import AppKit
import SwiftUI

@main
struct SOPShotApp: App {
    @NSApplicationDelegateAdaptor(SOPShotAppDelegate.self) private var appDelegate
    @StateObject private var model: SOPModel
    @StateObject private var captureOrb: CaptureOrbController

    init() {
        let model = SOPModel()
        let captureOrb = CaptureOrbController(model: model)
        _model = StateObject(wrappedValue: model)
        _captureOrb = StateObject(wrappedValue: captureOrb)
        SOPShotAppDelegate.sharedModel = model
        SOPShotAppDelegate.sharedOrb = captureOrb
    }

    var body: some Scene {
        WindowGroup("SOPShot") {
            ContentView()
                .environmentObject(model)
                .preferredColorScheme(.dark)
                .frame(minWidth: 360, minHeight: 180)
                .background(MainWindowBinder(prefersOrbShell: model.prefersOrbShell))
        }
        .defaultSize(width: 400, height: 210)
        .commands {
            if FeatureFlags.showsDebugAssistant {
                CommandMenu("调试") {
                    ForEach(DebugDestination.allCases) { destination in
                        Button(destination.title) {
                            model.jumpToDebug(destination)
                        }
                        .disabled(model.isHelpPresented)
                    }
                }
            }
            CommandGroup(after: .newItem) {
                Button {
                    if model.phase == .preview {
                        model.startAIProcessing()
                    } else {
                        model.toggleRecording()
                    }
                } label: {
                        Text(
                            model.phase == .recording
                            ? "结束截图"
                            : model.phase == .preview
                                ? "开始生成说明"
                                : "开始截图"
                        )
                }
                .disabled(model.isHelpPresented
                    || model.phase == .preparing
                    || model.phase == .extracting
                    || model.phase == .processing)
                .keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }
    }
}

@MainActor
final class SOPShotAppDelegate: NSObject, NSApplicationDelegate {
    static weak var sharedModel: SOPModel?
    static weak var sharedOrb: CaptureOrbController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        SOPShotAppDelegate.sharedOrb?.ensureIdleOrbShellIfNeeded()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        SOPShotAppDelegate.sharedOrb?.ensureIdleOrbShellIfNeeded()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if SOPShotAppDelegate.sharedModel?.prefersOrbShell == true {
            SOPShotAppDelegate.sharedOrb?.ensureIdleOrbShellIfNeeded()
            return false
        }
        return true
    }
}

/// Binds the SwiftUI host window as soon as it exists so the orb shell can hide it.
private struct MainWindowBinder: NSViewRepresentable {
    var prefersOrbShell: Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            SOPShotAppDelegate.sharedOrb?.bindMainWindow(view.window)
            if prefersOrbShell {
                SOPShotAppDelegate.sharedOrb?.ensureIdleOrbShellIfNeeded()
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            SOPShotAppDelegate.sharedOrb?.bindMainWindow(nsView.window)
            if prefersOrbShell {
                SOPShotAppDelegate.sharedOrb?.ensureIdleOrbShellIfNeeded()
            }
        }
    }
}
