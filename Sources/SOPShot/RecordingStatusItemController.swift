import AppKit
import Combine

@MainActor
final class RecordingStatusItemController: NSObject, ObservableObject {
    @Published private(set) var hasStatusItem = false

    private weak var model: SOPModel?
    private var statusItem: NSStatusItem?
    private var phaseSubscription: AnyCancellable?
    private var countSubscription: AnyCancellable?

    init(model: SOPModel) {
        self.model = model
        super.init()

        phaseSubscription = Publishers.CombineLatest3(
            model.$phase,
            model.$isInputMonitoringPermissionAlertPresented,
            model.$isDebugSession
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] phase, isPermissionAlertPresented, isDebugSession in
            Task { @MainActor in
                self?.synchronize(
                    phase: phase,
                    isPermissionAlertPresented: isPermissionAlertPresented,
                    isDebugSession: isDebugSession
                )
            }
        }

        countSubscription = model.$queuedScreenshotCount
            .receive(on: RunLoop.main)
            .sink { [weak self] count in
                Task { @MainActor in
                    guard self?.model?.phase == .recording,
                          self?.model?.isDebugSession != true else { return }
                    self?.updateCaptureTitle(count: count)
                }
            }
    }

    private func synchronize(
        phase: CapturePhase,
        isPermissionAlertPresented: Bool,
        isDebugSession: Bool
    ) {
        if isDebugSession {
            removeStatusItem()
            return
        }

        switch phase {
        case .recording:
            installStatusItemIfNeeded()
            updateCaptureTitle(count: model?.queuedScreenshotCount ?? 0)
            if !isPermissionAlertPresented {
                hideApplicationAfterCaptureStarts()
            }
        case .extracting:
            showExtractingStatus()
        case .preview, .idle:
            let shouldRestoreWindow = statusItem != nil
            removeStatusItem()
            if shouldRestoreWindow {
                showApplicationWindow()
            }
        case .preparing, .processing:
            break
        }
    }

    private func installStatusItemIfNeeded() {
        guard statusItem == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self
        item.button?.action = #selector(stopCaptureFromStatusItem(_:))
        item.button?.toolTip = "SOPShot 正在按操作截图，点击结束并检查截图"
        item.button?.setAccessibilityLabel("SOPShot 正在按操作截图。点击结束截图并查看预览。")
        statusItem = item
        hasStatusItem = true
    }

    private func updateCaptureTitle(count: Int) {
        let mark = NSMutableAttributedString(
            string: "▣",
            attributes: [
                .foregroundColor: NSColor.systemOrange,
                .font: NSFont.systemFont(ofSize: 11, weight: .semibold)
            ]
        )
        let label = count == 0 ? " SOPShot 截图" : " SOPShot \(count) 张"
        mark.append(
            NSAttributedString(
                string: label,
                attributes: [
                    .foregroundColor: NSColor.labelColor,
                    .font: NSFont.systemFont(ofSize: 13, weight: .medium)
                ]
            )
        )
        statusItem?.button?.attributedTitle = mark
        statusItem?.button?.toolTip = count == 0
            ? "SOPShot 正在按操作截图。点击或按关键键后会保存画面。"
            : "SOPShot 已截 \(count) 张。点击结束截图并检查。"
        statusItem?.button?.setAccessibilityLabel(
            count == 0
                ? "SOPShot 正在按操作截图。点击结束截图并查看预览。"
                : "SOPShot 已截 \(count) 张。点击结束截图并查看预览。"
        )
    }

    private func showExtractingStatus() {
        guard let button = statusItem?.button else { return }
        button.isEnabled = false
        button.attributedTitle = NSAttributedString(
            string: "SOPShot  整理截图",
            attributes: [
                .foregroundColor: NSColor.secondaryLabelColor,
                .font: NSFont.systemFont(ofSize: 13, weight: .medium)
            ]
        )
        button.toolTip = "SOPShot 正在整理截图，完成后会打开预览"
        button.setAccessibilityLabel("SOPShot 正在整理截图。完成后会打开截图预览。")
    }

    private func removeStatusItem() {
        guard let statusItem else { return }
        NSStatusBar.system.removeStatusItem(statusItem)
        self.statusItem = nil
        hasStatusItem = false
    }

    private func hideApplicationAfterCaptureStarts() {
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  self.model?.phase == .recording,
                  self.model?.isDebugSession != true,
                  self.model?.isInputMonitoringPermissionAlertPresented == false else { return }
            NSApp.hide(nil)
        }
    }

    private func showApplicationWindow() {
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            let window = NSApp.windows.first(where: { $0.title == "SOPShot" })
                ?? NSApp.windows.first(where: { $0.canBecomeKey })
            window?.makeKeyAndOrderFront(nil)
        }
    }

    @objc private func stopCaptureFromStatusItem(_ sender: Any?) {
        guard model?.phase == .recording else { return }
        showExtractingStatus()
        model?.stopRecording()
    }
}
