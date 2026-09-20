import AppKit
import Combine
import QuartzCore
import SwiftUI

@MainActor
final class CaptureOrbController: NSObject, ObservableObject {
    @Published private(set) var isOrbVisible = false

    private weak var model: SOPModel?
    private var stateSubscription: AnyCancellable?
    private var countSubscription: AnyCancellable?
    private var sheetSubscription: AnyCancellable?

    private var orbWindow: NSPanel?
    private var morphWindow: NSPanel?
    private var orbButton: CaptureOrbButton?
    private var savedMainOrigin: NSPoint?
    private var savedScreen: NSScreen?
    private var isCollapsing = false
    private var isRestoring = false
    private var hasCollapsedForSession = false
    private var orbMode: OrbMode = .idle

    private let orbSize: CGFloat = 54
    private let blobLaunchSize: CGFloat = 76
    private let orbMargin: CGFloat = 18
    private let previewContentSize = NSSize(width: 1120, height: 720)
    private let idleContentSize = NSSize(width: 400, height: 210)

    private weak var boundMainWindow: NSWindow?
    private var windowWatchers: [NSObjectProtocol] = []
    private var launchHideRetries = 0

    private var auxiliaryPanel: NSPanel?
    private var auxiliaryKind: AuxiliaryKind?
    private var closingAuxiliaryProgrammatically = false

    private enum AuxiliaryKind: Equatable {
        case help
        case modelSettings
        case captureSettings
        case debug
    }

    private enum OrbMode {
        case idle
        case preparing
        case recording
        case extracting
    }

    init(model: SOPModel) {
        self.model = model
        super.init()

        stateSubscription = Publishers.CombineLatest4(
            model.$phase,
            model.$isInputMonitoringPermissionAlertPresented,
            model.$isDebugSession,
            Publishers.CombineLatest(model.$steps, model.$isEditing)
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] phase, isPermissionAlertPresented, isDebugSession, stepsAndEditing in
            Task { @MainActor in
                self?.synchronize(
                    phase: phase,
                    isPermissionAlertPresented: isPermissionAlertPresented,
                    isDebugSession: isDebugSession,
                    steps: stepsAndEditing.0,
                    isEditing: stepsAndEditing.1
                )
            }
        }

        sheetSubscription = Publishers.CombineLatest(
            Publishers.CombineLatest4(
                model.$isModelSettingsPresented,
                model.$isCaptureSettingsPresented,
                model.$isDebugAssistantPresented,
                model.$isHelpPresented
            ),
            Publishers.CombineLatest4(
                model.$phase,
                model.$steps,
                model.$isEditing,
                model.$isDebugSession
            )
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] sheets, state in
            Task { @MainActor in
                let prefersOrb = state.0 == .idle && state.1.isEmpty && !state.2 && !state.3
                self?.synchronizeAuxiliaryPanels(
                    prefersOrbShell: prefersOrb,
                    modelSettings: sheets.0,
                    captureSettings: sheets.1,
                    debug: sheets.2,
                    help: sheets.3
                )
            }
        }

        countSubscription = model.$queuedScreenshotCount
            .receive(on: RunLoop.main)
            .sink { [weak self] count in
                Task { @MainActor in
                    guard self?.orbMode == .recording else { return }
                    self?.updateOrbAppearance(count: count)
                }
            }

        let center = NotificationCenter.default
        windowWatchers.append(center.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.handleWindowBecameVisible(notification.object as? NSWindow)
            }
        })
        windowWatchers.append(center.addObserver(
            forName: NSWindow.didBecomeMainNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.handleWindowBecameVisible(notification.object as? NSWindow)
            }
        })

        DispatchQueue.main.async { [weak self] in
            self?.ensureIdleOrbShellIfNeeded()
        }
    }

    func bindMainWindow(_ window: NSWindow?) {
        guard let window, !(window is NSPanel) else { return }
        boundMainWindow = window
        window.identifier = NSUserInterfaceItemIdentifier("sopshot.main")
    }

    func ensureIdleOrbShellIfNeeded() {
        guard model?.prefersOrbShell == true else { return }
        enterIdleOrb(fromCaptureSession: false)
        // SwiftUI may create/show the host window a moment later.
        if sopshotWindow() == nil, launchHideRetries < 20 {
            launchHideRetries += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.ensureIdleOrbShellIfNeeded()
            }
        } else {
            launchHideRetries = 0
        }
    }

    private func handleWindowBecameVisible(_ window: NSWindow?) {
        guard model?.prefersOrbShell == true else { return }
        guard let window, !(window is NSPanel) else { return }
        if window === auxiliaryPanel { return }
        bindMainWindow(window)
        hideMainWindow()
        presentOrb(mode: .idle, animated: orbWindow == nil)
    }

    private func synchronize(
        phase: CapturePhase,
        isPermissionAlertPresented: Bool,
        isDebugSession: Bool,
        steps: [SOPStep],
        isEditing: Bool
    ) {
        if isDebugSession {
            tearDownOrb(animated: false)
            hasCollapsedForSession = false
            showMainWindow(contentSize: idleContentSize, animated: false)
            return
        }

        let prefersIdleOrb = phase == .idle && steps.isEmpty && !isEditing

        switch phase {
        case .idle:
            if prefersIdleOrb {
                enterIdleOrb(fromCaptureSession: hasCollapsedForSession)
                hasCollapsedForSession = false
            } else {
                tearDownOrb(animated: false)
                hasCollapsedForSession = false
                showMainWindow(
                    contentSize: steps.isEmpty ? idleContentSize : previewContentSize,
                    animated: false
                )
            }

        case .preparing:
            hasCollapsedForSession = true
            hideMainWindow()
            presentOrb(mode: .preparing, animated: orbWindow == nil)

        case .recording:
            if isPermissionAlertPresented {
                tearDownOrb(animated: false)
                hasCollapsedForSession = false
                showMainWindow(contentSize: idleContentSize, animated: false)
                return
            }
            if orbWindow != nil || hasCollapsedForSession {
                hasCollapsedForSession = true
                hideMainWindow()
                presentOrb(mode: .recording, animated: false)
            } else {
                collapseMainWindowToOrb()
            }

        case .extracting:
            hasCollapsedForSession = true
            presentOrb(mode: .extracting, animated: false)

        case .preview:
            let shouldAnimate = hasCollapsedForSession || orbWindow != nil
            hasCollapsedForSession = false
            if shouldAnimate {
                restoreMainWindow(animated: true, contentSize: previewContentSize)
            } else {
                tearDownOrb(animated: false)
                showMainWindow(contentSize: previewContentSize, animated: false)
            }

        case .processing:
            tearDownOrb(animated: false)
            showMainWindow(contentSize: previewContentSize, animated: false)
        }
    }

    private func enterIdleOrb(fromCaptureSession: Bool) {
        hideMainWindow()
        if fromCaptureSession, let orbWindow, orbMode != .idle {
            presentOrb(mode: .idle, animated: false)
            orbWindow.orderFrontRegardless()
            return
        }
        presentOrb(mode: .idle, animated: orbWindow == nil)
    }

    private func synchronizeAuxiliaryPanels(
        prefersOrbShell: Bool,
        modelSettings: Bool,
        captureSettings: Bool,
        debug: Bool,
        help: Bool
    ) {
        guard prefersOrbShell else {
            closeAuxiliaryPanel()
            return
        }

        let kind: AuxiliaryKind?
        if help {
            kind = .help
        } else if modelSettings {
            kind = .modelSettings
        } else if captureSettings {
            kind = .captureSettings
        } else if debug && FeatureFlags.showsDebugAssistant {
            kind = .debug
        } else {
            kind = nil
        }

        guard let kind else {
            closeAuxiliaryPanel()
            return
        }

        if auxiliaryKind == kind, auxiliaryPanel != nil {
            auxiliaryPanel?.makeKeyAndOrderFront(nil)
            return
        }

        closeAuxiliaryPanel()
        presentAuxiliaryPanel(kind: kind)
    }

    private func presentAuxiliaryPanel(kind: AuxiliaryKind) {
        guard let model else { return }

        let title: String
        let size: NSSize
        let root: AnyView
        switch kind {
        case .help:
            title = "使用说明"
            size = NSSize(width: 520, height: 480)
            root = AnyView(
                OnboardingView(
                    onLoadDemo: { [weak self] in
                        model.completeOnboarding()
                        self?.closeAuxiliaryPanel()
                        DispatchQueue.main.async {
                            model.loadDemo()
                        }
                    },
                    onDismiss: { [weak self] in
                        model.completeOnboarding()
                        self?.closeAuxiliaryPanel()
                    }
                )
                .preferredColorScheme(.dark)
            )
        case .modelSettings:
            title = "模型设置"
            size = NSSize(width: 640, height: 480)
            root = AnyView(ModelSettingsView().environmentObject(model).preferredColorScheme(.dark))
        case .captureSettings:
            title = "截图设置"
            size = NSSize(width: 520, height: 520)
            root = AnyView(CaptureSettingsView().environmentObject(model).preferredColorScheme(.dark))
        case .debug:
            title = "调试助手"
            size = NSSize(width: 420, height: 520)
            root = AnyView(DebugAssistantView().environmentObject(model).preferredColorScheme(.dark))
        }

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = title
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.delegate = self

        let host = NSHostingView(rootView: root)
        host.frame = NSRect(origin: .zero, size: size)
        panel.contentView = host
        panel.setContentSize(size)
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        auxiliaryPanel = panel
        auxiliaryKind = kind
    }

    private func closeAuxiliaryPanel() {
        guard let panel = auxiliaryPanel else {
            auxiliaryKind = nil
            return
        }
        closingAuxiliaryProgrammatically = true
        panel.delegate = nil
        panel.orderOut(nil)
        auxiliaryPanel = nil
        auxiliaryKind = nil
        closingAuxiliaryProgrammatically = false
    }

    private func clearPresentationFlag(for kind: AuxiliaryKind) {
        switch kind {
        case .help:
            model?.isHelpPresented = false
        case .modelSettings:
            model?.isModelSettingsPresented = false
        case .captureSettings:
            model?.isCaptureSettingsPresented = false
        case .debug:
            model?.isDebugAssistantPresented = false
        }
    }

    private func collapseMainWindowToOrb() {
        guard let mainWindow = sopshotWindow() else {
            presentOrb(mode: .recording, animated: false)
            hasCollapsedForSession = true
            return
        }

        isCollapsing = true
        hasCollapsedForSession = true
        savedMainOrigin = mainWindow.frame.origin
        savedScreen = mainWindow.screen ?? NSScreen.main

        let windowFrame = mainWindow.frame
        let endFrame = orbFrame(for: mainWindow.screen ?? NSScreen.main)
        let launchFrame = centeredSquare(size: blobLaunchSize, in: windowFrame)
        let morph = makeMorphPanel(startingAt: launchFrame, cornerRadius: blobLaunchSize / 2)
        morphWindow = morph
        morph.alphaValue = 0
        morph.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            mainWindow.animator().alphaValue = 0
            morph.animator().alphaValue = 1
        }, completionHandler: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                mainWindow.orderOut(nil)
                mainWindow.alphaValue = 1

                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.42
                    context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    morph.animator().setFrame(endFrame, display: true)
                }, completionHandler: { [weak self] in
                    Task { @MainActor in
                        guard let self else { return }
                        morph.orderOut(nil)
                        self.morphWindow = nil
                        self.presentOrb(mode: .recording, at: endFrame, animated: false)
                        self.isCollapsing = false
                    }
                })
            }
        })
    }

    private func restoreMainWindow(animated: Bool, contentSize: NSSize) {
        guard !isRestoring else { return }
        isRestoring = true

        let mainWindow = sopshotWindow()
        let screen = savedScreen ?? mainWindow?.screen ?? NSScreen.main
        let targetFrame = windowFrame(
            forContentSize: contentSize,
            on: screen,
            preferredOrigin: savedMainOrigin,
            using: mainWindow
        )

        morphWindow?.orderOut(nil)
        morphWindow = nil

        if animated, let mainWindow {
            let fadeOrb = orbWindow
            orbWindow = nil
            orbButton = nil
            isOrbVisible = false

            mainWindow.setFrame(targetFrame, display: false)
            mainWindow.alphaValue = 0
            mainWindow.orderFront(nil)

            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.2
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                fadeOrb?.animator().alphaValue = 0
                if let frame = fadeOrb?.frame {
                    fadeOrb?.animator().setFrame(frame.insetBy(dx: 8, dy: 8), display: true)
                }
            }, completionHandler: { [weak self] in
                Task { @MainActor in
                    fadeOrb?.orderOut(nil)
                    NSAnimationContext.runAnimationGroup({ context in
                        context.duration = 0.28
                        context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                        mainWindow.animator().alphaValue = 1
                    }, completionHandler: {
                        Task { @MainActor [weak self] in
                            NSApp.activate(ignoringOtherApps: true)
                            mainWindow.makeKeyAndOrderFront(nil)
                            self?.isRestoring = false
                            self?.savedMainOrigin = nil
                            self?.savedScreen = nil
                        }
                    })
                }
            })
        } else {
            tearDownOrb(animated: false)
            showMainWindow(contentSize: contentSize, animated: false)
            isRestoring = false
            savedMainOrigin = nil
            savedScreen = nil
        }
    }

    private func presentOrb(mode: OrbMode, animated: Bool) {
        presentOrb(mode: mode, at: orbWindow?.frame ?? defaultOrbFrame(), animated: animated)
    }

    private func presentOrb(mode: OrbMode, at frame: NSRect, animated: Bool) {
        orbMode = mode
        if orbWindow == nil {
            let panel = NSPanel(
                contentRect: frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.level = .statusBar
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            panel.isFloatingPanel = true
            panel.hidesOnDeactivate = false
            panel.becomesKeyOnlyIfNeeded = true
            panel.animationBehavior = .none
            panel.ignoresMouseEvents = false

            let button = CaptureOrbButton(frame: NSRect(origin: .zero, size: frame.size))
            button.target = self
            button.action = #selector(orbClicked(_:))
            button.sendAction(on: .leftMouseDown)
            panel.contentView = button

            orbWindow = panel
            orbButton = button
            isOrbVisible = true
        }

        updateOrbAppearance(count: model?.queuedScreenshotCount ?? 0)
        orbWindow?.setFrame(frame, display: true)
        if animated {
            orbWindow?.alphaValue = 0
            orbWindow?.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.16
                orbWindow?.animator().alphaValue = 1
            }
        } else {
            orbWindow?.alphaValue = 1
            orbWindow?.orderFrontRegardless()
        }
    }

    private func updateOrbAppearance(count: Int) {
        let extracting = orbMode == .extracting
        let preparing = orbMode == .preparing
        orbButton?.apply(
            count: count,
            extracting: extracting,
            preparing: preparing,
            idle: orbMode == .idle
        )

        let tip: String
        switch orbMode {
        case .idle:
            tip = "SOPShot：点击打开菜单"
        case .preparing:
            tip = "SOPShot 正在准备截图"
        case .recording:
            tip = count == 0
                ? "SOPShot 正在按操作截图。点击结束并检查截图。"
                : "SOPShot 已截 \(count) 张。点击结束截图并检查。"
        case .extracting:
            tip = "SOPShot 正在整理截图，完成后会打开预览"
        }
        orbWindow?.contentView?.toolTip = tip
        orbButton?.toolTip = tip
        orbButton?.isEnabled = orbMode != .extracting && orbMode != .preparing
        orbButton?.setAccessibilityLabel(tip)
    }

    @objc private func orbClicked(_ sender: Any?) {
        switch orbMode {
        case .idle:
            showIdleMenu()
        case .recording:
            updateOrbAppearance(count: model?.queuedScreenshotCount ?? 0)
            orbMode = .extracting
            updateOrbAppearance(count: model?.queuedScreenshotCount ?? 0)
            model?.stopRecording()
        case .preparing, .extracting:
            break
        }
    }

    private func showIdleMenu() {
        guard let button = orbButton else { return }
        let menu = NSMenu()
        menu.autoenablesItems = false

        let startItem = NSMenuItem(
            title: "开始截图",
            action: #selector(menuStartCapture(_:)),
            keyEquivalent: "r"
        )
        startItem.keyEquivalentModifierMask = [.command, .shift]
        startItem.target = self
        menu.addItem(startItem)

        menu.addItem(.separator())

        let modelRoot = NSMenuItem(title: "选择模型", action: nil, keyEquivalent: "")
        let modelMenu = NSMenu()
        let options = model?.configuredModelOptions ?? []
        if options.isEmpty {
            let empty = NSMenuItem(title: "尚未配置视觉模型", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            modelMenu.addItem(empty)
        } else {
            for option in options {
                let item = NSMenuItem(
                    title: "\(option.provider.displayName) · \(option.modelLabel)",
                    action: #selector(menuSelectModel(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = option.id
                if option.id == model?.selectedConfiguredModelID {
                    item.state = .on
                }
                modelMenu.addItem(item)
            }
        }
        menu.setSubmenu(modelMenu, for: modelRoot)
        menu.addItem(modelRoot)

        let captureSettings = NSMenuItem(
            title: "截图设置…",
            action: #selector(menuCaptureSettings(_:)),
            keyEquivalent: ""
        )
        captureSettings.target = self
        menu.addItem(captureSettings)

        let modelSettings = NSMenuItem(
            title: "模型设置…",
            action: #selector(menuModelSettings(_:)),
            keyEquivalent: ""
        )
        modelSettings.target = self
        menu.addItem(modelSettings)

        menu.addItem(.separator())

        let help = NSMenuItem(
            title: "使用说明…",
            action: #selector(menuHelp(_:)),
            keyEquivalent: ""
        )
        help.target = self
        menu.addItem(help)

        if FeatureFlags.showsDebugAssistant {
            let debug = NSMenuItem(
                title: "调试助手…",
                action: #selector(menuDebug(_:)),
                keyEquivalent: ""
            )
            debug.target = self
            menu.addItem(debug)
        }

        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: "退出 SOPShot",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quit.keyEquivalentModifierMask = [.command]
        menu.addItem(quit)

        let point = NSPoint(x: 0, y: button.bounds.height + 2)
        menu.popUp(positioning: nil, at: point, in: button)
    }

    @objc private func menuStartCapture(_ sender: Any?) {
        model?.startRecording()
    }

    @objc private func menuSelectModel(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let option = model?.configuredModelOptions.first(where: { $0.id == id }) else { return }
        model?.selectConfiguredModel(option)
    }

    @objc private func menuCaptureSettings(_ sender: Any?) {
        model?.isCaptureSettingsPresented = true
    }

    @objc private func menuModelSettings(_ sender: Any?) {
        model?.isModelSettingsPresented = true
    }

    @objc private func menuHelp(_ sender: Any?) {
        model?.isHelpPresented = true
    }

    @objc private func menuDebug(_ sender: Any?) {
        model?.isDebugAssistantPresented = true
    }

    private func hideMainWindow() {
        let windows = NSApp.windows.filter { window in
            !(window is NSPanel)
                && window !== auxiliaryPanel
                && window !== orbWindow
                && window !== morphWindow
        }
        for window in windows {
            if boundMainWindow == nil {
                boundMainWindow = window
            }
            savedMainOrigin = window.frame.origin
            savedScreen = window.screen ?? NSScreen.main
            window.alphaValue = 0
            window.orderOut(nil)
            window.alphaValue = 1
        }
    }

    private func showMainWindow(contentSize: NSSize, animated: Bool) {
        guard let window = sopshotWindow() else { return }
        let frame = windowFrame(
            forContentSize: contentSize,
            on: savedScreen ?? window.screen ?? NSScreen.main,
            preferredOrigin: savedMainOrigin,
            using: window
        )
        window.alphaValue = 0
        window.setFrame(frame, display: true)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                window.animator().alphaValue = 1
            }
        } else {
            window.alphaValue = 1
        }
    }

    private func tearDownOrb(animated: Bool) {
        let panel = orbWindow
        orbWindow = nil
        orbButton = nil
        isOrbVisible = false
        morphWindow?.orderOut(nil)
        morphWindow = nil

        guard let panel else { return }
        if animated {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.15
                panel.animator().alphaValue = 0
            }, completionHandler: {
                panel.orderOut(nil)
            })
        } else {
            panel.orderOut(nil)
        }
    }

    private func makeMorphPanel(startingAt frame: NSRect, cornerRadius: CGFloat) -> NSPanel {
        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.ignoresMouseEvents = true

        let host = NSView(frame: NSRect(origin: .zero, size: frame.size))
        host.wantsLayer = true
        host.layer?.backgroundColor = NSColor.systemOrange.cgColor
        host.layer?.cornerRadius = cornerRadius
        host.layer?.masksToBounds = true
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        return panel
    }

    private func centeredSquare(size: CGFloat, in rect: NSRect) -> NSRect {
        NSRect(
            x: rect.midX - size / 2,
            y: rect.midY - size / 2,
            width: size,
            height: size
        )
    }

    private func windowFrame(
        forContentSize contentSize: NSSize,
        on screen: NSScreen?,
        preferredOrigin: NSPoint?,
        using window: NSWindow?
    ) -> NSRect {
        let contentRect = NSRect(origin: .zero, size: contentSize)
        var frame: NSRect
        if let window {
            frame = window.frameRect(forContentRect: contentRect)
        } else {
            frame = NSRect(x: 0, y: 0, width: contentSize.width, height: contentSize.height + 28)
        }

        let visible = (screen ?? NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        if let preferredOrigin {
            frame.origin = preferredOrigin
        } else {
            frame.origin = NSPoint(
                x: visible.midX - frame.width / 2,
                y: visible.midY - frame.height / 2
            )
        }

        if frame.maxX > visible.maxX { frame.origin.x = visible.maxX - frame.width }
        if frame.maxY > visible.maxY { frame.origin.y = visible.maxY - frame.height }
        if frame.minX < visible.minX { frame.origin.x = visible.minX }
        if frame.minY < visible.minY { frame.origin.y = visible.minY }
        return frame
    }

    private func sopshotWindow() -> NSWindow? {
        if let boundMainWindow {
            return boundMainWindow
        }
        return NSApp.windows.first(where: {
            !($0 is NSPanel)
                && $0 !== auxiliaryPanel
                && $0 !== orbWindow
                && $0 !== morphWindow
                && ($0.identifier?.rawValue == "sopshot.main" || $0.title == "SOPShot" || $0.canBecomeKey)
        })
    }

    private func orbFrame(for screen: NSScreen?) -> NSRect {
        let screen = screen ?? NSScreen.main ?? NSScreen.screens[0]
        let visible = screen.visibleFrame
        return NSRect(
            x: visible.minX + orbMargin,
            y: visible.maxY - orbMargin - orbSize,
            width: orbSize,
            height: orbSize
        )
    }

    private func defaultOrbFrame() -> NSRect {
        orbFrame(for: NSScreen.main)
    }
}

extension CaptureOrbController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard !closingAuxiliaryProgrammatically,
              let kind = auxiliaryKind else { return }
        auxiliaryPanel = nil
        auxiliaryKind = nil
        clearPresentationFlag(for: kind)
    }
}

private final class CaptureOrbButton: NSButton {
    private var count = 0
    private var extracting = false
    private var preparing = false
    private var idle = true

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false
        title = ""
        imagePosition = .imageOnly
        focusRingType = .none
        wantsLayer = true
        layer?.cornerRadius = frameRect.width / 2
        layer?.masksToBounds = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(count: Int, extracting: Bool, preparing: Bool, idle: Bool) {
        self.count = count
        self.extracting = extracting
        self.preparing = preparing
        self.idle = idle
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let bounds = self.bounds
        let fill: NSColor
        if extracting || preparing {
            fill = NSColor.systemOrange.withAlphaComponent(0.72)
        } else {
            fill = NSColor.systemOrange
        }
        fill.setFill()
        NSBezierPath(ovalIn: bounds.insetBy(dx: 0.5, dy: 0.5)).fill()

        NSColor.white.withAlphaComponent(0.22).setStroke()
        let ring = NSBezierPath(ovalIn: bounds.insetBy(dx: 1.2, dy: 1.2))
        ring.lineWidth = 1
        ring.stroke()

        let text: String
        let font: NSFont
        if preparing {
            text = "…"
            font = NSFont.systemFont(ofSize: 22, weight: .bold)
        } else if extracting {
            text = "…"
            font = NSFont.systemFont(ofSize: 22, weight: .bold)
        } else if idle {
            text = "▣"
            font = NSFont.systemFont(ofSize: 15, weight: .semibold)
        } else if count == 0 {
            text = "▣"
            font = NSFont.systemFont(ofSize: 15, weight: .semibold)
        } else {
            text = "\(min(count, 99))"
            font = NSFont.systemFont(ofSize: count >= 10 ? 15 : 17, weight: .bold)
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white
        ]
        let size = text.size(withAttributes: attributes)
        let point = NSPoint(
            x: (bounds.width - size.width) / 2,
            y: (bounds.height - size.height) / 2 - 0.5
        )
        text.draw(at: point, withAttributes: attributes)
    }
}
