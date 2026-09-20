import AppKit
import Combine
import QuartzCore
import SwiftUI

@MainActor
final class CaptureOrbController: NSObject, ObservableObject, NSMenuDelegate {
    @Published private(set) var isOrbVisible = false

    private weak var model: SOPModel?
    private var stateSubscription: AnyCancellable?
    private var countSubscription: AnyCancellable?
    private var sheetSubscription: AnyCancellable?
    private var sizeSubscription: AnyCancellable?
    private var tourSubscription: AnyCancellable?

    private var orbWindow: NSPanel?
    private var morphWindow: NSPanel?
    private var orbButton: CaptureOrbButton?
    private var lastOrbFrame: NSRect?
    private weak var lastOrbScreen: NSScreen?
    private var savedScreen: NSScreen?
    private var isCollapsing = false
    private var isRestoring = false
    private var hasCollapsedForSession = false
    private var orbMode: OrbMode = .idle

    private var orbSize: CGFloat { model?.captureOrbSize.diameter ?? CaptureOrbSize.large.diameter }
    private let blobLaunchSize: CGFloat = 76
    private let orbMargin: CGFloat = 18
    private let previewContentSize = NSSize(width: 1120, height: 720)
    private let idleContentSize = NSSize(width: 400, height: 210)
    private static let orbOriginXKey = "sopshot.orb.originX"
    private static let orbOriginYKey = "sopshot.orb.originY"

    private weak var boundMainWindow: NSWindow?
    private var windowWatchers: [NSObjectProtocol] = []
    private var launchHideRetries = 0

    private var auxiliaryPanel: NSPanel?
    private var auxiliaryKind: AuxiliaryKind?
    private var closingAuxiliaryProgrammatically = false
    private var onboardingFlow: OnboardingFlowController?

    private enum AuxiliaryKind: Equatable {
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
        lastOrbFrame = Self.loadPersistedOrbFrame(diameter: model.captureOrbSize.diameter)

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
                self?.updateOrbAppearance(count: self?.model?.queuedScreenshotCount ?? 0)
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

        sizeSubscription = model.$captureOrbSize
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.resizeVisibleOrb()
                }
            }

        tourSubscription = model.$guidedTourStep
            .receive(on: RunLoop.main)
            .sink { [weak self] step in
                Task { @MainActor in
                    self?.applyMainWindowResizeLock(locked: step != nil)
                }
            }

        let center = NotificationCenter.default
        windowWatchers.append(center.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { notification in
            let window = notification.object as? NSWindow
            Task { @MainActor [weak self] in
                self?.handleWindowBecameVisible(window)
            }
        })
        windowWatchers.append(center.addObserver(
            forName: NSWindow.didBecomeMainNotification,
            object: nil,
            queue: .main
        ) { notification in
            let window = notification.object as? NSWindow
            Task { @MainActor [weak self] in
                self?.handleWindowBecameVisible(window)
            }
        })

        DispatchQueue.main.async { [weak self] in
            self?.ensureIdleOrbShellIfNeeded()
        }
    }

    func bindMainWindow(_ window: NSWindow?) {
        guard let window, !(window is NSPanel) else { return }
        let isNewWindow = boundMainWindow !== window
        boundMainWindow = window
        window.identifier = NSUserInterfaceItemIdentifier("sopshot.main")
        if let closeButton = window.standardWindowButton(.closeButton) {
            closeButton.target = self
            closeButton.action = #selector(mainWindowCloseButtonClicked(_:))
        }

        guard isNewWindow else { return }
        let currentSize = window.contentView?.bounds.size ?? window.contentLayoutRect.size
        let contentSize = currentSize.width > 0 && currentSize.height > 0
            ? currentSize
            : idleContentSize
        centerWindow(window, on: presentationScreen(for: window), contentSize: contentSize)
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

    @objc private func mainWindowCloseButtonClicked(_ sender: Any?) {
        guard let window = sopshotWindow() else { return }
        if model?.phase == .preview {
            model?.requestClosePreview()
        } else {
            window.performClose(sender)
        }
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

        if model?.isGuidedTourActive == true {
            synchronizeOnboardingFlow(isPresented: true, prefersOrbShell: true)
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
        synchronizeOnboardingFlow(isPresented: help, prefersOrbShell: prefersOrbShell)

        guard prefersOrbShell else {
            closeAuxiliaryPanel()
            return
        }

        let kind: AuxiliaryKind?
        if modelSettings {
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
            if let panel = auxiliaryPanel, !panel.isVisible {
                centerWindow(panel, on: presentationScreen(for: panel))
            }
            auxiliaryPanel?.makeKeyAndOrderFront(nil)
            return
        }

        closeAuxiliaryPanel()
        presentAuxiliaryPanel(kind: kind)
    }

    private func synchronizeOnboardingFlow(isPresented: Bool, prefersOrbShell: Bool) {
        guard let model else {
            onboardingFlow?.stop()
            onboardingFlow = nil
            return
        }

        let shouldRun = model.isGuidedTourActive || (isPresented && prefersOrbShell)
        guard shouldRun else {
            onboardingFlow?.stop()
            onboardingFlow = nil
            return
        }

        if isPresented, model.guidedTourStep == nil {
            model.beginGuidedTour()
        }

        let orbFrame = orbWindow?.frame ?? defaultOrbFrame()
        let screen = screen(forOrbFrame: orbFrame)
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else { return }

        if let onboardingFlow {
            onboardingFlow.updateAnchor(on: screen, orbFrame: orbFrame)
            return
        }

        let flow = OnboardingFlowController(model: model) { [weak self, weak model] completed in
            if completed {
                model?.completeOnboarding()
            } else {
                model?.dismissOnboarding()
            }
            self?.onboardingFlow = nil
            // Tour end / Esc should always land back on the idle orb shell.
            self?.ensureIdleOrbShellIfNeeded()
        }
        onboardingFlow = flow
        flow.start(on: screen, orbFrame: orbFrame)
    }

    private func updateOnboardingAnchor(frame: NSRect, on screen: NSScreen?) {
        guard let onboardingFlow,
              let screen = connectedScreen(screen) else { return }
        onboardingFlow.updateAnchor(on: screen, orbFrame: frame)
    }

    private func presentAuxiliaryPanel(kind: AuxiliaryKind) {
        guard let model else { return }

        let title: String
        let size: NSSize
        let root: AnyView
        switch kind {
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
        centerWindow(panel, on: presentationScreen(for: panel), contentSize: size)
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
        savedScreen = connectedScreen(mainWindow.screen) ?? presentationScreen(for: mainWindow)

        let windowFrame = mainWindow.frame
        let endFrame = lastOrbFrame ?? orbFrame(for: mainWindow.screen ?? NSScreen.main)
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
        let screen = presentationScreen(for: mainWindow, preferred: savedScreen)
        let targetFrame = windowFrame(
            forContentSize: contentSize,
            on: screen,
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
                            self?.savedScreen = nil
                            // Re-cut the coach spotlight now that the preview window is final.
                            self?.applyMainWindowResizeLock(locked: self?.model?.isGuidedTourActive == true)
                            self?.onboardingFlow?.refresh()
                        }
                    })
                }
            })
        } else {
            tearDownOrb(animated: false)
            showMainWindow(contentSize: contentSize, animated: false)
            isRestoring = false
            savedScreen = nil
        }
    }

    private func presentOrb(mode: OrbMode, animated: Bool) {
        presentOrb(mode: mode, at: orbWindow?.frame ?? lastOrbFrame ?? defaultOrbFrame(), animated: animated)
    }

    private func presentOrb(mode: OrbMode, at frame: NSRect, animated: Bool) {
        let screen = screen(forOrbFrame: frame)
        let frame = boundedOrbFrame(frame, on: screen)
        rememberOrbFrame(frame, on: screen)
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
            button.autoresizingMask = [.width, .height]
            button.target = self
            button.action = #selector(orbClicked(_:))
            button.setAccessibilityHelp("聚焦后可用方向键微调位置，按住并拖动可移动；轻点打开菜单或结束采集。")
            button.onMove = { [weak self] origin, followsPointer in
                self?.moveOrb(to: origin, followsPointer: followsPointer)
            }
            panel.contentView = button

            orbWindow = panel
            orbButton = button
            isOrbVisible = true
        }

        updateOrbAppearance(count: model?.queuedScreenshotCount ?? 0)
        orbWindow?.setFrame(frame, display: true)
        orbButton?.setOrbDiameter(frame.width)
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
        if model?.isHelpPresented == true || model?.isGuidedTourActive == true {
            synchronizeOnboardingFlow(
                isPresented: true,
                prefersOrbShell: model?.prefersOrbShell == true || model?.isGuidedTourActive == true
            )
        }
        updateOnboardingAnchor(frame: frame, on: screen)
    }

    private func updateOrbAppearance(count: Int) {
        let extracting = orbMode == .extracting
        let preparing = orbMode == .preparing
        orbButton?.apply(
            count: count,
            extracting: extracting,
            preparing: preparing,
            idle: orbMode == .idle,
            recording: orbMode == .recording
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
        orbButton?.isEnabled = orbMode != .extracting
            && orbMode != .preparing
        orbButton?.setAccessibilityLabel(tip)
    }

    private var deferredIdleMenuAction: (() -> Void)?

    @objc private func orbClicked(_ sender: Any?) {
        switch orbMode {
        case .idle:
            guard model?.allowsGuidedTourAction(.openOrbMenu) != false else { return }
            showIdleMenu()
        case .recording:
            guard model?.allowsGuidedTourAction(.stopCapture) != false else { return }
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
        deferredIdleMenuAction = nil

        // Advance openOrb → pickModel before building items, otherwise every action
        // stays disabled for the menu that was constructed under step 1 permissions.
        if model?.guidedTourStep == .openOrb {
            model?.noteGuidedTourEvent(.orbMenuOpened)
            onboardingFlow?.refresh()
        }

        let menu = NSMenu()
        menu.autoenablesItems = false

        let touring = model?.guidedTourStep != nil
        let allowStart = model?.allowsGuidedTourAction(.startCapture) != false
        let allowSelectModel = model?.allowsGuidedTourAction(.selectModel) != false
        let allowModelSettings = model?.allowsGuidedTourAction(.openModelSettings) != false
        let options = model?.configuredModelOptions ?? []

        let startItem = NSMenuItem(
            title: "开始截图",
            action: #selector(menuStartCapture(_:)),
            keyEquivalent: "r"
        )
        startItem.keyEquivalentModifierMask = [.command, .shift]
        startItem.target = self
        startItem.isEnabled = allowStart
        menu.addItem(startItem)

        menu.addItem(.separator())

        let modelRoot = NSMenuItem(title: "选择模型", action: nil, keyEquivalent: "")
        let modelMenu = NSMenu()
        if options.isEmpty {
            if touring {
                let mock = NSMenuItem(
                    title: "演示模型 · 引导专用",
                    action: #selector(menuSelectModel(_:)),
                    keyEquivalent: ""
                )
                mock.target = self
                mock.representedObject = SOPModel.guidedTourMockModelID
                mock.isEnabled = allowSelectModel
                modelMenu.addItem(mock)
            } else {
                let empty = NSMenuItem(title: "尚未配置视觉模型", action: nil, keyEquivalent: "")
                empty.isEnabled = false
                modelMenu.addItem(empty)
            }
        } else {
            for option in options {
                let item = NSMenuItem(
                    title: "\(option.provider.displayName) · \(option.modelLabel)",
                    action: #selector(menuSelectModel(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = option.id
                item.isEnabled = allowSelectModel
                if option.id == model?.selectedConfiguredModelID {
                    item.state = .on
                }
                modelMenu.addItem(item)
            }
        }
        menu.setSubmenu(modelMenu, for: modelRoot)
        modelRoot.isEnabled = allowSelectModel
        menu.addItem(modelRoot)

        let captureSettings = NSMenuItem(
            title: "截图设置…",
            action: #selector(menuCaptureSettings(_:)),
            keyEquivalent: ""
        )
        captureSettings.target = self
        captureSettings.isEnabled = !touring
        menu.addItem(captureSettings)

        let modelSettings = NSMenuItem(
            title: "模型设置…",
            action: #selector(menuModelSettings(_:)),
            keyEquivalent: ""
        )
        modelSettings.target = self
        modelSettings.isEnabled = allowModelSettings
        menu.addItem(modelSettings)

        menu.addItem(.separator())

        let help = NSMenuItem(
            title: "使用说明…",
            action: #selector(menuHelp(_:)),
            keyEquivalent: ""
        )
        help.target = self
        help.isEnabled = !touring
        menu.addItem(help)

        if FeatureFlags.showsDebugAssistant {
            let debug = NSMenuItem(
                title: "调试助手…",
                action: #selector(menuDebug(_:)),
                keyEquivalent: ""
            )
            debug.target = self
            debug.isEnabled = !touring
            menu.addItem(debug)
        }

        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: "退出 SOPShot",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quit.keyEquivalentModifierMask = [.command]
        quit.isEnabled = !touring
        menu.addItem(quit)

        menu.delegate = self
        let point = NSPoint(x: 0, y: button.bounds.height + 2)
        // popUp blocks until the menu dismisses. Defer item actions until after dismiss
        // so startRecording / sheets don't fight menu tracking.
        menu.popUp(positioning: nil, at: point, in: button)

        let action = deferredIdleMenuAction
        deferredIdleMenuAction = nil
        action?()
    }

    func menuWillOpen(_ menu: NSMenu) {
        // Coach copy / spotlight may still need a sync pass while the menu is visible.
        if model?.guidedTourStep == .pickModel || model?.guidedTourStep == .startCapture {
            onboardingFlow?.refresh()
        }
    }

    @objc private func menuStartCapture(_ sender: Any?) {
        guard model?.allowsGuidedTourAction(.startCapture) != false else { return }
        deferredIdleMenuAction = { [weak self] in
            self?.model?.startRecording()
        }
    }

    @objc private func menuSelectModel(_ sender: NSMenuItem) {
        guard model?.allowsGuidedTourAction(.selectModel) != false else { return }
        guard let id = sender.representedObject as? String else { return }
        if id == SOPModel.guidedTourMockModelID {
            deferredIdleMenuAction = { [weak self] in
                self?.model?.selectGuidedTourMockModel()
            }
            return
        }
        deferredIdleMenuAction = { [weak self] in
            guard let option = self?.model?.configuredModelOptions.first(where: { $0.id == id }) else { return }
            self?.model?.selectConfiguredModel(option)
        }
    }

    @objc private func menuCaptureSettings(_ sender: Any?) {
        guard model?.isGuidedTourActive != true else { return }
        deferredIdleMenuAction = { [weak self] in
            self?.model?.isCaptureSettingsPresented = true
        }
    }

    @objc private func menuModelSettings(_ sender: Any?) {
        guard model?.allowsGuidedTourAction(.openModelSettings) != false else { return }
        deferredIdleMenuAction = { [weak self] in
            self?.model?.isModelSettingsPresented = true
        }
    }

    @objc private func menuHelp(_ sender: Any?) {
        guard model?.isGuidedTourActive != true else { return }
        deferredIdleMenuAction = { [weak self] in
            self?.model?.beginGuidedTour()
        }
    }

    @objc private func menuDebug(_ sender: Any?) {
        guard model?.isGuidedTourActive != true else { return }
        deferredIdleMenuAction = { [weak self] in
            self?.model?.isDebugAssistantPresented = true
        }
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
            savedScreen = connectedScreen(window.screen) ?? presentationScreen(for: window)
            window.alphaValue = 0
            window.orderOut(nil)
            window.alphaValue = 1
        }
    }

    private func showMainWindow(contentSize: NSSize, animated: Bool) {
        guard let window = sopshotWindow() else { return }
        let frame = windowFrame(
            forContentSize: contentSize,
            on: presentationScreen(for: window, preferred: savedScreen),
            using: window
        )
        let wasVisible = window.isVisible
        let sizeChanged = abs(window.frame.width - frame.width) > 1
            || abs(window.frame.height - frame.height) > 1
        if !wasVisible || sizeChanged {
            window.setFrame(frame, display: true)
        }
        if animated && !wasVisible {
            window.alphaValue = 0
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        if animated && !wasVisible {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                window.animator().alphaValue = 1
            }
        } else {
            window.alphaValue = 1
        }
        savedScreen = nil
        applyMainWindowResizeLock(locked: model?.isGuidedTourActive == true)
    }

    private func tearDownOrb(animated: Bool) {
        if let frame = orbWindow?.frame {
            rememberOrbFrame(frame, on: screen(forOrbFrame: frame))
        }
        onboardingFlow?.stop()
        onboardingFlow = nil
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
        using window: NSWindow?
    ) -> NSRect {
        let contentRect = NSRect(origin: .zero, size: contentSize)
        var frame: NSRect
        if let window {
            frame = window.frameRect(forContentRect: contentRect)
        } else {
            frame = NSRect(x: 0, y: 0, width: contentSize.width, height: contentSize.height + 28)
        }

        let visible = screen?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? NSScreen.screens.first?.visibleFrame
            ?? NSRect(origin: .zero, size: contentSize)
        frame.origin = NSPoint(
            x: visible.midX - frame.width / 2,
            y: visible.midY - frame.height / 2
        )
        frame.origin.x = min(max(frame.origin.x, visible.minX), max(visible.minX, visible.maxX - frame.width))
        frame.origin.y = min(max(frame.origin.y, visible.minY), max(visible.minY, visible.maxY - frame.height))
        return frame
    }

    private func centerWindow(_ window: NSWindow, on screen: NSScreen?, contentSize: NSSize? = nil) {
        let measuredSize = contentSize
            ?? window.contentView?.bounds.size
            ?? window.contentLayoutRect.size
        let size = measuredSize.width > 0 && measuredSize.height > 0
            ? measuredSize
            : window.frame.size
        let frame = windowFrame(forContentSize: size, on: screen, using: window)
        window.setFrame(frame, display: false)
    }

    private func presentationScreen(for window: NSWindow?, preferred: NSScreen? = nil) -> NSScreen? {
        if let screen = connectedScreen(preferred) {
            return screen
        }

        if let mainWindow = sopshotWindow(), mainWindow.isVisible,
           let screen = connectedScreen(mainWindow.screen) {
            return screen
        }

        if let window, window.isVisible, let screen = connectedScreen(window.screen) {
            return screen
        }

        if let screen = connectedScreen(orbWindow?.screen) {
            return screen
        }

        let mouseLocation = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) {
            return screen
        }

        if let window, !window.isVisible, window.frame.origin != .zero,
           let screen = connectedScreen(window.screen) {
            return screen
        }

        if let screen = connectedScreen(savedScreen) {
            return screen
        }
        if let screen = connectedScreen(window?.screen) {
            return screen
        }
        if let screen = connectedScreen(NSApp.keyWindow?.screen) {
            return screen
        }
        if let screen = connectedScreen(NSApp.mainWindow?.screen) {
            return screen
        }
        return NSScreen.main ?? NSScreen.screens.first
    }

    private func connectedScreen(_ candidate: NSScreen?) -> NSScreen? {
        guard let candidate else { return nil }
        let screenNumberKey = NSDeviceDescriptionKey("NSScreenNumber")
        if let number = candidate.deviceDescription[screenNumberKey] as? NSNumber {
            return NSScreen.screens.first {
                ($0.deviceDescription[screenNumberKey] as? NSNumber) == number
            }
        }
        return NSScreen.screens.first(where: { $0 === candidate })
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
        if let restored = lastOrbFrame ?? Self.loadPersistedOrbFrame(diameter: orbSize) {
            let screen = screen(forOrbFrame: restored) ?? NSScreen.main
            return boundedOrbFrame(
                NSRect(origin: restored.origin, size: NSSize(width: orbSize, height: orbSize)),
                on: screen
            )
        }
        return orbFrame(for: NSScreen.main)
    }

    private func resizeVisibleOrb() {
        guard let window = orbWindow, let button = orbButton else { return }
        let oldFrame = window.frame
        let diameter = orbSize
        let screen = screen(forOrbFrame: oldFrame)
        var frame = NSRect(
            x: oldFrame.midX - diameter / 2,
            y: oldFrame.midY - diameter / 2,
            width: diameter,
            height: diameter
        )
        frame = boundedOrbFrame(frame, on: screen)
        window.setFrame(frame, display: true)
        button.setOrbDiameter(diameter)
        rememberOrbFrame(frame, on: screen)
        updateOnboardingAnchor(frame: frame, on: screen)
    }

    private func moveOrb(to origin: NSPoint, followsPointer: Bool) {
        guard let window = orbWindow else { return }
        let pointer = NSEvent.mouseLocation
        let pointerScreen = followsPointer
            ? NSScreen.screens.first(where: { $0.frame.contains(pointer) })
            : nil
        let screen = pointerScreen
            ?? connectedScreen(window.screen)
            ?? NSScreen.main
        var frame = window.frame
        frame.origin = origin
        frame = boundedOrbFrame(frame, on: screen)
        window.setFrame(frame, display: true)
        rememberOrbFrame(frame, on: screen)
        updateOnboardingAnchor(frame: frame, on: screen)
    }

    private func screen(forOrbFrame frame: NSRect) -> NSScreen? {
        let center = NSPoint(x: frame.midX, y: frame.midY)
        return NSScreen.screens.first(where: { $0.frame.contains(center) })
            ?? connectedScreen(lastOrbScreen)
            ?? presentationScreen(for: orbWindow)
    }

    private func boundedOrbFrame(_ frame: NSRect, on screen: NSScreen?) -> NSRect {
        guard let visible = screen?.visibleFrame else { return frame }
        var frame = frame
        frame.origin.x = min(max(frame.origin.x, visible.minX), max(visible.minX, visible.maxX - frame.width))
        frame.origin.y = min(max(frame.origin.y, visible.minY), max(visible.minY, visible.maxY - frame.height))
        return frame
    }

    private func rememberOrbFrame(_ frame: NSRect, on screen: NSScreen?) {
        lastOrbFrame = frame
        lastOrbScreen = screen
        persistOrbPosition(frame)
    }

    func persistOrbPositionNow() {
        guard let frame = orbWindow?.frame ?? lastOrbFrame else { return }
        persistOrbPosition(frame)
    }

    private func persistOrbPosition(_ frame: NSRect) {
        UserDefaults.standard.set(Double(frame.origin.x), forKey: Self.orbOriginXKey)
        UserDefaults.standard.set(Double(frame.origin.y), forKey: Self.orbOriginYKey)
    }

    private static func loadPersistedOrbFrame(diameter: CGFloat) -> NSRect? {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: orbOriginXKey) != nil,
              defaults.object(forKey: orbOriginYKey) != nil else {
            return nil
        }
        let origin = NSPoint(
            x: defaults.double(forKey: orbOriginXKey),
            y: defaults.double(forKey: orbOriginYKey)
        )
        var frame = NSRect(origin: origin, size: NSSize(width: diameter, height: diameter))
        let screen = NSScreen.screens.first(where: { $0.frame.intersects(frame) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let visible = screen?.visibleFrame else { return frame }
        frame.origin.x = min(max(frame.origin.x, visible.minX), max(visible.minX, visible.maxX - frame.width))
        frame.origin.y = min(max(frame.origin.y, visible.minY), max(visible.minY, visible.maxY - frame.height))
        return frame
    }

    private func applyMainWindowResizeLock(locked: Bool) {
        guard let window = sopshotWindow() else { return }
        if locked {
            window.styleMask.remove(.resizable)
            let size = window.frame.size
            window.minSize = size
            window.maxSize = size
        } else {
            if !window.styleMask.contains(.resizable) {
                window.styleMask.insert(.resizable)
            }
            window.minSize = NSSize(width: 360, height: 180)
            window.maxSize = NSSize(
                width: CGFloat.greatestFiniteMagnitude,
                height: CGFloat.greatestFiniteMagnitude
            )
        }
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
    private var recording = false
    var onMove: ((NSPoint, Bool) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false
        title = ""
        imagePosition = .imageOnly
        focusRingType = .default
        wantsLayer = true
        layer?.cornerRadius = frameRect.width / 2
        layer?.masksToBounds = true
    }

    override var acceptsFirstResponder: Bool { true }

    func setOrbDiameter(_ diameter: CGFloat) {
        setFrameSize(NSSize(width: diameter, height: diameter))
        layer?.cornerRadius = diameter / 2
        needsDisplay = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(count: Int, extracting: Bool, preparing: Bool, idle: Bool, recording: Bool) {
        self.count = count
        self.extracting = extracting
        self.preparing = preparing
        self.idle = idle
        self.recording = recording
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else {
            super.mouseDown(with: event)
            return
        }

        let startFrame = window.frame
        let startPoint = window.convertPoint(toScreen: event.locationInWindow)
        var didDrag = false

        while let nextEvent = NSApp.nextEvent(
            matching: [.leftMouseDragged, .leftMouseUp],
            until: .distantFuture,
            inMode: .eventTracking,
            dequeue: true
        ) {
            let currentPoint = window.convertPoint(toScreen: nextEvent.locationInWindow)
            let delta = NSPoint(x: currentPoint.x - startPoint.x, y: currentPoint.y - startPoint.y)
            if !didDrag, hypot(delta.x, delta.y) >= 4 {
                didDrag = true
            }

            if didDrag {
                onMove?(
                    NSPoint(x: startFrame.origin.x + delta.x, y: startFrame.origin.y + delta.y),
                    true
                )
            }

            if nextEvent.type == .leftMouseUp {
                break
            }
        }

        if !didDrag, isEnabled, let action {
            sendAction(action, to: target)
        }
    }

    override func keyDown(with event: NSEvent) {
        let distance: CGFloat = event.modifierFlags.contains(.shift) ? 24 : 8
        let origin: NSPoint
        switch event.keyCode {
        case 123:
            origin = NSPoint(x: (window?.frame.origin.x ?? 0) - distance, y: window?.frame.origin.y ?? 0)
        case 124:
            origin = NSPoint(x: (window?.frame.origin.x ?? 0) + distance, y: window?.frame.origin.y ?? 0)
        case 125:
            origin = NSPoint(x: window?.frame.origin.x ?? 0, y: (window?.frame.origin.y ?? 0) - distance)
        case 126:
            origin = NSPoint(x: window?.frame.origin.x ?? 0, y: (window?.frame.origin.y ?? 0) + distance)
        default:
            super.keyDown(with: event)
            return
        }
        onMove?(origin, false)
    }

    override func draw(_ dirtyRect: NSRect) {
        let bounds = self.bounds
        let fill: NSColor
        if recording {
            fill = NSColor.systemRed
        } else if extracting || preparing {
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
        } else if recording && count == 0 {
            drawStopMark(in: bounds)
            return
        } else if idle {
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

    private func drawStopMark(in bounds: NSRect) {
        let side = min(bounds.width * 0.28, 13)
        let mark = NSBezierPath(
            roundedRect: NSRect(
                x: (bounds.width - side) / 2,
                y: (bounds.height - side) / 2,
                width: side,
                height: side
            ),
            xRadius: 2,
            yRadius: 2
        )
        NSColor.white.setFill()
        mark.fill()
    }
}
