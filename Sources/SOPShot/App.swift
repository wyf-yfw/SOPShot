import SwiftUI

@main
struct SOPShotApp: App {
    @StateObject private var model: SOPModel
    @StateObject private var recordingStatusItem: RecordingStatusItemController

    init() {
        let model = SOPModel()
        _model = StateObject(wrappedValue: model)
        _recordingStatusItem = StateObject(
            wrappedValue: RecordingStatusItemController(model: model)
        )
    }

    var body: some Scene {
        WindowGroup("SOPShot") {
            ContentView()
                .environmentObject(model)
                .preferredColorScheme(.dark)
                .frame(minWidth: 360, minHeight: 180)
        }
        .defaultSize(width: 400, height: 210)
        .commands {
            CommandMenu("调试") {
                ForEach(DebugDestination.allCases) { destination in
                    Button(destination.title) {
                        model.jumpToDebug(destination)
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
                .disabled(model.phase == .preparing || model.phase == .extracting || model.phase == .processing)
                .keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }
    }
}
