import AppKit
import Combine
import SwiftUI

@MainActor
final class OnboardingFlowController {
    private let model: SOPModel
    private let onFinish: (Bool) -> Void

    private var screen: NSScreen?
    private var orbFrame: NSRect = .zero
    private var overlayPanel: OnboardingOverlayPanel?
    private var overlayView: OnboardingDimmerView?
    private var stepSubscription: AnyCancellable?
    private var escapeMonitor: Any?
    private var isStopping = false

    init(model: SOPModel, onFinish: @escaping (Bool) -> Void) {
        self.model = model
        self.onFinish = onFinish
        stepSubscription = model.$guidedTourStep
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.render()
            }
    }

    func start(on screen: NSScreen, orbFrame: NSRect) {
        self.screen = screen
        self.orbFrame = orbFrame
        if model.guidedTourStep == nil {
            model.beginGuidedTour()
        }
        ensureOverlay(on: screen)
        installEscapeMonitor()
        render()
    }

    func updateAnchor(on screen: NSScreen, orbFrame: NSRect) {
        let screenChanged = self.screen !== screen
        self.screen = screen
        self.orbFrame = orbFrame
        if screenChanged {
            removeOverlay()
            ensureOverlay(on: screen)
        } else {
            overlayPanel?.setFrame(screen.frame, display: false)
        }
        render()
    }

    /// NSMenu runs its own tracking loop, so the Combine delivery scheduled on the
    /// default run loop may not arrive until the menu closes. The menu delegate calls
    /// this synchronously as soon as the guided menu opens.
    func refresh() {
        render()
        overlayView?.displayIfNeeded()
    }

    func stop() {
        guard !isStopping else { return }
        isStopping = true
        removeEscapeMonitor()
        stepSubscription?.cancel()
        stepSubscription = nil
        removeOverlay()
        isStopping = false
    }

    private func ensureOverlay(on screen: NSScreen) {
        if let overlayPanel {
            overlayPanel.setFrame(screen.frame, display: true)
            return
        }
        let panel = OnboardingOverlayPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        // Let clicks reach the real orb / app windows underneath.
        panel.ignoresMouseEvents = true
        panel.appearance = NSAppearance(named: .darkAqua)

        let view = OnboardingDimmerView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.autoresizingMask = [.width, .height]
        panel.contentView = view

        overlayPanel = panel
        overlayView = view
        panel.orderFrontRegardless()
    }

    private func removeOverlay() {
        overlayPanel?.orderOut(nil)
        overlayPanel = nil
        overlayView = nil
    }

    private func installEscapeMonitor() {
        removeEscapeMonitor()
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.cancelTour()
                return nil
            }
            return event
        }
    }

    private func removeEscapeMonitor() {
        if let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
            self.escapeMonitor = nil
        }
    }

    private func cancelTour() {
        stop()
        onFinish(false)
    }

    private func render() {
        guard let screen, let overlayPanel, let overlayView else { return }
        guard let step = model.guidedTourStep else {
            overlayPanel.orderOut(nil)
            return
        }

        // While the orb menu is open (steps 2–3), don't orderFront — that can cover or
        // interrupt NSMenu tracking and leave the coach copy one step behind.
        let menuLikelyOpen = step == .pickModel || step == .startCapture
        overlayPanel.setFrame(screen.frame, display: false)
        if !menuLikelyOpen || !overlayPanel.isVisible {
            overlayPanel.orderFrontRegardless()
        }

        let focus: OnboardingDimmerView.Focus
        switch step {
        case .openOrb, .startCapture, .stopCapture:
            focus = .orb(localRect(for: orbFrame))
        case .pickModel, .deleteScreenshot, .generate, .exportMarkdown, .finished:
            focus = .none
        }

        overlayView.configure(
            focus: focus,
            title: step.title,
            message: step.message,
            calloutAnchor: focusAnchor(for: step)
        )
        overlayView.needsDisplay = true
    }

    private func focusAnchor(for step: GuidedTourStep) -> NSRect? {
        switch step {
        case .openOrb, .stopCapture:
            return localRect(for: orbFrame)
        case .pickModel, .startCapture:
            guard let screen else { return nil }
            let menuSize = NSSize(width: 220, height: 240)
            let visibleFrame = screen.visibleFrame
            let hasRoomBelowOrb = orbFrame.minY - visibleFrame.minY >= menuSize.height + 12
            let menuY = hasRoomBelowOrb
                ? orbFrame.minY - menuSize.height
                : orbFrame.maxY + 8
            let menuFrame = NSRect(
                x: orbFrame.minX - 8,
                y: menuY,
                width: menuSize.width,
                height: menuSize.height
            )
            return localRect(for: menuFrame)
        case .deleteScreenshot, .generate, .exportMarkdown, .finished:
            if let window = NSApp.windows.first(where: { $0.title == "SOPShot" && !($0 is NSPanel) && $0.isVisible }) {
                return localRect(for: window.frame)
            }
            return screen.map { localRect(for: $0.visibleFrame) }
        }
    }

    private func localRect(for screenRect: NSRect) -> NSRect {
        guard let screen else { return screenRect }
        return NSRect(
            x: screenRect.minX - screen.frame.minX,
            y: screenRect.minY - screen.frame.minY,
            width: screenRect.width,
            height: screenRect.height
        )
    }
}

private final class OnboardingOverlayPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class OnboardingDimmerView: NSView {
    enum Focus {
        case none
        case orb(NSRect)
    }

    private var focus: Focus = .none
    private var calloutAnchor: NSRect?
    private var title = ""
    private var message = ""

    func configure(focus: Focus, title: String, message: String, calloutAnchor: NSRect? = nil) {
        self.focus = focus
        self.calloutAnchor = calloutAnchor
        self.title = title
        self.message = message
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.58).setFill()
        bounds.fill()

        if case .orb(let rect) = focus {
            drawOrbCutout(rect)
        }

        drawInstruction()
    }

    private func drawOrbCutout(_ rect: NSRect) {
        let spotlight = rect.insetBy(dx: -10, dy: -10)
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.setBlendMode(.clear)
        NSBezierPath(ovalIn: spotlight).fill()
        context.restoreGState()

        NSColor.systemOrange.setStroke()
        let ring = NSBezierPath(ovalIn: spotlight)
        ring.lineWidth = 2
        ring.stroke()
    }

    private func drawInstruction() {
        let width = instructionWidth()
        let messageAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.white.withAlphaComponent(0.86),
            .paragraphStyle: paragraphStyle(lineSpacing: 3)
        ]
        let messageHeight = (message as NSString).boundingRect(
            with: NSSize(width: width - 40, height: 220),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: messageAttributes
        ).height
        let height = max(118, ceil(messageHeight) + 68)
        let rect = instructionRect(width: width, height: height)

        NSColor(calibratedWhite: 0.11, alpha: 0.98).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10).fill()
        NSColor.white.withAlphaComponent(0.20).setStroke()
        let border = NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10)
        border.lineWidth = 1
        border.stroke()

        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        (title as NSString).draw(
            in: NSRect(x: rect.minX + 20, y: rect.maxY - 35, width: rect.width - 40, height: 20),
            withAttributes: titleAttributes
        )
        (message as NSString).draw(
            with: NSRect(x: rect.minX + 20, y: rect.minY + 25, width: rect.width - 40, height: rect.height - 62),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: messageAttributes,
            context: nil
        )
        ("按 Esc 可退出引导" as NSString).draw(
            in: NSRect(x: rect.minX + 20, y: rect.minY + 8, width: rect.width - 40, height: 14),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 10),
                .foregroundColor: NSColor.white.withAlphaComponent(0.48)
            ]
        )
    }

    private func instructionRect(width: CGFloat, height: CGFloat) -> NSRect {
        let inset: CGFloat = 28
        let gap: CGFloat = 22
        let maxX = bounds.maxX - inset
        let maxY = bounds.maxY - inset

        let preferredTarget = calloutAnchor ?? {
            if case .orb(let target) = focus { return target }
            return nil
        }()

        guard let target = preferredTarget else {
            return NSRect(
                x: bounds.midX - width / 2,
                y: bounds.midY - height / 2,
                width: width,
                height: height
            )
        }

        let isLargeTarget = target.width >= bounds.width * 0.45
            || target.height >= bounds.height * 0.60
        let rightX = target.maxX + gap
        let leftX = target.minX - width - gap
        let x: CGFloat
        if rightX + width <= maxX {
            x = rightX
        } else if leftX >= inset {
            x = leftX
        } else if isLargeTarget {
            // A large target is usually the preview/result window. Keep the card
            // against the nearest screen edge instead of falling back to its center.
            let clampedRight = min(max(inset, rightX), maxX - width)
            let clampedLeft = min(max(inset, leftX), maxX - width)
            let rightOverlap = max(
                0,
                min(target.maxX, clampedRight + width) - max(target.minX, clampedRight)
            )
            let leftOverlap = max(
                0,
                min(target.maxX, clampedLeft + width) - max(target.minX, clampedLeft)
            )
            x = rightOverlap <= leftOverlap ? clampedRight : clampedLeft
        } else {
            x = min(max(inset, target.midX - width / 2), maxX - width)
        }

        // Align the card with the relevant control/menu, not an arbitrary screen
        // corner. Clamp it to the visible panel so every tour stage stays in view.
        let y = min(max(inset, target.midY - height / 2), maxY - height)

        return NSRect(
            x: min(max(inset, x), maxX - width),
            y: min(max(inset, y), maxY - height),
            width: width,
            height: height
        )
    }

    private func instructionWidth() -> CGFloat {
        let standardWidth: CGFloat = 340
        let inset: CGFloat = 28
        let gap: CGFloat = 22

        guard let target = calloutAnchor,
              target.width >= bounds.width * 0.45 || target.height >= bounds.height * 0.60 else {
            return standardWidth
        }

        let rightSpace = bounds.maxX - inset - target.maxX - gap
        let leftSpace = target.minX - gap - inset
        let sideSpace = max(rightSpace, leftSpace)
        if sideSpace >= 220 {
            return min(standardWidth, sideSpace)
        }
        return min(standardWidth, bounds.width - inset * 2)
    }

    private func paragraphStyle(lineSpacing: CGFloat) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = lineSpacing
        style.lineBreakMode = .byWordWrapping
        return style
    }
}
