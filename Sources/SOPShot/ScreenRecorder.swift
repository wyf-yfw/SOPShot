import AppKit
import CoreGraphics
import ScreenCaptureKit

/// Captures one screen image for every recorded click or important key action.
///
/// There is intentionally no video writer here. A short delay lets the click
/// or key action reach the target application before the screenshot is
/// requested, while the event itself remains the timestamp and identity
/// associated with the image.
@MainActor
final class ClickScreenshotSession {
    private let postInputDelayNanoseconds: UInt64 = 50_000_000
    private let maxSnapshotDimension = 2560

    private var contentFilter: SCContentFilter?
    private var screenshotConfiguration: SCStreamConfiguration?
    private var displayID: CGDirectDisplayID?
    private var pendingCaptures: [Task<CapturedFrame?, Never>] = []
    private var isActive = false

    /// Fires whenever the number of queued screenshots changes during a session.
    var onQueuedCountChanged: ((Int) -> Void)?
    var triggerPolicy: ScreenshotTriggerPolicy = .default

    var queuedScreenshotCount: Int {
        pendingCaptures.count + pendingGestures.count
    }

    func start() async throws {
        cancelPendingCaptures()
        contentFilter = nil
        screenshotConfiguration = nil
        displayID = nil
        isActive = false
        notifyQueuedCountChanged()

        guard #available(macOS 13.0, *) else { throw CaptureError.unsupported }
        if !CGPreflightScreenCaptureAccess() {
            _ = CGRequestScreenCaptureAccess()
        }

        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            if !CGPreflightScreenCaptureAccess() {
                throw CaptureError.permissionDenied
            }
            throw CaptureError.contentUnavailable(error.localizedDescription)
        }

        guard let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() }) ?? content.displays.first else {
            throw CaptureError.contentUnavailable("系统没有返回可截图的显示器。")
        }

        let pixelWidth = Int(CGDisplayPixelsWide(display.displayID))
        let pixelHeight = Int(CGDisplayPixelsHigh(display.displayID))
        guard pixelWidth > 0, pixelHeight > 0 else {
            throw CaptureError.contentUnavailable("系统没有返回有效的显示器像素尺寸。")
        }

        let ownWindows = content.windows.filter {
            $0.owningApplication?.bundleIdentifier == Bundle.main.bundleIdentifier
        }
        let filter = SCContentFilter(display: display, excludingWindows: ownWindows)
        let outputSize = scaledDimensions(width: pixelWidth, height: pixelHeight)
        let configuration = SCStreamConfiguration()
        configuration.width = outputSize.width
        configuration.height = outputSize.height
        configuration.showsCursor = true
        configuration.capturesAudio = false
        if #available(macOS 14.0, *) {
            configuration.scalesToFit = true
            configuration.preservesAspectRatio = true
        }

        contentFilter = filter
        screenshotConfiguration = configuration
        displayID = display.displayID
        isActive = true
        notifyQueuedCountChanged()
    }

    private struct PendingGesture {
        var event: InputTimelineEvent
        var task: Task<CapturedFrame?, Never>
    }

    private var pendingGestures: [InputEventKind: PendingGesture] = [:]

    func enqueueCaptureEvent(_ event: InputTimelineEvent) {
        guard isActive,
              contentFilter != nil,
              screenshotConfiguration != nil,
              displayID != nil else {
            return
        }

        if triggerPolicy.shouldCoalesce(event.kind) {
            scheduleCoalescedCapture(event)
            return
        }

        guard triggerPolicy.shouldCaptureImmediately(event.kind) else { return }
        appendCapture(event, delay: postInputDelayNanoseconds)
    }

    private func makeCaptureTask(
        for event: InputTimelineEvent,
        delayNanoseconds: UInt64,
        coalesced: Bool = false
    ) -> Task<CapturedFrame?, Never> {
        Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: delayNanoseconds)
            } catch {
                return nil
            }
            guard let self,
                  let contentFilter = self.contentFilter,
                  let configuration = self.screenshotConfiguration,
                  let displayID = self.displayID else {
                return nil
            }
            let frame = await self.capture(
                event: event,
                contentFilter: contentFilter,
                configuration: configuration,
                displayID: displayID
            )
            if coalesced {
                // Hand the finished gesture over to the ordered list so a later
                // gesture of the same kind cannot discard an image already taken.
                if self.pendingGestures[event.kind]?.event.id == event.id {
                    self.pendingGestures[event.kind] = nil
                }
                if let frame {
                    self.pendingCaptures.append(Task<CapturedFrame?, Never> { frame })
                }
                self.notifyQueuedCountChanged()
            }
            return frame
        }
    }

    private func appendCapture(_ event: InputTimelineEvent, delay: UInt64) {
        pendingCaptures.append(makeCaptureTask(for: event, delayNanoseconds: delay))
        notifyQueuedCountChanged()
    }

    /// Keeps only the trailing screenshot of a continuous gesture.
    /// Every incoming event cancels the pending one, so a burst of scrolls
    /// results in a single image captured after the gesture settles.
    private func scheduleCoalescedCapture(_ event: InputTimelineEvent) {
        pendingGestures[event.kind]?.task.cancel()
        pendingGestures[event.kind]?.event = event
        pendingGestures[event.kind]?.task = makeCaptureTask(
            for: event,
            delayNanoseconds: postInputDelayNanoseconds
                + UInt64(event.kind.screenshotSettleDelay * 1_000_000_000),
            coalesced: true
        )
        notifyQueuedCountChanged()
    }

    func finish() async -> [CapturedFrame] {
        isActive = false

        let gestureCaptures = pendingGestures.values.map(\.task)
        pendingGestures.removeAll()

        let captures = pendingCaptures + gestureCaptures
        pendingCaptures = []
        notifyQueuedCountChanged()

        var frames: [CapturedFrame] = []
        frames.reserveCapacity(captures.count)
        for capture in captures {
            if let frame = await capture.value {
                frames.append(frame)
            }
        }
        frames.sort { $0.timestamp < $1.timestamp }

        contentFilter = nil
        screenshotConfiguration = nil
        displayID = nil
        return frames
    }

    private func capture(
        event: InputTimelineEvent,
        contentFilter: SCContentFilter,
        configuration: SCStreamConfiguration,
        displayID: CGDirectDisplayID
    ) async -> CapturedFrame? {
        let cgImage: CGImage?
        if #available(macOS 14.0, *) {
            cgImage = await withCheckedContinuation { continuation in
                SCScreenshotManager.captureImage(
                    contentFilter: contentFilter,
                    configuration: configuration
                ) { image, _ in
                    continuation.resume(returning: image)
                }
            }
        } else {
            // SCScreenshotManager was introduced in macOS 14. Keep the macOS
            // 13 fallback functional, even though it cannot exclude our own
            // window from the full-display image.
            cgImage = CGDisplayCreateImage(displayID)
        }

        guard let cgImage else { return nil }
        let image = NSImage(
            cgImage: cgImage,
            size: CGSize(width: cgImage.width, height: cgImage.height)
        )
        return CapturedFrame(
            image: image,
            timestamp: event.timestamp,
            primaryInputEvent: event
        )
    }

    private func scaledDimensions(width: Int, height: Int) -> (width: Int, height: Int) {
        let scale = min(
            1.0,
            Double(maxSnapshotDimension) / Double(max(width, height))
        )
        return (
            max(2, Int((Double(width) * scale).rounded(.down))),
            max(2, Int((Double(height) * scale).rounded(.down)))
        )
    }

    private func cancelPendingCaptures() {
        pendingGestures.values.forEach { $0.task.cancel() }
        pendingGestures.removeAll()
        pendingCaptures.forEach { $0.cancel() }
        pendingCaptures = []
        notifyQueuedCountChanged()
    }

    private func notifyQueuedCountChanged() {
        onQueuedCountChanged?(queuedScreenshotCount)
    }
}
