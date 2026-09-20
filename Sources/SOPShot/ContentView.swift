import AppKit
import SwiftUI

extension Color {
    static let sopBackground = Color(nsColor: .underPageBackgroundColor)
    static let sopSurface = Color(nsColor: .windowBackgroundColor)
    static let sopPaper = Color(nsColor: .textBackgroundColor)
    static let sopMuted = Color(nsColor: .controlBackgroundColor)
    static let sopAccent = Color(nsColor: .systemOrange)
    static let sopTeal = Color(nsColor: .systemTeal)
    static let sopDanger = Color(nsColor: .systemRed)
}

struct ContentView: View {
    @EnvironmentObject private var model: SOPModel
    @AppStorage("sopshot.onboarding.completed") private var onboardingCompleted = false

    var body: some View {
        Group {
            if model.phase == .preview {
                CaptureFramePreviewView()
            } else if model.phase != .idle {
                CaptureView()
            } else if model.steps.isEmpty {
                // Idle shell is the floating orb; keep a minimal host for sheets/alerts.
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(WindowSizeView(targetContentSize: NSSize(width: 400, height: 210)))
            } else if model.isEditing {
                EditorWorkspaceView()
            } else {
                ResultPreviewView()
            }
        }
        .background(Color.sopBackground)
        .task {
            model.requestInputMonitoringAccessIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshInputMonitoringPermission()
        }
        .onAppear {
            if !onboardingCompleted {
                model.beginGuidedTour()
            }
        }
        .toolbar {
            if !model.steps.isEmpty || model.phase != .idle || model.isDebugSession {
                if FeatureFlags.showsDebugAssistant {
                    ToolbarItem(placement: .automatic) {
                        Button {
                            model.isDebugAssistantPresented = true
                        } label: {
                            Image(systemName: "hammer")
                        }
                        .help("跳转到任意页面，不必走完整流程")
                        .accessibilityLabel("调试助手")
                    }
                }
                ToolbarItem(placement: .automatic) {
                    Menu {
                        Button("截图设置…") {
                            model.isCaptureSettingsPresented = true
                        }
                        .disabled(model.phase != .idle && model.phase != .preview && !model.isDebugSession)
                        Button("模型设置…") {
                            model.isModelSettingsPresented = true
                        }
                        .disabled(model.phase != .idle && model.phase != .preview && !model.isDebugSession)
                        Divider()
                        Button("使用说明…") {
                            model.beginGuidedTour()
                        }
                        .disabled(model.phase != .idle && model.phase != .preview && !model.isDebugSession)
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .help("截图触发、模型配置与使用说明")
                    .accessibilityLabel("设置")
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { model.isModelSettingsPresented && !model.prefersOrbShell },
            set: {
                model.isModelSettingsPresented = $0
            }
        )) {
            ModelSettingsView()
                .environmentObject(model)
        }
        .sheet(isPresented: Binding(
            get: { model.isCaptureSettingsPresented && !model.prefersOrbShell },
            set: {
                model.isCaptureSettingsPresented = $0
            }
        )) {
            CaptureSettingsView()
                .environmentObject(model)
        }
        .sheet(isPresented: Binding(
            get: { FeatureFlags.showsDebugAssistant && model.isDebugAssistantPresented && !model.prefersOrbShell },
            set: { model.isDebugAssistantPresented = $0 }
        )) {
            DebugAssistantView()
                .environmentObject(model)
        }
        .sheet(isPresented: Binding(
            get: { model.isHelpPresented && !model.prefersOrbShell },
            set: {
                if !$0 {
                    model.dismissOnboarding()
                }
            }
        )) {
            OnboardingUnavailableView()
                .environmentObject(model)
        }
        .alert("需要输入监控权限", isPresented: $model.isInputMonitoringPermissionAlertPresented) {
            Button("打开系统设置") {
                model.openInputMonitoringSettings()
            }
            Button("稍后", role: .cancel) {}
        } message: {
            Text("SOPShot需要读取鼠标和键盘的操作类别，在重要操作后截取对应画面。不会记录具体输入文字、剪贴板内容或密码。请在“系统设置 > 隐私与安全性 > 输入监控”中允许 SOPShot。")
        }
        .alert(
            model.pendingConfirmation?.title ?? "",
            isPresented: Binding(
                get: { model.pendingConfirmation != nil },
                set: { if !$0 { model.cancelPendingConfirmation() } }
            ),
            presenting: model.pendingConfirmation
        ) { confirmation in
            Button(confirmation.confirmTitle, role: confirmation.isDestructive ? .destructive : nil) {
                model.confirmPendingAction()
            }
            Button("取消", role: .cancel) {
                model.cancelPendingConfirmation()
            }
        } message: { confirmation in
            Text(confirmation.message)
        }
    }

}

struct DebugAssistantView: View {
    @EnvironmentObject private var model: SOPModel

    private let destinations: [(String, [DebugDestination])] = [
        ("开始与截图", [.emptyStart, .preparing, .recording, .extracting]),
        ("预览与结果", [.preview, .processing, .result, .editor]),
        ("设置", [.modelSettings, .captureSettings])
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("调试助手")
                        .font(.system(size: 20, weight: .semibold))
                    Text("直接跳到目标页面看布局，不必真实截图或调用模型。")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("关闭") {
                    model.isDebugAssistantPresented = false
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 22)
            .padding(.top, 20)
            .padding(.bottom, 14)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(destinations, id: \.0) { section in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(section.0)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                            ForEach(section.1) { destination in
                                Button {
                                    model.jumpToDebug(destination)
                                } label: {
                                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(destination.title)
                                                .font(.system(size: 14, weight: .semibold))
                                                .foregroundStyle(.primary)
                                            Text(destination.detail)
                                                .font(.system(size: 11))
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer(minLength: 8)
                                        Image(systemName: "arrow.right")
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundStyle(Color.sopAccent)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                                    .background(Color.sopMuted)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(22)
            }
        }
        .frame(width: 420, height: 520)
    }
}

struct ModelSettingsView: View {
    @EnvironmentObject private var model: SOPModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("模型设置")
                        .font(.system(size: 24, weight: .bold))
                    Text("SOPShot 不代管模型。截图并确认后，软件才会把图片发送给这里配置的接口。")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Divider()
                .padding(.vertical, 22)

            Form {
                Section {
                    Picker(
                        "厂商",
                        selection: Binding(
                            get: { model.modelProvider },
                            set: { model.selectModelProvider($0) }
                        )
                    ) {
                        ForEach(ModelProvider.allCases) { provider in
                            Text(provider.displayName)
                                .tag(provider)
                        }
                    }
                    .pickerStyle(.menu)

                    Text(model.modelProvider.description)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 4)
                }

                Section {
                    if model.modelProvider.presets.isEmpty {
                        TextField("模型名称", text: $model.modelName)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        Picker(
                            "模型",
                            selection: Binding(
                                get: { model.modelName },
                                set: { selectedID in
                                    if let preset = model.modelProvider.presets.first(where: { $0.id == selectedID }) {
                                        model.selectModelPreset(preset)
                                    }
                                }
                            )
                        ) {
                            ForEach(model.modelProvider.presets) { preset in
                                Text("\(preset.name)  ·  \(preset.detail)")
                                    .tag(preset.id)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    if model.modelProvider.supportedInputModes.count > 1 {
                        Picker(
                            "发送方式",
                            selection: Binding(
                                get: { model.modelInputMode },
                                set: { model.selectModelInputMode($0) }
                            )
                        ) {
                            ForEach(model.modelProvider.supportedInputModes) { inputMode in
                                Text(inputMode.displayName)
                                    .tag(inputMode)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    Text(model.modelInputMode.description)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                } header: {
                    Text("图像输入")
                }

                Section {
                    if isCustomProvider {
                        TextField("接口地址", text: $model.modelEndpoint)
                            .textFieldStyle(.roundedBorder)
                    }
                    SecureField("API Key", text: $model.modelAPIKey)
                        .textFieldStyle(.roundedBorder)
                    if model.isAPIKeyLoading && model.modelAPIKey.isEmpty {
                        Text("正在读取本机 API Key…")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text(isCustomProvider ? "连接信息" : "API Key")
                }
            }
            .formStyle(.grouped)

            VStack(alignment: .leading, spacing: 6) {
                Text("只显示支持图像输入的模型。结束截图后会先预览画面，确认后才会发送。")
                Text("测试会发送一张内置演示画面。API Key 保存在本机应用配置中，不写入苹果钥匙串。")
                Text(isCustomProvider ? "接口地址和模型选择会保存在本机。" : "预制厂商的接口地址已内置，模型选择会保存在本机。")
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .padding(.top, 14)

            HStack(spacing: 12) {
                Button {
                    model.testModelAPI()
                } label: {
                    HStack(spacing: 7) {
                        if case .testing = model.modelTestState {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text("测试图像输入")
                    }
                }
                .buttonStyle(SOPQuietButtonStyle())
                .disabled(model.phase != .idle || isTesting)

                modelTestMessage

                Spacer()

                Button("保存并关闭") {
                    model.saveModelSettings()
                }
                .buttonStyle(SOPDarkButtonStyle())
            }
            .padding(.top, 18)
        }
        .padding(28)
        .frame(width: 640, height: 480)
    }

    private var isTesting: Bool {
        if case .testing = model.modelTestState {
            return true
        }
        return false
    }

    private var isCustomProvider: Bool {
        model.modelProvider == .customOpenAICompatible
    }

    @ViewBuilder
    private var modelTestMessage: some View {
        switch model.modelTestState {
        case .idle:
            EmptyView()
        case .testing:
            Text("正在连接…")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        case .success(let message):
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(Color.sopTeal)
                .lineLimit(2)
        case .failure(let message):
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(Color.sopDanger)
                .lineLimit(2)
        }
    }
}

struct CaptureSettingsView: View {
    @EnvironmentObject private var model: SOPModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("截图设置")
                        .font(.system(size: 24, weight: .bold))
                    Text("选择哪些操作会触发截图。普通打字始终不会截图。")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("悬浮球大小")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                    Picker("悬浮球大小", selection: $model.captureOrbSize) {
                        ForEach(CaptureOrbSize.allCases) { size in
                            Text(size.title).tag(size)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 142)
                }
            }

            Divider()
                .padding(.vertical, 22)

            Form {
                Section {
                    ForEach(InputEventKind.configurableScreenshotTriggers) { kind in
                        Toggle(
                            isOn: Binding(
                                get: { model.screenshotTriggers.isEnabled(kind) },
                                set: { model.setScreenshotTrigger(kind, enabled: $0) }
                            )
                        ) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(kind.promptLabel)
                                Text(kind.settingsDetail)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("触发操作")
                } footer: {
                    Text("关闭后对应操作不再截图。至少保留一种触发，才能开始截图。")
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("保存并关闭") {
                    model.saveCaptureSettings()
                }
                .buttonStyle(SOPDarkButtonStyle())
                .disabled(!model.screenshotTriggers.hasAnyTriggerEnabled)
            }
            .padding(.top, 18)
        }
        .padding(28)
        .frame(width: 520, height: 520)
    }
}

struct CaptureView: View {
    @EnvironmentObject private var model: SOPModel

    private var isPreparing: Bool { model.phase == .preparing }
    private var isRecording: Bool { model.phase == .recording }
    private var isExtracting: Bool { model.phase == .extracting }
    private var isProcessing: Bool { model.phase == .processing }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(captureTitle)
                    .font(.system(size: 18, weight: .semibold))
                    .tracking(-0.3)
                Spacer(minLength: 12)
                if isRecording {
                    Text("已截 \(model.queuedScreenshotCount) 张")
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.sopAccent)
                }
            }

            Text(captureSubtitle)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)

            if isRecording {
                Button {
                    model.stopRecording()
                } label: {
                    HStack {
                        Text("结束截图")
                        Spacer()
                        Text("⌘⇧R")
                            .font(.system(size: 11, design: .monospaced))
                            .opacity(0.7)
                    }
                }
                .buttonStyle(SOPFilledButtonStyle(tone: .accent))
                .padding(.top, 16)
            } else {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(statusText)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .padding(.top, 14)
            }

            if shouldShowBanner, let banner = model.banner {
                BannerView(banner: banner)
                    .padding(.top, 12)
            }

            Text(helperText)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.top, 12)
        }
        .padding(.horizontal, 22)
        .padding(.top, 20)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(WindowSizeView(targetContentSize: NSSize(width: 400, height: 228)))
    }

    private var captureTitle: String {
        if isPreparing { return "准备截图" }
        if isRecording { return "按操作截图" }
        if isExtracting { return "整理截图" }
        return "生成说明"
    }

    private var captureSubtitle: String {
        if isPreparing { return "准备完成后开始操作。每次重要操作会保存一张截图。" }
        if isRecording { return "按平时方式操作。不会录视频，只在点击和关键按键后截图。" }
        if isExtracting { return "截图已在本机，整理后先让你检查。" }
        return "截图已确认，正在生成操作说明。"
    }

    private var statusText: String {
        if isPreparing { return "正在准备屏幕截图" }
        if isExtracting { return "正在整理已保存的截图" }
        return "正在生成说明"
    }

    private var helperText: String {
        if isPreparing { return "准备完成后开始操作。" }
        if isRecording { return "普通字母和数字不会触发截图。" }
        if isExtracting { return "完成后会打开截图预览。" }
        return "完成后会显示生成的说明。"
    }

    private var shouldShowBanner: Bool {
        guard let banner = model.banner else { return false }
        switch banner.tone {
        case .warning, .error:
            return true
        case .info, .success:
            return false
        }
    }
}

struct CaptureFramePreviewView: View {
    @EnvironmentObject private var model: SOPModel
    @State private var selectedIndex = 0
    @State private var isDeleteConfirmationPresented = false

    private var visibleIndex: Int {
        guard !model.previewFrames.isEmpty else { return 0 }
        return min(max(0, selectedIndex), model.previewFrames.count - 1)
    }

    private var selectedFrame: CapturedFrame? {
        guard model.previewFrames.indices.contains(visibleIndex) else {
            return model.previewFrames.first
        }
        return model.previewFrames[visibleIndex]
    }

    private var selectedEvents: [InputTimelineEvent] {
        guard let selectedFrame else { return [] }
        return model.previewInputEvents(for: selectedFrame)
    }

    private var selectedClickEvents: [InputTimelineEvent] {
        selectedEvents.filter { $0.kind == .click && $0.location != nil }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                BrandHeader()
                Spacer()
                HStack(spacing: 7) {
                    Circle()
                        .fill(Color.sopTeal)
                        .frame(width: 7, height: 7)
                    Text("等待确认")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 18)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("检查截图")
                                .font(.system(size: 28, weight: .bold))
                                .tracking(-0.8)
                            Text("已捕获 \(model.previewFrames.count) 张截图。检查后再生成说明。")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("重新采集") {
                            model.restartFromPreview()
                        }
                        .buttonStyle(SOPQuietButtonStyle())
                        Button("开始生成说明") {
                            model.startAIProcessing()
                        }
                        .buttonStyle(SOPFilledButtonStyle(tone: .accent))
                        .accessibilityHint("确认截图后，将画面和操作数据发送给所选模型生成说明。")
                    }
                    .padding(.horizontal, 30)
                    .padding(.top, 26)

                    if let selectedFrame {
                        HStack(alignment: .top, spacing: 18) {
                            VStack(alignment: .leading, spacing: 8) {
                                AnnotatedFrameImageView(
                                    image: selectedFrame.image,
                                    clickEvents: selectedClickEvents
                                )
                                .frame(maxWidth: .infinity, minHeight: 310, maxHeight: 400)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.secondary.opacity(0.24), lineWidth: 1)
                                )

                                HStack(spacing: 8) {
                                    Text("第 \(visibleIndex + 1) 张")
                                        .font(.system(size: 12, weight: .semibold))
                                    Text("·")
                                        .foregroundStyle(.secondary)
                                    Text("操作时间 \(String(format: "%.1f", selectedFrame.timestamp)) 秒")
                                        .font(.system(size: 12, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                    if !selectedClickEvents.isEmpty {
                                        Text("·")
                                            .foregroundStyle(.secondary)
                                        Text("已标记 \(selectedClickEvents.count) 个点击")
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundStyle(Color.sopAccent)
                                    }
                                    Spacer(minLength: 10)
                                    Button {
                                        isDeleteConfirmationPresented = true
                                    } label: {
                                        Label("删除图片", systemImage: "trash")
                                    }
                                    .buttonStyle(SOPDangerButtonStyle())
                                }
                            }
                            .frame(maxWidth: .infinity)

                            VStack(alignment: .leading, spacing: 12) {
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text("操作数据")
                                        .font(.system(size: 15, weight: .semibold))
                                    Spacer(minLength: 0)
                                    Text("对应一次操作")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                }

                                if selectedEvents.isEmpty {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Image(systemName: model.previewInputMonitoringAvailable ? "cursorarrow.click" : "exclamationmark.circle")
                                            .font(.system(size: 16, weight: .medium))
                                            .foregroundStyle(model.previewInputMonitoringAvailable ? Color.sopTeal : Color.sopAccent)
                                        Text(model.previewInputMonitoringAvailable
                                             ? "这张图附近没有捕获到鼠标或键盘操作。"
                                             : "本次采集没有开启输入监控，所以这里没有操作数据。")
                                            .font(.system(size: 12, weight: .medium))
                                            .fixedSize(horizontal: false, vertical: true)
                                        if !model.previewInputMonitoringAvailable {
                                            Text("开启输入监控后，下一次采集会显示操作类型和鼠标位置。")
                                                .font(.system(size: 11))
                                                .foregroundStyle(.secondary)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                    }
                                    .padding(12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.sopMuted)
                                    .overlay(
                                        Rectangle()
                                            .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
                                    )
                                } else {
                                    ScrollView {
                                        VStack(alignment: .leading, spacing: 7) {
                                            ForEach(Array(selectedEvents.enumerated()), id: \.offset) { _, event in
                                                InputEventRow(event: event)
                                            }
                                        }
                                    }
                                    .frame(maxHeight: 140)
                                }

                                Divider()

                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(alignment: .firstTextBaseline) {
                                        Text("补充说明")
                                            .font(.system(size: 13, weight: .semibold))
                                        Spacer(minLength: 0)
                                        Text("发给模型")
                                            .font(.system(size: 10))
                                            .foregroundStyle(.secondary)
                                    }
                                    Text("写清流程背景、对象或专有名词。留空也可以直接生成。")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                    TextEditor(text: $model.previewUserNote)
                                        .font(.system(size: 13))
                                        .scrollContentBackground(.hidden)
                                        .padding(8)
                                        .frame(minHeight: 96, maxHeight: 140)
                                        .background(Color.sopPaper)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6)
                                                .stroke(Color.secondary.opacity(0.22), lineWidth: 1)
                                        )
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                }
                            }
                            .frame(width: 286, alignment: .topLeading)
                            .padding(.top, 6)
                        }
                        .padding(.horizontal, 30)
                        .padding(.top, 22)

                        VStack(alignment: .leading, spacing: 9) {
                            HStack(alignment: .firstTextBaseline) {
                                Text("已捕获截图")
                                    .font(.system(size: 13, weight: .semibold))
                                Text("点击查看")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("\(model.previewFrames.count) 张")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }

                            ScrollView(.horizontal, showsIndicators: true) {
                                HStack(alignment: .top, spacing: 9) {
                                    ForEach(Array(model.previewFrames.enumerated()), id: \.offset) { index, frame in
                                        Button {
                                            selectedIndex = index
                                        } label: {
                                            VStack(alignment: .leading, spacing: 5) {
                                                Image(nsImage: frame.image)
                                                    .resizable()
                                                    .aspectRatio(contentMode: .fill)
                                                    .frame(width: 144, height: 82)
                                                    .clipped()
                                                HStack(spacing: 5) {
                                                    Text(String(format: "%02d", index + 1))
                                                        .font(.system(size: 10, design: .monospaced))
                                                    Text("\(String(format: "%.1f", frame.timestamp)) 秒")
                                                        .font(.system(size: 10))
                                                        .foregroundStyle(.secondary)
                                                }
                                            }
                                            .padding(6)
                                            .background(index == visibleIndex ? Color.sopAccent.opacity(0.11) : Color.sopSurface)
                                            .overlay(
                                                Rectangle()
                                                    .stroke(index == visibleIndex ? Color.sopAccent : Color.secondary.opacity(0.22), lineWidth: index == visibleIndex ? 2 : 1)
                                            )
                                        }
                                        .buttonStyle(.plain)
                                        .help("查看第 \(index + 1) 张操作截图")
                                    }
                                }
                                .padding(.vertical, 3)
                            }
                        }
                        .padding(.horizontal, 30)
                        .padding(.top, 22)
                        .padding(.bottom, 28)
                    } else {
                        VStack(spacing: 10) {
                            Text("没有生成可预览的操作截图")
                                .font(.system(size: 15, weight: .semibold))
                            Text("请重新采集，并在过程中完成需要记录的操作。")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                            Button("重新采集") {
                                model.restartFromPreview()
                            }
                            .buttonStyle(SOPQuietButtonStyle())
                        }
                        .frame(maxWidth: .infinity, minHeight: 360)
                    }
                }
            }
            .background(Color.sopBackground)
        }
        .alert("删除这张截图？", isPresented: $isDeleteConfirmationPresented) {
            Button("删除图片", role: .destructive) {
                deleteSelectedFrame()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("这张截图及其对应的操作数据会从本次预览中移除。")
        }
        .background(WindowSizeView(targetContentSize: NSSize(width: 1120, height: 720)))
    }

    private func deleteSelectedFrame() {
        let index = visibleIndex
        model.deletePreviewFrame(at: index)
        if model.previewFrames.isEmpty {
            selectedIndex = 0
        } else {
            selectedIndex = min(selectedIndex, model.previewFrames.count - 1)
        }
    }

    private struct InputEventRow: View {
        let event: InputTimelineEvent

        var body: some View {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: symbolName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.sopTeal)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(event.displayLabel)
                            .font(.system(size: 12, weight: .semibold))
                        Spacer(minLength: 0)
                        Text(String(format: "%.1f 秒", event.timestamp))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }

                    if let location = event.location {
                        Text("鼠标位置  \(Self.percent(location.x)), \(Self.percent(location.y))")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    } else if event.keyLabel != nil {
                        Text("已记录按键类别，不记录具体输入内容")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("未记录具体按键内容")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(9)
            .background(Color.sopSurface)
            .overlay(
                Rectangle()
                    .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
            )
        }

        private var symbolName: String {
            switch event.kind {
            case .click: return "cursorarrow.click"
            case .drag: return "hand.draw"
            case .scroll: return "arrow.up.and.down"
            case .typing: return "keyboard"
            case .confirm: return "return"
            case .keyAction: return "keyboard"
            case .navigation: return "arrow.left.arrow.right"
            case .shortcut: return "command"
            }
        }

        private static func percent(_ value: CGFloat) -> String {
            "\(Int((value * 100).rounded()))%"
        }
    }

    private struct AnnotatedFrameImageView: View {
        let image: NSImage
        let clickEvents: [InputTimelineEvent]

        var body: some View {
            GeometryReader { proxy in
                let imageBounds = CGSize(
                    width: max(0, proxy.size.width - 24),
                    height: max(0, proxy.size.height - 24)
                )
                let imageSize = aspectFitSize(for: image.size, in: imageBounds)
                let imageOrigin = CGPoint(
                    x: (proxy.size.width - imageSize.width) / 2,
                    y: (proxy.size.height - imageSize.height) / 2
                )

                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.sopMuted)

                    Image(nsImage: image)
                        .resizable()
                        .frame(width: imageSize.width, height: imageSize.height)

                    ForEach(Array(clickEvents.enumerated()), id: \.offset) { index, event in
                        if let location = event.location {
                            ClickMarker(number: index + 1)
                                .position(
                                    x: imageOrigin.x + normalized(location.x) * imageSize.width,
                                    y: imageOrigin.y + normalized(location.y) * imageSize.height
                                )
                        }
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("操作截图，已标记 \(clickEvents.count) 个鼠标点击位置")
            }
        }

        private func aspectFitSize(for imageSize: CGSize, in bounds: CGSize) -> CGSize {
            guard imageSize.width > 0, imageSize.height > 0, bounds.width > 0, bounds.height > 0 else {
                return .zero
            }
            let scale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
            return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        }

        private func normalized(_ value: CGFloat) -> CGFloat {
            min(max(value, 0), 1)
        }
    }

    private struct ClickMarker: View {
        let number: Int

        var body: some View {
            ZStack {
                Circle()
                    .fill(Color.sopAccent.opacity(0.20))
                    .frame(width: 22, height: 22)
                Circle()
                    .fill(Color.sopAccent)
                    .frame(width: 15, height: 15)
                Text("\(number)")
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .shadow(color: .black.opacity(0.28), radius: 2, y: 1)
            .accessibilityHidden(true)
        }
    }
}

struct ResultPreviewView: View {
    @EnvironmentObject private var model: SOPModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(
                        model.aiEngineLabel == "演示内容" ? "演示预览" : "说明已生成"
                    )
                        .font(.system(size: 18, weight: .semibold))
                    Text("\(model.steps.count) 个步骤 · \(model.aiEngineLabel)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("重新采集") {
                    model.startRecording()
                }
                .buttonStyle(SOPQuietButtonStyle())
                Button("编辑结果") {
                    model.isEditing = true
                }
                .buttonStyle(SOPQuietButtonStyle())
                Menu {
                    Button("导出 HTML") { model.exportHTML() }
                    Button("导出 Markdown") { model.exportMarkdown() }
                } label: {
                    Text("导出")
                }
                .buttonStyle(SOPDarkButtonStyle())
            }
            .padding(.horizontal, 24)
            .frame(height: 70)

            Divider()

            if let banner = model.banner {
                BannerView(banner: banner)
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
            }

            ScrollView {
                PaperView()
                    .padding(.horizontal, 28)
                    .padding(.vertical, 36)
            }
            .background(Color.sopBackground)
        }
        .background(WindowSizeView(targetContentSize: NSSize(width: 1120, height: 720)))
    }
}

struct EditorWorkspaceView: View {
    var body: some View {
        HStack(spacing: 0) {
            SidebarView()
            Divider()
            WorkbenchView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            InspectorView()
        }
        .background(WindowSizeView(targetContentSize: NSSize(width: 1120, height: 720)))
    }
}

struct EmptyStartView: View {
    @EnvironmentObject private var model: SOPModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text("操作截图")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                ModelSelectorMenu()
            }

            Text("开始截图")
                .font(.system(size: 18, weight: .semibold))
                .tracking(-0.3)
                .padding(.top, 18)

            Text("按平时方式操作电脑。点击和关键按键会保存截图，再整理成说明。")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)

            if let banner = model.banner {
                BannerView(banner: banner)
                    .padding(.top, 12)
            }

            Button {
                model.startRecording()
            } label: {
                HStack {
                    ScreenshotGlyph(active: false)
                        .foregroundStyle(.white.opacity(0.95))
                    Text("开始截图")
                    Spacer()
                    Text("⌘⇧R")
                        .font(.system(size: 11, design: .monospaced))
                        .opacity(0.7)
                }
            }
            .buttonStyle(SOPFilledButtonStyle(tone: .accent))
            .padding(.top, 16)
        }
        .padding(.horizontal, 22)
        .padding(.top, 18)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(WindowSizeView(targetContentSize: NSSize(width: 400, height: 210)))
    }
}

struct ModelSelectorMenu: View {
    @EnvironmentObject private var model: SOPModel

    var body: some View {
        Menu {
            if model.configuredModelOptions.isEmpty {
                Text(model.modelConfiguration.isConfigured ? "正在读取已配置模型" : "尚未配置视觉模型")
            } else {
                ForEach(configuredProviders) { provider in
                    Section(provider.displayName) {
                        ForEach(options(for: provider)) { option in
                            Button {
                                model.selectConfiguredModel(option)
                            } label: {
                                HStack {
                                    Text(option.modelLabel)
                                    if option.id == model.selectedConfiguredModelID {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 7) {
                Circle()
                    .fill(model.modelConfiguration.isConfigured ? Color.sopTeal : Color.sopAccent)
                    .frame(width: 6, height: 6)
                Text(model.modelConfiguration.isConfigured ? model.modelConfiguration.displayName : "未配置模型")
                    .font(.system(size: 12))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.sopMuted)
            .clipShape(Capsule())
        }
        .menuStyle(.borderlessButton)
        .help("选择已配置的视觉模型")
        .accessibilityLabel("选择模型")
    }

    private var configuredProviders: [ModelProvider] {
        ModelProvider.allCases.filter { provider in
            model.configuredModelOptions.contains { $0.provider == provider }
        }
    }

    private func options(for provider: ModelProvider) -> [ConfiguredModelOption] {
        model.configuredModelOptions.filter { $0.provider == provider }
    }
}

struct OnboardingUnavailableView: View {
    @EnvironmentObject private var model: SOPModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("软件使用引导")
                .font(.system(size: 20, weight: .semibold))
            Text("请先清空当前草稿并回到悬浮球，再从菜单里打开「使用说明」。引导会在真实界面上逐步提示，并用演示数据完成一次完整流程。")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("关闭") {
                    model.dismissOnboarding()
                }
                .buttonStyle(SOPQuietButtonStyle())
            }
        }
        .padding(24)
        .frame(width: 380)
    }
}

private struct WindowSizeView: NSViewRepresentable {
    let targetContentSize: NSSize

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            Self.fit(window: view.window, targetContentSize: targetContentSize)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            Self.fit(window: nsView.window, targetContentSize: targetContentSize)
        }
    }

    private static func fit(window: NSWindow?, targetContentSize: NSSize) {
        guard let window else { return }
        let currentSize = window.contentLayoutRect.size
        guard abs(currentSize.width - targetContentSize.width) > 20
                || abs(currentSize.height - targetContentSize.height) > 20 else { return }
        window.setContentSize(targetContentSize)
    }
}

struct SidebarView: View {
    @EnvironmentObject private var model: SOPModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            BrandHeader()
                .padding(.bottom, 24)

            VStack(alignment: .leading, spacing: 7) {
                Text("当前草稿")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline) {
                    Text(model.displayTitle)
                        .font(.system(size: 16, weight: .semibold))
                        .lineLimit(1)
                    Spacer()
                    Text("\(model.steps.count) 步")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            VStack(spacing: 8) {
                Button {
                    model.toggleRecording()
                } label: {
                    HStack(spacing: 8) {
                        ScreenshotGlyph(active: model.phase == .recording)
                            .foregroundStyle(.white.opacity(0.95))
                        Text(model.phase.label)
                        Spacer()
                        if model.phase == .recording {
                            Text("\(model.queuedScreenshotCount) 张")
                                .font(.system(size: 11, design: .monospaced))
                        }
                    }
                }
                .buttonStyle(SOPFilledButtonStyle(tone: .accent))
                .disabled(model.phase == .preparing || model.phase == .extracting || model.phase == .processing)

                Button {
                    model.requestLoadDemo()
                } label: {
                    HStack {
                        Text("载入演示")
                        Spacer()
                    }
                }
                .buttonStyle(SOPQuietButtonStyle())
                .disabled(model.phase != .idle)
            }
            .padding(.top, 20)

            if model.phase != .idle {
                CaptureStatusView(
                    phase: model.phase,
                    screenshotCount: model.queuedScreenshotCount
                )
                    .padding(.top, 12)
            }

            if model.steps.isEmpty {
                EmptyRailView()
                    .padding(.top, 22)
            } else {
                ScrollView {
                    LazyVStack(spacing: 7) {
                        ForEach(model.steps) { step in
                            StepListRow(step: step, isSelected: step.id == model.selectedStepID)
                                .onTapGesture { model.selectStep(step) }
                        }
                    }
                    .padding(.top, 20)
                }
                .scrollIndicators(.visible)
            }

            Spacer(minLength: 20)

            Text("说明已经生成。需要时可以微调，导出前检查隐私。")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 14)
            .overlay(alignment: .top) { Divider() }
        }
        .padding(18)
        .frame(width: 248)
        .background(Color.sopSurface)
    }
}

struct BrandHeader: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: Self.brandIcon)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 6.5, style: .continuous))
            VStack(alignment: .leading, spacing: 0) {
                Text("SOPShot")
                    .font(.system(size: 17, weight: .bold))
                Text("操作截图")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private static let brandIcon: NSImage = loadBrandIcon()

    private static func loadBrandIcon() -> NSImage {
        if let url = Bundle.module.url(forResource: "AppIcon", withExtension: "png"),
           let icon = NSImage(contentsOf: url) {
            return icon
        }
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "png"),
           let icon = NSImage(contentsOf: url) {
            return icon
        }
        if let url = Bundle.main.url(forResource: "SOPShot", withExtension: "icns"),
           let icon = NSImage(contentsOf: url) {
            return icon
        }
        return NSImage(size: NSSize(width: 128, height: 128))
    }
}

/// Small frame mark used wherever the old record glyph / red recording dot lived.
struct ScreenshotGlyph: View {
    var active: Bool = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 2)
                .stroke(lineWidth: active ? 1.8 : 1.5)
                .frame(width: 11, height: 9)
            Rectangle()
                .frame(width: 5, height: 1.5)
                .offset(x: 3, y: -2)
        }
        .frame(width: 12, height: 10)
    }
}

struct CaptureStatusView: View {
    let phase: CapturePhase
    var screenshotCount: Int = 0

    var body: some View {
        HStack(spacing: 8) {
            ScreenshotGlyph(active: phase == .recording)
                .foregroundStyle(phase == .recording ? Color.sopAccent : Color.secondary)
            Text(statusLabel)
                .font(.system(size: 11))
            Spacer()
        }
        .foregroundStyle(phase == .recording ? Color.sopAccent : .secondary)
        .padding(9)
        .background(Color.sopMuted)
        .overlay(Rectangle().stroke(Color.sopAccent.opacity(0.35), lineWidth: 1))
    }

    private var statusLabel: String {
        switch phase {
        case .recording:
            return screenshotCount == 0 ? "等待第一次截图" : "已截 \(screenshotCount) 张"
        case .preparing:
            return "准备截图"
        case .extracting:
            return "整理截图"
        case .processing:
            return "生成说明"
        case .preview:
            return "检查截图"
        case .idle:
            return "空闲"
        }
    }
}

struct EmptyRailView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Rectangle()
                .fill(Color.secondary.opacity(0.35))
                .frame(width: 44, height: 1)
            Text("还没有操作截图")
                .font(.system(size: 13, weight: .semibold))
            Text("开始截图后，每次鼠标点击或关键按键都会保存一张屏幕截图。")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct StepListRow: View {
    let step: SOPStep
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 9) {
            Image(nsImage: step.image)
                .resizable()
                .scaledToFill()
                .frame(width: 30, height: 30)
                .clipped()
                .overlay(Rectangle().stroke(Color.secondary.opacity(0.25), lineWidth: 1))
            VStack(alignment: .leading, spacing: 1) {
                Text(step.title.isEmpty ? "未命名步骤" : step.title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Text(step.note.isEmpty ? "还没有补充说明" : step.note)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(7)
        .background(isSelected ? Color.sopAccent.opacity(0.16) : Color.clear)
        .overlay(Rectangle().stroke(isSelected ? Color.sopAccent : Color.clear, lineWidth: 1))
        .contentShape(Rectangle())
    }
}

struct WorkbenchView: View {
    @EnvironmentObject private var model: SOPModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                HStack(spacing: 8) {
                    Text("本地草稿")
                        .foregroundStyle(.secondary)
                    Text("/")
                        .foregroundStyle(.tertiary)
                    Text(model.displayTitle)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                }
                .font(.system(size: 12))
                Spacer()
                HStack(spacing: 7) {
                    Button("完成编辑") { model.isEditing = false }
                        .buttonStyle(SOPQuietButtonStyle())
                    Button("重新开始") { model.clearDraft() }
                        .buttonStyle(SOPQuietButtonStyle())
                    Button("导出 HTML") { model.exportHTML() }
                        .buttonStyle(SOPDarkButtonStyle())
                    Button("导出 Markdown") { model.exportMarkdown() }
                        .buttonStyle(SOPAccentButtonStyle())
                }
            }
            .padding(.horizontal, 24)
            .frame(height: 64)

            Divider()

            if let banner = model.banner {
                BannerView(banner: banner)
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
            }

            ScrollView {
                PaperView()
                    .padding(.horizontal, 28)
                    .padding(.vertical, 36)
            }
            .background(Color.sopBackground)
        }
    }
}

struct BannerView: View {
    let banner: SOPBanner

    private var tint: Color {
        switch banner.tone {
        case .info: return .secondary
        case .success: return .sopTeal
        case .warning: return .sopAccent
        case .error: return .sopDanger
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(tint).frame(width: 7, height: 7)
            Text(banner.text)
                .font(.system(size: 12))
                .foregroundStyle(tint)
            Spacer()
        }
        .padding(10)
        .background(Color.sopMuted)
        .overlay(Rectangle().stroke(tint.opacity(0.35), lineWidth: 1))
    }
}

struct PaperView: View {
    @EnvironmentObject private var model: SOPModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 3)
                    .stroke(Color.sopAccent, lineWidth: 2)
                    .frame(width: 12, height: 12)
                Text("操作说明")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                    Text(model.isEditing ? "编辑中" : "预览")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .overlay(Rectangle().stroke(Color.secondary.opacity(0.4), lineWidth: 1))
            }

            HStack(alignment: .bottom, spacing: 28) {
                VStack(alignment: .leading, spacing: 8) {
                    if model.isEditing {
                        TextField("给说明起个标题", text: $model.title)
                            .textFieldStyle(.plain)
                            .font(.system(size: 34, weight: .bold))
                            .tracking(-1.2)
                    } else {
                        Text(model.displayTitle)
                            .font(.system(size: 34, weight: .bold))
                            .tracking(-1.2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(model.isEditing ? (model.title.isEmpty ? "标题说清楚这份说明要完成什么。" : "可以继续补充适用对象，再检查每一步。") : previewHint)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Text("适用对象")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        if model.isEditing {
                            TextField("例如：新入职同事", text: $model.audience)
                                .textFieldStyle(.plain)
                                .font(.system(size: 12))
                                .frame(width: 155)
                        } else {
                            Text(model.audience.isEmpty ? "未指定" : model.audience)
                                .font(.system(size: 12))
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                        }
                    }
                    HStack(spacing: 10) {
                        Text("步骤")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Text("\(model.steps.count)")
                            .font(.system(size: 12, design: .monospaced))
                    }
                }
            }
            .padding(.vertical, 24)

            Divider()
                .padding(.bottom, 26)

            if !model.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    Text("流程目标")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(model.summary)
                        .font(.system(size: 14))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.bottom, 26)
            }

            if model.steps.isEmpty {
                EmptyPaperView()
            } else {
                VStack(spacing: 20) {
                    ForEach(Array(model.steps.enumerated()), id: \.element.id) { index, step in
                        PaperStepView(index: index, step: step)
                    }
                }
            }

            Divider()
                .padding(.top, 20)
            HStack {
                Text("导出文件会包含图片，可离线打开。")
                Spacer()
                Text(model.steps.isEmpty ? "尚未生成" : model.aiEngineLabel)
            }
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .padding(.top, 14)
        }
        .padding(44)
        .frame(maxWidth: 760, alignment: .leading)
        .background(Color.sopPaper)
        .shadow(color: .black.opacity(0.12), radius: 18, y: 8)
    }

    private var previewHint: String {
        switch model.aiEngineLabel {
        case "演示内容": return "演示内容，可进入编辑"
        default: return "根据操作截图生成，可继续编辑"
        }
    }
}

struct EmptyPaperView: View {
    @EnvironmentObject private var model: SOPModel

    var body: some View {
        VStack(spacing: 14) {
            Rectangle()
                .fill(Color.secondary.opacity(0.35))
                .frame(width: 50, height: 58)
                .overlay(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 7) {
                        Rectangle().fill(Color.secondary.opacity(0.45)).frame(width: 26, height: 3)
                        Rectangle().fill(Color.secondary.opacity(0.45)).frame(width: 19, height: 3)
                    }
                    .padding(11)
                }
            Text("这张说明还没有步骤")
                .font(.system(size: 18, weight: .semibold))
            Text("按顺序完成一次电脑操作，每次鼠标点击或关键按键都会生成一张截图，最后排成一页可交接的说明。")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            Button("开始截图") { model.startRecording() }
                .buttonStyle(SOPFilledButtonStyle(tone: .accent))
        }
        .frame(maxWidth: .infinity, minHeight: 360)
        .overlay(Rectangle().stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 4])).foregroundStyle(Color.secondary.opacity(0.45)))
    }
}

struct PaperStepView: View {
    let index: Int
    let step: SOPStep

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            ZStack(alignment: .topLeading) {
                Image(nsImage: step.image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 270)
                    .background(Color.sopMuted)
                    .overlay(Rectangle().stroke(Color.secondary.opacity(0.3), lineWidth: 1))
                Text(String(format: "%02d", index + 1))
                    .font(.system(size: 11, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 5)
                    .background(Color.sopPaper)
                    .overlay(Rectangle().stroke(Color.primary, lineWidth: 1))
                    .padding(10)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(step.title.isEmpty ? "未命名步骤" : step.title)
                    .font(.system(size: 16, weight: .semibold))
                if !step.note.isEmpty {
                    Text(step.note)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !step.tip.isEmpty {
                    Text("提醒：\(step.tip)")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.sopAccent)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.sopAccent.opacity(0.12))
                        .overlay(alignment: .leading) { Rectangle().fill(Color.sopAccent).frame(width: 2) }
                }
            }
            .frame(minWidth: 180, maxWidth: 240, alignment: .leading)
            .padding(.top, 4)
        }
        .padding(.bottom, 18)
        .overlay(alignment: .bottom) { Divider() }
    }
}

struct InspectorView: View {
    @EnvironmentObject private var model: SOPModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("当前步骤")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(model.selectedStep.map { $0.title.isEmpty ? "未命名步骤" : $0.title } ?? "未选择")
                        .font(.system(size: 16, weight: .semibold))
                        .lineLimit(2)
                }
                Spacer()
                Text(model.selectedIndex.map { String(format: "%02d", $0 + 1) } ?? "00")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            if let index = model.selectedIndex {
                StepEditor(index: index)
                    .padding(.top, 28)
            } else {
                VStack(alignment: .leading, spacing: 9) {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.35))
                        .frame(width: 46, height: 1)
                    Text("先完成一遍操作截图")
                        .font(.system(size: 16, weight: .semibold))
                    Text("结束截图后，先确认每次点击对应的画面，再发送给当前模型。")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 74)
            }

            Spacer(minLength: 30)

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    Text("□")
                        .foregroundStyle(Color.sopTeal)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("隐私检查")
                            .font(.system(size: 13, weight: .semibold))
                        Text("导出前看看截图里有没有不该发出去的资料。")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Button("显示遮盖建议") {
                    model.banner = SOPBanner(text: "导出前请检查姓名、邮箱、手机号、账号、订单号和客户资料。原型当前不会自动遮盖。", tone: .info)
                }
                .buttonStyle(.link)
                .font(.system(size: 12, weight: .semibold))
            }
            .padding(.top, 17)
            .overlay(alignment: .top) { Divider() }
        }
        .padding(22)
        .frame(width: 292)
        .background(Color.sopSurface)
    }
}

struct StepEditor: View {
    @EnvironmentObject private var model: SOPModel
    let index: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            EditorField(title: "步骤标题", text: binding(\.title), placeholder: "例如：进入费用管理")
            EditorTextField(title: "补充说明", text: binding(\.note), placeholder: "告诉接手的人，这一步要完成什么", minHeight: 76)
            EditorTextField(title: "提醒", text: binding(\.tip), placeholder: "可选，例如：提交前检查金额", minHeight: 62)

            Divider()
                .padding(.vertical, 3)

            HStack(spacing: 6) {
                Button("上移") { model.moveSelected(by: -1) }
                    .buttonStyle(SOPQuietButtonStyle())
                    .disabled(index == 0)
                Button("下移") { model.moveSelected(by: 1) }
                    .buttonStyle(SOPQuietButtonStyle())
                    .disabled(index == model.steps.count - 1)
                Button("删除") { model.deleteSelected() }
                    .buttonStyle(SOPDangerButtonStyle())
            }

            Button("整理这一步") { model.composeSelected() }
                .buttonStyle(SOPDarkButtonStyle())
                .frame(maxWidth: .infinity)
                .padding(.top, 2)
            Text("只修改当前说明，不会重新发送截图。")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private func binding(_ keyPath: WritableKeyPath<SOPStep, String>) -> Binding<String> {
        Binding(
            get: { model.selectedStep?[keyPath: keyPath] ?? "" },
            set: { model.updateSelected(keyPath, value: $0) }
        )
    }
}

struct EditorField: View {
    let title: String
    @Binding var text: String
    let placeholder: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13))
        }
    }
}

struct EditorTextField: View {
    let title: String
    @Binding var text: String
    let placeholder: String
    let minHeight: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            ZStack(alignment: .topLeading) {
                TextEditor(text: $text)
                    .font(.system(size: 13))
                    .frame(minHeight: minHeight)
                    .padding(5)
                    .scrollContentBackground(.hidden)
                    .background(Color.sopPaper)
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.secondary.opacity(0.35), lineWidth: 1))
                if text.isEmpty {
                    Text(placeholder)
                        .font(.system(size: 13))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 12)
                        .allowsHitTesting(false)
                }
            }
        }
    }
}

enum SOPButtonTone {
    case accent
    case danger
}

struct SOPFilledButtonStyle: ButtonStyle {
    let tone: SOPButtonTone

    func makeBody(configuration: Configuration) -> some View {
        SOPFilledButtonBody(configuration: configuration, tone: tone)
    }
}

private struct SOPFilledButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let tone: SOPButtonTone
    @State private var isHovered = false

    var body: some View {
        configuration.label
            .padding(.horizontal, 12)
            .frame(minHeight: 40)
            .background(fillColor)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .opacity(configuration.isPressed ? 0.82 : 1)
            .onHover { hovering in
                guard isHovered != hovering else { return }
                withAnimation(.easeOut(duration: 0.12)) {
                    isHovered = hovering
                }
            }
    }

    private var fillColor: Color {
        let base = tone == .accent ? Color.sopAccent : Color.sopDanger
        if configuration.isPressed {
            return base
        }
        return isHovered ? base.opacity(0.88) : base
    }
}

struct SOPQuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        SOPQuietButtonBody(configuration: configuration)
    }
}

private struct SOPQuietButtonBody: View {
    let configuration: ButtonStyle.Configuration
    @State private var isHovered = false

    var body: some View {
        configuration.label
            .padding(.horizontal, 11)
            .frame(minHeight: 40)
            .background(
                configuration.isPressed
                    ? Color.sopMuted.opacity(0.82)
                    : (isHovered ? Color.sopMuted.opacity(0.55) : Color.clear)
            )
            .foregroundStyle(.primary)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(isHovered || configuration.isPressed ? 0.5 : 0.35), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .onHover { hovering in
                guard isHovered != hovering else { return }
                withAnimation(.easeOut(duration: 0.12)) {
                    isHovered = hovering
                }
            }
    }
}

struct SOPDarkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        SOPDarkButtonBody(configuration: configuration)
    }
}

private struct SOPDarkButtonBody: View {
    let configuration: ButtonStyle.Configuration
    @State private var isHovered = false

    var body: some View {
        configuration.label
            .padding(.horizontal, 12)
            .frame(minHeight: 40)
            .background(Color.primary.opacity(configuration.isPressed ? 1 : (isHovered ? 0.88 : 1)))
            .foregroundStyle(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .opacity(configuration.isPressed ? 0.8 : 1)
            .onHover { hovering in
                guard isHovered != hovering else { return }
                withAnimation(.easeOut(duration: 0.12)) {
                    isHovered = hovering
                }
            }
    }
}

struct SOPAccentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        SOPAccentButtonBody(configuration: configuration)
    }
}

private struct SOPAccentButtonBody: View {
    let configuration: ButtonStyle.Configuration
    @State private var isHovered = false

    var body: some View {
        configuration.label
            .padding(.horizontal, 12)
            .frame(minHeight: 40)
            .background(Color.sopAccent.opacity(configuration.isPressed ? 0.18 : (isHovered ? 0.28 : 0.18)))
            .foregroundStyle(Color.sopAccent)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.sopAccent, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .opacity(configuration.isPressed ? 0.78 : 1)
            .onHover { hovering in
                guard isHovered != hovering else { return }
                withAnimation(.easeOut(duration: 0.12)) {
                    isHovered = hovering
                }
            }
    }
}

struct SOPDangerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        SOPDangerButtonBody(configuration: configuration)
    }
}

private struct SOPDangerButtonBody: View {
    let configuration: ButtonStyle.Configuration
    @State private var isHovered = false

    var body: some View {
        configuration.label
            .padding(.horizontal, 11)
            .frame(minHeight: 40)
            .background(isHovered || configuration.isPressed ? Color.sopDanger.opacity(0.12) : Color.clear)
            .foregroundStyle(Color.sopDanger)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.sopDanger.opacity(isHovered ? 0.7 : 0.5), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .opacity(configuration.isPressed ? 0.78 : 1)
            .onHover { hovering in
                guard isHovered != hovering else { return }
                withAnimation(.easeOut(duration: 0.12)) {
                    isHovered = hovering
                }
            }
    }
}
