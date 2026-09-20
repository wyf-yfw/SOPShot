import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

struct SOPStep: Identifiable {
    let id: UUID
    var title: String
    var note: String
    var tip: String
    var image: NSImage
    var sourceName: String

    init(
        id: UUID = UUID(),
        title: String = "",
        note: String = "",
        tip: String = "",
        image: NSImage,
        sourceName: String = ""
    ) {
        self.id = id
        self.title = title
        self.note = note
        self.tip = tip
        self.image = image
        self.sourceName = sourceName
    }
}

enum CapturePhase: Equatable {
    case idle
    case preparing
    case recording
    case extracting
    case preview
    case processing

    var label: String {
        switch self {
        case .idle: return "开始截图"
        case .preparing: return "准备中"
        case .recording: return "结束截图"
        case .extracting: return "整理截图"
        case .preview: return "检查截图"
        case .processing: return "生成说明"
        }
    }
}

enum CaptureOrbSize: String, CaseIterable, Identifiable, Hashable {
    case small
    case medium
    case large

    var id: String { rawValue }

    var title: String {
        switch self {
        case .small: return "小"
        case .medium: return "中"
        case .large: return "大"
        }
    }

    var diameter: CGFloat {
        switch self {
        case .small: return 36
        case .medium: return 44
        case .large: return 54
        }
    }
}

enum DebugDestination: String, CaseIterable, Identifiable {
    case emptyStart
    case preparing
    case recording
    case extracting
    case processing
    case preview
    case result
    case editor
    case modelSettings
    case captureSettings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .emptyStart: return "空白开始页"
        case .preparing: return "准备截图"
        case .recording: return "截图进行中"
        case .extracting: return "整理截图"
        case .processing: return "生成说明中"
        case .preview: return "检查截图"
        case .result: return "最终预览"
        case .editor: return "编辑工作台"
        case .modelSettings: return "模型设置"
        case .captureSettings: return "截图设置"
        }
    }

    var detail: String {
        switch self {
        case .emptyStart: return "空草稿，可点开始截图"
        case .preparing: return "紧凑状态面板 · 准备中"
        case .recording: return "紧凑状态面板 · 已截 7 张"
        case .extracting: return "紧凑状态面板 · 整理中"
        case .processing: return "紧凑状态面板 · 生成中"
        case .preview: return "带演示截图与操作数据"
        case .result: return "报销单演示说明"
        case .editor: return "在演示说明上进入编辑"
        case .modelSettings: return "弹出模型设置表单"
        case .captureSettings: return "弹出截图触发设置"
        }
    }

    var keepsDebugSession: Bool {
        switch self {
        case .preparing, .recording, .extracting, .processing, .preview:
            return true
        case .emptyStart, .result, .editor, .modelSettings, .captureSettings:
            return false
        }
    }
}

enum PendingConfirmation: Identifiable, Equatable {
    case restartPreview
    case closePreview
    case deleteStep
    case clearDraft
    case loadDemo

    var id: String {
        switch self {
        case .restartPreview: return "restartPreview"
        case .closePreview: return "closePreview"
        case .deleteStep: return "deleteStep"
        case .clearDraft: return "clearDraft"
        case .loadDemo: return "loadDemo"
        }
    }

    var title: String {
        switch self {
        case .restartPreview: return "放弃这次操作采集并重新开始？"
        case .closePreview: return "关闭并放弃本次采集？"
        case .deleteStep: return "删除当前步骤？"
        case .clearDraft: return "清空当前草稿？"
        case .loadDemo: return "载入演示草稿？"
        }
    }

    var message: String {
        switch self {
        case .restartPreview: return "当前已经采集的操作截图都会被删除。"
        case .closePreview: return "确认后将丢弃本次采集的截图和补充说明，并回到悬浮球。这些内容不会保存，也无法恢复。"
        case .deleteStep: return "这只会从当前草稿中移除这一步。"
        case .clearDraft: return "这只会清除当前窗口中的草稿内容。"
        case .loadDemo: return "这会替换当前窗口中的草稿内容。"
        }
    }

    var confirmTitle: String {
        switch self {
        case .restartPreview: return "重新采集"
        case .closePreview: return "关闭并丢弃"
        case .deleteStep: return "删除"
        case .clearDraft: return "清空"
        case .loadDemo: return "载入"
        }
    }

    var isDestructive: Bool {
        switch self {
        case .restartPreview, .closePreview, .deleteStep, .clearDraft:
            return true
        case .loadDemo:
            return false
        }
    }
}

enum BannerTone {
    case info
    case success
    case warning
    case error
}

struct SOPBanner: Identifiable {
    let id = UUID()
    let text: String
    let tone: BannerTone
}

@MainActor
enum GuidedTourStep: Int, CaseIterable, Equatable {
    case openOrb
    case pickModel
    case startCapture
    case stopCapture
    case deleteScreenshot
    case generate
    case exportMarkdown
    case finished

    var title: String {
        switch self {
        case .openOrb: return "软件使用  1/7"
        case .pickModel: return "软件使用  2/7"
        case .startCapture: return "软件使用  3/7"
        case .stopCapture: return "软件使用  4/7"
        case .deleteScreenshot: return "软件使用  5/7"
        case .generate: return "软件使用  6/7"
        case .exportMarkdown: return "软件使用  7/7"
        case .finished: return "软件使用  完成"
        }
    }

    var message: String {
        switch self {
        case .openOrb:
            return "点击左上角悬浮球打开菜单。引导会用真实界面操作，截图和说明都来自演示数据。"
        case .pickModel:
            return "在菜单里点「选择模型」并选一个已配置模型。若还没有模型，先打开「模型设置」保存 API Key。"
        case .startCapture:
            return "选择模型后菜单会关闭。再点悬浮球打开菜单，然后点「开始截图」进入演示采集。"
        case .stopCapture:
            return "演示采集进行中。点击悬浮球结束截图，会打开真实的检查页并载入演示画面。"
        case .deleteScreenshot:
            return "在检查页删除一张不需要的截图，确认后点「开始生成说明」。"
        case .generate:
            return "点「开始生成说明」。引导不会访问网络，会直接载入演示说明稿。"
        case .exportMarkdown:
            return "在结果页导出 Markdown。这会真正弹出保存面板，写入的是演示内容。"
        case .finished:
            return "引导已完成。之后可以从悬浮球直接开始真实截图。"
        }
    }
}

enum GuidedTourEvent: Equatable {
    case orbMenuOpened
    case modelSelected
    case modelSettingsSaved
    case captureStarted
    case captureStopped
    case previewFrameDeleted
    case generateFinished
    case exported
}

@MainActor
final class SOPModel: ObservableObject {
    @Published var title = ""
    @Published var audience = ""
    @Published var steps: [SOPStep] = []
    @Published var selectedStepID: UUID?
    @Published var phase: CapturePhase = .idle
    @Published var banner: SOPBanner?
    @Published var recordingStartedAt: Date?
    @Published var queuedScreenshotCount = 0
    @Published var summary = ""
    @Published var aiEngineLabel = ""
    @Published var isEditing = false
    @Published var modelProvider: ModelProvider
    @Published var modelInputMode: ModelInputMode
    @Published var modelName: String
    @Published var modelEndpoint: String
    @Published var modelAPIKey = ""
    @Published var isAPIKeyLoading = false
    @Published var modelTestState: ModelTestState = .idle
    @Published var isModelSettingsPresented = false
    @Published var isCaptureSettingsPresented = false
    @Published var isDebugAssistantPresented = false
    @Published var isHelpPresented = false
    /// Active guided tour step; `nil` means tour is not running.
    @Published var guidedTourStep: GuidedTourStep?
    /// When true, capture UI is a debug preview and must not hide the window or show the capture orb.
    @Published var isDebugSession = false
    @Published var pendingConfirmation: PendingConfirmation?
    @Published var configuredModelOptions: [ConfiguredModelOption] = []
    @Published var previewFrames: [CapturedFrame] = []
    @Published var previewUserNote = ""
    @Published var previewInputMode: ModelInputMode?
    @Published var previewModelLabel = ""
    @Published var previewInputMonitoringAvailable = false
    @Published var inputMonitoringAvailable = false
    @Published var isInputMonitoringPermissionAlertPresented = false
    @Published var screenshotTriggers: ScreenshotTriggerPolicy
    @Published var captureOrbSize: CaptureOrbSize {
        didSet {
            UserDefaults.standard.set(captureOrbSize.rawValue, forKey: Self.captureOrbSizeKey)
        }
    }

    var prefersOrbShell: Bool {
        phase == .idle && steps.isEmpty && !isEditing && !isDebugSession
    }

    var isGuidedTourActive: Bool {
        guidedTourStep != nil
    }

    private let screenshotSession = ClickScreenshotSession()
    private let interactionRecorder = InteractionRecorder()
    private let apiKeyStore = APIKeyStore()
    private var recordingConfiguration: ModelAPIConfiguration?
    private var recordingTriggerPolicy: ScreenshotTriggerPolicy = .default
    private var pendingInputEvents: [InputTimelineEvent] = []
    private var pendingConfiguration: ModelAPIConfiguration?
    private var recordingInputMonitoringAvailable = false
    private var didRequestInputMonitoringAtLaunch = false
    private var apiKeyLoadGeneration = 0
    private var cachedAPIKeys: [String: String] = [:]

    init() {
        let storedProvider = UserDefaults.standard.string(forKey: "sopshot.model.provider")
            .flatMap(ModelProvider.init(rawValue:)) ?? .gemini
        let storedInputMode = UserDefaults.standard.string(forKey: "sopshot.model.inputMode")
            .flatMap(ModelInputMode.init(rawValue:))
        let initialInputMode = storedInputMode.flatMap { storedProvider.supportedInputModes.contains($0) ? $0 : nil }
            ?? storedProvider.defaultInputMode
        let providerModelKey = "sopshot.model.\(storedProvider.rawValue).name"
        let savedModel = UserDefaults.standard.string(forKey: providerModelKey)
            ?? UserDefaults.standard.string(forKey: "sopshot.model.name")
            ?? ""
        let initialModel = storedProvider == .customOpenAICompatible
            || storedProvider.presets.contains { $0.id == savedModel }
            ? savedModel
            : storedProvider.defaultModel
        modelProvider = storedProvider
        modelInputMode = initialInputMode
        modelName = initialModel
        screenshotTriggers = Self.loadScreenshotTriggers()
        captureOrbSize = UserDefaults.standard.string(forKey: Self.captureOrbSizeKey)
            .flatMap(CaptureOrbSize.init(rawValue:)) ?? .large
        let providerEndpointKey = "sopshot.model.\(storedProvider.rawValue).endpoint"
        modelEndpoint = UserDefaults.standard.string(forKey: providerEndpointKey)
            ?? (storedProvider == .customOpenAICompatible
                ? UserDefaults.standard.string(forKey: "sopshot.model.endpoint") ?? storedProvider.defaultEndpoint
                : storedProvider.defaultEndpoint)
        modelAPIKey = ""
        loadAPIKey(for: storedProvider)
        loadConfiguredModelOptions()
    }

    var selectedIndex: Int? {
        guard let selectedStepID else { return nil }
        return steps.firstIndex { $0.id == selectedStepID }
    }

    var selectedStep: SOPStep? {
        guard let selectedIndex else { return nil }
        return steps[selectedIndex]
    }

    var displayTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "未命名说明" : title
    }

    var modelConfiguration: ModelAPIConfiguration {
        ModelAPIConfiguration(
            provider: modelProvider,
            inputMode: modelInputMode,
            endpoint: modelEndpoint,
            model: modelName,
            apiKey: modelAPIKey
        )
    }

    var selectedModelPreset: ModelPreset? {
        modelProvider.presets.first { $0.id == modelName }
    }

    var selectedConfiguredModelID: String {
        ConfiguredModelOption.identifier(provider: modelProvider, modelID: modelName)
    }

    func requestInputMonitoringAccessIfNeeded() {
        guard !didRequestInputMonitoringAtLaunch else { return }
        didRequestInputMonitoringAtLaunch = true
        refreshInputMonitoringPermission(requestIfNeeded: true)
    }

    func refreshInputMonitoringPermission(requestIfNeeded: Bool = false) {
        let granted = requestIfNeeded
            ? interactionRecorder.requestListenPermission()
            : interactionRecorder.hasListenPermission()
        inputMonitoringAvailable = granted
        if requestIfNeeded && !granted {
            isInputMonitoringPermissionAlertPresented = true
        }
    }

    func openInputMonitoringSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ListenEvent"
        ]
        for address in urls {
            guard let url = URL(string: address), NSWorkspace.shared.open(url) else { continue }
            return
        }
    }

    func selectModelProvider(_ provider: ModelProvider) {
        guard modelProvider != provider else { return }
        modelProvider = provider
        modelInputMode = provider.defaultInputMode
        modelName = provider.defaultModel
        modelEndpoint = provider.defaultEndpoint
        modelAPIKey = ""
        loadAPIKey(for: provider)
        modelTestState = .idle
    }

    private func loadAPIKey(for provider: ModelProvider) {
        apiKeyLoadGeneration += 1
        let generation = apiKeyLoadGeneration
        isAPIKeyLoading = true
        let service = apiKeyStore
        let account = provider.rawValue
        let keyTask = Task.detached(priority: .userInitiated) {
            let value = (try? service.load(forAccount: account)) ?? ""
            return value
        }
        Task { @MainActor [weak self] in
            let value = await keyTask.value
            guard let self,
                  self.apiKeyLoadGeneration == generation,
                  self.modelProvider.rawValue == account else { return }
            self.modelAPIKey = value
            self.isAPIKeyLoading = false
            self.cachedAPIKeys[account] = value
            self.rebuildConfiguredModelOptions()
        }
    }

    private func loadConfiguredModelOptions() {
        let service = apiKeyStore
        let accounts = ModelProvider.allCases.map(\.rawValue)
        let keyTask = Task.detached(priority: .userInitiated) {
            var values: [String: String] = [:]
            for account in accounts {
                let value = (try? service.load(forAccount: account)) ?? ""
                if !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    values[account] = value
                }
            }
            return values
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            let values = await keyTask.value
            self.cachedAPIKeys = values
            if self.modelAPIKey.isEmpty,
               let currentKey = values[self.modelProvider.rawValue] {
                self.modelAPIKey = currentKey
                self.isAPIKeyLoading = false
            }
            self.rebuildConfiguredModelOptions()
        }
    }

    private func rebuildConfiguredModelOptions() {
        var options: [ConfiguredModelOption] = []

        for provider in ModelProvider.allCases {
            guard let key = cachedAPIKeys[provider.rawValue],
                  !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }

            if provider.presets.isEmpty {
                let customModel = provider == modelProvider ? modelName : storedModelName(for: provider)
                if !customModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    options.append(
                        ConfiguredModelOption(
                            provider: provider,
                            modelID: customModel,
                            modelLabel: customModel
                        )
                    )
                }
            } else {
                options.append(contentsOf: provider.presets.map { preset in
                    ConfiguredModelOption(
                        provider: provider,
                        modelID: preset.id,
                        modelLabel: preset.name
                    )
                })
            }
        }

        if modelConfiguration.isConfigured,
           !options.contains(where: { $0.id == selectedConfiguredModelID }) {
            options.append(
                ConfiguredModelOption(
                    provider: modelProvider,
                    modelID: modelName,
                    modelLabel: selectedModelPreset?.name ?? modelName
                )
            )
        }

        configuredModelOptions = options
    }

    private func storedModelName(for provider: ModelProvider) -> String {
        let providerKey = "sopshot.model.\(provider.rawValue).name"
        let stored = UserDefaults.standard.string(forKey: providerKey) ?? ""
        if provider == .customOpenAICompatible {
            return stored
        }
        return provider.presets.contains { $0.id == stored } ? stored : provider.defaultModel
    }

    func selectConfiguredModel(_ option: ConfiguredModelOption) {
        guard phase == .idle else { return }

        modelProvider = option.provider
        modelInputMode = option.provider.defaultInputMode
        modelName = option.modelID
        if option.provider == .customOpenAICompatible {
            let endpointKey = "sopshot.model.\(option.provider.rawValue).endpoint"
            modelEndpoint = UserDefaults.standard.string(forKey: endpointKey)
                ?? UserDefaults.standard.string(forKey: "sopshot.model.endpoint")
                ?? option.provider.defaultEndpoint
        } else {
            modelEndpoint = option.provider.defaultEndpoint
        }

        if let key = cachedAPIKeys[option.provider.rawValue] {
            modelAPIKey = key
            isAPIKeyLoading = false
        } else {
            modelAPIKey = ""
            loadAPIKey(for: option.provider)
        }

        UserDefaults.standard.set(option.provider.rawValue, forKey: "sopshot.model.provider")
        UserDefaults.standard.set(modelInputMode.rawValue, forKey: "sopshot.model.inputMode")
        UserDefaults.standard.set(modelName, forKey: "sopshot.model.name")
        UserDefaults.standard.set(modelName, forKey: "sopshot.model.\(option.provider.rawValue).name")
        UserDefaults.standard.set(modelEndpoint, forKey: "sopshot.model.endpoint")
        UserDefaults.standard.set(modelEndpoint, forKey: "sopshot.model.\(option.provider.rawValue).endpoint")
        modelTestState = .idle
        rebuildConfiguredModelOptions()
        noteGuidedTourEvent(.modelSelected)
    }

    func selectModelPreset(_ preset: ModelPreset) {
        modelName = preset.id
        modelTestState = .idle
    }

    func beginGuidedTour() {
        guidedTourStep = .openOrb
        isHelpPresented = true
        banner = nil
    }

    func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: "sopshot.onboarding.completed")
        isHelpPresented = false
        guidedTourStep = nil
    }

    func dismissOnboarding() {
        isHelpPresented = false
        guidedTourStep = nil
    }

    func noteGuidedTourEvent(_ event: GuidedTourEvent) {
        guard let step = guidedTourStep else { return }
        let next: GuidedTourStep?
        switch (step, event) {
        case (.openOrb, .orbMenuOpened):
            next = .pickModel
        case (.openOrb, .modelSelected), (.openOrb, .modelSettingsSaved),
             (.pickModel, .modelSelected), (.pickModel, .modelSettingsSaved):
            next = .startCapture
        case (.openOrb, .captureStarted), (.pickModel, .captureStarted), (.startCapture, .captureStarted):
            next = .stopCapture
        case (.stopCapture, .captureStopped):
            next = .deleteScreenshot
        case (.deleteScreenshot, .previewFrameDeleted):
            next = .generate
        case (.generate, .generateFinished):
            next = .exportMarkdown
        case (.exportMarkdown, .exported):
            next = .finished
        default:
            next = nil
        }
        guard let next else { return }
        guidedTourStep = next
        if next == .finished {
            completeOnboarding()
            banner = SOPBanner(text: "引导完成。之后可以从悬浮球直接开始截图。", tone: .success)
        }
    }

    func selectModelInputMode(_ mode: ModelInputMode) {
        guard modelProvider.supportedInputModes.contains(mode) else { return }
        modelInputMode = mode
        modelTestState = .idle
    }

    func saveModelSettings() {
        let cleanProvider = modelProvider
        let cleanModel = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanEndpoint = modelEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanAPIKey = modelAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        modelName = cleanModel
        modelEndpoint = cleanEndpoint
        modelAPIKey = cleanAPIKey

        if cleanAPIKey.isEmpty && isAPIKeyLoading {
            modelTestState = .failure("正在读取本机 API Key，请稍等片刻后再保存。")
            banner = SOPBanner(text: "API Key 仍在读取，本次没有修改已保存的 Key。", tone: .warning)
            return
        }

        apiKeyLoadGeneration += 1
        isAPIKeyLoading = false

        do {
            try apiKeyStore.save(cleanAPIKey, for: cleanProvider)
        } catch {
            modelTestState = .failure("API Key 保存失败，请检查本机应用配置权限后重试。")
            banner = SOPBanner(text: "API Key 保存失败，设置没有关闭。", tone: .error)
            return
        }

        UserDefaults.standard.set(cleanProvider.rawValue, forKey: "sopshot.model.provider")
        UserDefaults.standard.set(modelInputMode.rawValue, forKey: "sopshot.model.inputMode")
        UserDefaults.standard.set(cleanModel, forKey: "sopshot.model.name")
        UserDefaults.standard.set(cleanEndpoint, forKey: "sopshot.model.endpoint")
        UserDefaults.standard.set(cleanModel, forKey: "sopshot.model.\(cleanProvider.rawValue).name")
        UserDefaults.standard.set(cleanEndpoint, forKey: "sopshot.model.\(cleanProvider.rawValue).endpoint")
        cachedAPIKeys[cleanProvider.rawValue] = cleanAPIKey
        rebuildConfiguredModelOptions()
        if phase == .preview {
            pendingConfiguration = modelConfiguration
            previewInputMode = modelInputMode
            previewModelLabel = modelConfiguration.displayName
        }
        isModelSettingsPresented = false
        modelTestState = .idle
        if modelConfiguration.isConfigured {
            banner = nil
            noteGuidedTourEvent(.modelSettingsSaved)
        } else {
            banner = SOPBanner(text: "模型设置已保存，开始截图前还需要填写 API Key。", tone: .warning)
        }

    }

    func saveCaptureSettings() {
        guard screenshotTriggers.hasAnyTriggerEnabled else {
            banner = SOPBanner(text: "请至少打开一种截图触发操作。", tone: .warning)
            return
        }
        Self.persistScreenshotTriggers(screenshotTriggers)
        isCaptureSettingsPresented = false
        banner = nil
    }

    func setScreenshotTrigger(_ kind: InputEventKind, enabled: Bool) {
        guard InputEventKind.configurableScreenshotTriggers.contains(kind) else { return }
        var updated = screenshotTriggers
        updated.setEnabled(kind, enabled)
        screenshotTriggers = updated
    }

    private static let screenshotTriggersKey = "sopshot.capture.triggers"
    private static let captureOrbSizeKey = "sopshot.capture.orbSize"

    private static func loadScreenshotTriggers() -> ScreenshotTriggerPolicy {
        guard let data = UserDefaults.standard.data(forKey: screenshotTriggersKey),
              let decoded = try? JSONDecoder().decode(ScreenshotTriggerPolicy.self, from: data) else {
            return .default
        }
        return decoded
    }

    private static func persistScreenshotTriggers(_ policy: ScreenshotTriggerPolicy) {
        guard let data = try? JSONEncoder().encode(policy) else { return }
        UserDefaults.standard.set(data, forKey: screenshotTriggersKey)
    }

    func testModelAPI() {
        guard phase == .idle else { return }
        modelTestState = .testing
        let configuration = modelConfiguration
        Task { [weak self] in
            guard let self else { return }
            do {
                let message = try await ModelAPIClient.test(configuration: configuration)
                modelTestState = .success(message)
            } catch {
                modelTestState = .failure(error.localizedDescription)
            }
        }
    }

    func toggleRecording() {
        switch phase {
        case .idle:
            startRecording()
        case .recording:
            stopRecording()
        case .preparing, .extracting, .preview, .processing:
            break
        }
    }

    func startRecording() {
        guard phase == .idle else { return }

        if isGuidedTourActive {
            startGuidedTourRecording()
            return
        }

        guard modelConfiguration.isConfigured else {
            isModelSettingsPresented = true
            banner = SOPBanner(text: "开始前请先在“模型设置”中选择图像模型并填写 API Key。", tone: .warning)
            return
        }
        guard screenshotTriggers.hasAnyTriggerEnabled else {
            isCaptureSettingsPresented = true
            banner = SOPBanner(text: "请先在“截图设置”里至少打开一种截图触发操作。", tone: .warning)
            return
        }
        isDebugSession = false
        title = ""
        audience = ""
        summary = ""
        aiEngineLabel = ""
        steps = []
        selectedStepID = nil
        isEditing = false
        clearPendingCapture()
        queuedScreenshotCount = 0
        let configuration = modelConfiguration
        let triggerPolicy = screenshotTriggers
        recordingConfiguration = configuration
        recordingTriggerPolicy = triggerPolicy
        phase = .preparing
        banner = SOPBanner(text: "正在准备截图。完成后会先预览，再发送给 \(configuration.displayName)。", tone: .info)

        Task { [weak self] in
            guard let self else { return }
            do {
                screenshotSession.triggerPolicy = triggerPolicy
                interactionRecorder.triggerPolicy = triggerPolicy
                screenshotSession.onQueuedCountChanged = { [weak self] count in
                    self?.queuedScreenshotCount = count
                }
                interactionRecorder.onCaptureEvent = { [weak self] event in
                    self?.screenshotSession.enqueueCaptureEvent(event)
                }
                try await screenshotSession.start()
                let hasInputPermission = interactionRecorder.start()
                recordingInputMonitoringAvailable = hasInputPermission
                inputMonitoringAvailable = hasInputPermission
                if !hasInputPermission {
                    isInputMonitoringPermissionAlertPresented = true
                }
                phase = .recording
                recordingStartedAt = Date()
                banner = SOPBanner(
                    text: hasInputPermission
                        ? "正在按操作截图。已启用：\(triggerPolicy.enabledSummary)。完成后点击左上角圆球结束。"
                        : "正在等待截图。当前未开启输入监控，无法识别鼠标和键盘操作；请先打开权限。",
                    tone: hasInputPermission ? .info : .warning
                )
            } catch {
                _ = interactionRecorder.finish()
                _ = await screenshotSession.finish()
                screenshotSession.onQueuedCountChanged = nil
                queuedScreenshotCount = 0
                recordingInputMonitoringAvailable = false
                inputMonitoringAvailable = false
                phase = .idle
                recordingStartedAt = nil
                banner = SOPBanner(text: error.localizedDescription, tone: .error)
            }
        }
    }

    private func startGuidedTourRecording() {
        isDebugSession = false
        title = ""
        audience = ""
        summary = ""
        aiEngineLabel = ""
        steps = []
        selectedStepID = nil
        isEditing = false
        clearPendingCapture()
        let demo = DebugFixtureFactory.previewSession()
        queuedScreenshotCount = demo.frames.count
        let configuration: ModelAPIConfiguration
        if modelConfiguration.isConfigured {
            configuration = modelConfiguration
        } else {
            configuration = ModelAPIConfiguration(
                provider: .deepSeek,
                inputMode: .images,
                endpoint: ModelProvider.deepSeek.defaultEndpoint,
                model: ModelProvider.deepSeek.defaultModel,
                apiKey: "guided-tour-mock"
            )
        }
        recordingConfiguration = configuration
        recordingTriggerPolicy = screenshotTriggers
        recordingInputMonitoringAvailable = true
        inputMonitoringAvailable = true
        recordingStartedAt = Date()
        phase = .recording
        banner = SOPBanner(
            text: "引导演练中：使用演示截图。点击悬浮球结束截图。",
            tone: .info
        )
        noteGuidedTourEvent(.captureStarted)
    }

    func stopRecording() {
        guard phase == .recording else { return }
        if isDebugSession {
            jumpToDebug(.preview)
            return
        }
        if isGuidedTourActive {
            stopGuidedTourRecording()
            return
        }
        phase = .extracting
        banner = SOPBanner(text: "截图已停止，正在整理本机截图。此时还不会调用模型。", tone: .info)
        let configuration = recordingConfiguration ?? modelConfiguration

        Task { [weak self] in
            guard let self else { return }
            do {
                let inputEvents = interactionRecorder.finish()
                let frames = await screenshotSession.finish()
                screenshotSession.onQueuedCountChanged = nil
                queuedScreenshotCount = frames.count
                let captureEventCount = inputEvents.filter {
                    self.recordingTriggerPolicy.producesScreenshot(for: $0.kind)
                }.count
                guard captureEventCount > 0 else { throw CaptureError.emptyCapture }
                guard !frames.isEmpty else {
                    throw CaptureError.screenshotFailed(expected: captureEventCount, captured: 0)
                }

                pendingInputEvents = inputEvents
                pendingConfiguration = configuration
                previewFrames = frames
                previewInputMode = configuration.inputMode
                previewModelLabel = configuration.displayName
                previewInputMonitoringAvailable = recordingInputMonitoringAvailable
                recordingStartedAt = nil
                banner = SOPBanner(
                    text: "已按鼠标点击、拖拽、滚动和关键按键保存 \(frames.count) 张截图，请检查后生成说明。",
                    tone: .info
                )
                recordingConfiguration = nil
                phase = .preview
            } catch {
                screenshotSession.onQueuedCountChanged = nil
                queuedScreenshotCount = 0
                phase = .idle
                recordingStartedAt = nil
                recordingConfiguration = nil
                if let captureError = error as? CaptureError, case .emptyCapture = captureError {
                    banner = nil
                } else {
                    banner = SOPBanner(text: error.localizedDescription, tone: .error)
                }
            }
        }
    }

    private func stopGuidedTourRecording() {
        phase = .extracting
        banner = SOPBanner(text: "引导演练：正在载入演示截图。", tone: .info)
        let configuration = recordingConfiguration ?? modelConfiguration
        seedPreviewDemo(keepPending: true)
        if modelConfiguration.isConfigured {
            pendingConfiguration = modelConfiguration
            previewModelLabel = modelConfiguration.displayName
            previewInputMode = modelConfiguration.inputMode
        } else {
            pendingConfiguration = configuration
        }
        recordingStartedAt = nil
        recordingConfiguration = nil
        queuedScreenshotCount = previewFrames.count
        banner = SOPBanner(
            text: "已载入 \(previewFrames.count) 张演示截图，请检查后生成说明。",
            tone: .info
        )
        phase = .preview
        noteGuidedTourEvent(.captureStopped)
    }

    func startAIProcessing() {
        guard phase == .preview,
              let configuration = pendingConfiguration,
              !previewFrames.isEmpty else {
            banner = SOPBanner(text: "当前没有可发送的截图，请重新采集。", tone: .warning)
            return
        }

        if isDebugSession {
            jumpToDebug(.result)
            return
        }

        if isGuidedTourActive {
            startGuidedTourProcessing()
            return
        }

        let currentConfiguration = modelConfiguration.isConfigured ? modelConfiguration : configuration
        pendingConfiguration = currentConfiguration
        previewInputMode = currentConfiguration.inputMode
        previewModelLabel = currentConfiguration.displayName
        phase = .processing
        banner = SOPBanner(text: "已确认截图，正在发送给 \(currentConfiguration.displayName)。", tone: .info)
        let inputEvents = pendingInputEvents
        let sampledFrames = previewFrames
        let userNote = previewUserNote

        Task { [weak self] in
            guard let self else { return }
            do {
                let draft = try await ModelAPIClient.analyze(
                    frames: sampledFrames,
                    configuration: currentConfiguration,
                    inputEvents: inputEvents,
                    userNote: userNote,
                    triggerPolicy: recordingTriggerPolicy
                )
                let frames = sampledFrames
                let capturedSteps = try makeSteps(from: draft, frames: frames)
                title = draft.title
                audience = draft.audience
                summary = draft.summary
                aiEngineLabel = draft.engineLabel
                steps = capturedSteps
                selectedStepID = capturedSteps.first?.id
                isEditing = false
                clearPendingCapture()
                phase = .idle
                banner = SOPBanner(
                    text: "已根据这组截图生成 \(capturedSteps.count) 个步骤，当前显示最终预览。",
                    tone: .success
                )
            } catch {
                phase = .preview
                banner = SOPBanner(text: "生成说明失败，截图仍然保留。检查设置后重试。\n\(error.localizedDescription)", tone: .error)
            }
        }
    }

    private func startGuidedTourProcessing() {
        let label = pendingConfiguration?.displayName
            ?? (modelConfiguration.isConfigured ? modelConfiguration.displayName : "演示模型")
        phase = .processing
        banner = SOPBanner(text: "引导演练：正在用演示数据生成说明（不会访问网络）。", tone: .info)
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard let self, self.isGuidedTourActive, self.phase == .processing else { return }
            self.loadDemo()
            self.aiEngineLabel = "引导演示 · \(label)"
            self.clearPendingCapture()
            self.phase = .idle
            self.banner = SOPBanner(
                text: "已生成演示说明。接下来导出 Markdown 完成引导。",
                tone: .success
            )
            self.noteGuidedTourEvent(.generateFinished)
        }
    }

    func restartFromPreview() {
        guard phase == .preview else { return }
        pendingConfirmation = .restartPreview
    }

    func requestClosePreview() {
        guard phase == .preview else { return }
        pendingConfirmation = .closePreview
    }

    func deleteSelected() {
        guard selectedIndex != nil else { return }
        pendingConfirmation = .deleteStep
    }

    func clearDraft() {
        guard !steps.isEmpty || !title.isEmpty || !audience.isEmpty else {
            banner = SOPBanner(text: "当前草稿已经是空的。", tone: .info)
            return
        }
        pendingConfirmation = .clearDraft
    }

    func requestLoadDemo() {
        if steps.isEmpty && title.isEmpty && audience.isEmpty {
            loadDemo()
            return
        }
        pendingConfirmation = .loadDemo
    }

    func confirmPendingAction() {
        guard let pendingConfirmation else { return }
        self.pendingConfirmation = nil
        switch pendingConfirmation {
        case .restartPreview:
            performRestartFromPreview()
        case .closePreview:
            discardPreviewAndReturnToOrb()
        case .deleteStep:
            performDeleteSelected()
        case .clearDraft:
            performClearDraft()
        case .loadDemo:
            loadDemo()
        }
    }

    func cancelPendingConfirmation() {
        pendingConfirmation = nil
    }

    private func performRestartFromPreview() {
        guard phase == .preview else { return }
        if isDebugSession {
            jumpToDebug(.recording)
            return
        }
        clearPendingCapture()
        phase = .idle
        banner = nil
        startRecording()
    }

    private func discardPreviewAndReturnToOrb() {
        guard phase == .preview else { return }
        clearDraftSilently()
        recordingConfiguration = nil
        recordingStartedAt = nil
        isEditing = false
        isDebugSession = false
        isHelpPresented = false
        phase = .idle
        banner = nil
    }

    private func performDeleteSelected() {
        guard let selectedIndex else { return }
        steps.remove(at: selectedIndex)
        self.selectedStepID = steps.indices.contains(selectedIndex) ? steps[selectedIndex].id : steps.last?.id
        if steps.isEmpty {
            isEditing = false
        }
    }

    private func performClearDraft() {
        title = ""
        audience = ""
        summary = ""
        aiEngineLabel = ""
        steps = []
        selectedStepID = nil
        isEditing = false
        banner = nil
    }

    private func clearPendingCapture() {
        pendingInputEvents = []
        pendingConfiguration = nil
        previewFrames = []
        previewUserNote = ""
        previewInputMode = nil
        previewModelLabel = ""
        previewInputMonitoringAvailable = false
        queuedScreenshotCount = 0
    }

    func deletePreviewFrame(at index: Int) {
        guard previewFrames.indices.contains(index) else { return }

        let deletedFrame = previewFrames.remove(at: index)
        if let primaryInputEventID = deletedFrame.primaryInputEvent?.id,
           let eventIndex = pendingInputEvents.firstIndex(where: { $0.id == primaryInputEventID }) {
            pendingInputEvents.remove(at: eventIndex)
        } else if let eventIndex = pendingInputEvents.indices
            .filter({ recordingTriggerPolicy.producesScreenshot(for: pendingInputEvents[$0].kind) })
            .min(by: {
                abs(pendingInputEvents[$0].timestamp - deletedFrame.timestamp)
                    < abs(pendingInputEvents[$1].timestamp - deletedFrame.timestamp)
            }) {
            pendingInputEvents.remove(at: eventIndex)
        }

        banner = SOPBanner(
            text: previewFrames.isEmpty
                ? "已删除最后一张截图，请重新采集。"
                : "已删除第 \(index + 1) 张截图，剩余 \(previewFrames.count) 张。",
            tone: .info
        )
        if !previewFrames.isEmpty {
            noteGuidedTourEvent(.previewFrameDeleted)
        }
    }

    func previewInputEvents(for frame: CapturedFrame, radius: TimeInterval = 0.7) -> [InputTimelineEvent] {
        let nearbyEvents = nearbyPreviewEvents(around: frame.timestamp, radius: radius)
        if let primaryInputEventID = frame.primaryInputEvent?.id {
            if let primaryEvent = nearbyEvents.first(where: { $0.id == primaryInputEventID }) {
                return [primaryEvent]
            }
        }
        return eventsWithSinglePrimaryCaptureEvent(nearbyEvents, timestamp: frame.timestamp)
    }

    func previewInputEvents(around timestamp: TimeInterval, radius: TimeInterval = 0.7) -> [InputTimelineEvent] {
        eventsWithSinglePrimaryCaptureEvent(
            nearbyPreviewEvents(around: timestamp, radius: radius),
            timestamp: timestamp
        )
    }

    private func nearbyPreviewEvents(around timestamp: TimeInterval, radius: TimeInterval) -> [InputTimelineEvent] {
        pendingInputEvents
            .filter { abs($0.timestamp - timestamp) <= radius }
            .sorted { $0.timestamp < $1.timestamp }
    }

    private func eventsWithSinglePrimaryCaptureEvent(
        _ events: [InputTimelineEvent],
        timestamp: TimeInterval
    ) -> [InputTimelineEvent] {
        guard let primaryCaptureIndex = events.indices
            .filter({ recordingTriggerPolicy.producesScreenshot(for: events[$0].kind) })
            .min(by: { lhs, rhs in
                let leftDistance = abs(events[lhs].timestamp - timestamp)
                let rightDistance = abs(events[rhs].timestamp - timestamp)
                if leftDistance == rightDistance {
                    return events[lhs].timestamp > events[rhs].timestamp
                }
                return leftDistance < rightDistance
            }) else {
            return events
        }

        return [events[primaryCaptureIndex]]
    }

    func selectStep(_ step: SOPStep) {
        selectedStepID = step.id
    }

    func updateSelected(_ keyPath: WritableKeyPath<SOPStep, String>, value: String) {
        guard let selectedIndex else { return }
        steps[selectedIndex][keyPath: keyPath] = value
        objectWillChange.send()
    }

    func moveSelected(by offset: Int) {
        guard let selectedIndex else { return }
        let targetIndex = selectedIndex + offset
        guard steps.indices.contains(targetIndex) else { return }
        steps.swapAt(selectedIndex, targetIndex)
    }

    func composeSelected() {
        guard let selectedIndex else { return }
        let note = steps[selectedIndex].note
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "。！？!?"))
        guard !note.isEmpty else {
            banner = SOPBanner(text: "先写一句这一步要完成什么，再整理成短句。", tone: .warning)
            return
        }
        steps[selectedIndex].note = note.hasSuffix("。") ? note : "\(note)。"
        if steps[selectedIndex].title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            steps[selectedIndex].title = note.count > 18 ? String(note.prefix(18)) + "…" : note
        }
            banner = SOPBanner(text: "当前步骤已更新。", tone: .success)
    }

    func loadDemo() {
        title = "如何提交一张报销单"
        audience = "需要提交报销的同事"
        summary = "完成一次报销单提交，方便新同事按画面完成操作。"
        aiEngineLabel = "演示内容"
        steps = DemoImageFactory.steps()
        selectedStepID = steps.first?.id
        isEditing = false
        banner = SOPBanner(text: "已载入演示草稿。演示内容只用于体验排版和编辑流程。", tone: .success)
    }

    func jumpToDebug(_ destination: DebugDestination) {
        abandonLiveCaptureIfNeeded()
        isDebugSession = destination.keepsDebugSession
        isDebugAssistantPresented = false
        isModelSettingsPresented = false
        isCaptureSettingsPresented = false
        isHelpPresented = false
        guidedTourStep = nil
        isEditing = false
        banner = nil

        switch destination {
        case .emptyStart:
            clearDraftSilently()
            phase = .idle
            queuedScreenshotCount = 0

        case .preparing:
            clearDraftSilently()
            phase = .preparing
            queuedScreenshotCount = 0

        case .recording:
            clearDraftSilently()
            phase = .recording
            recordingStartedAt = Date()
            queuedScreenshotCount = 7

        case .extracting:
            clearDraftSilently()
            phase = .extracting
            queuedScreenshotCount = 7

        case .processing:
            seedPreviewDemo(keepPending: true)
            phase = .processing
            queuedScreenshotCount = previewFrames.count

        case .preview:
            seedPreviewDemo(keepPending: true)
            phase = .preview
            queuedScreenshotCount = previewFrames.count

        case .result:
            clearPendingCapture()
            loadDemo()
            phase = .idle
            isEditing = false
            banner = nil

        case .editor:
            clearPendingCapture()
            loadDemo()
            phase = .idle
            isEditing = true
            banner = nil

        case .modelSettings:
            phase = .idle
            if steps.isEmpty {
                clearDraftSilently()
            }
            isModelSettingsPresented = true

        case .captureSettings:
            phase = .idle
            if steps.isEmpty {
                clearDraftSilently()
            }
            isCaptureSettingsPresented = true
        }
    }

    private func abandonLiveCaptureIfNeeded() {
        guard !isDebugSession else {
            interactionRecorder.onCaptureEvent = nil
            screenshotSession.onQueuedCountChanged = nil
            return
        }
        switch phase {
        case .preparing, .recording, .extracting, .processing:
            _ = interactionRecorder.finish()
            Task { @MainActor [weak self] in
                _ = await self?.screenshotSession.finish()
            }
            interactionRecorder.onCaptureEvent = nil
            screenshotSession.onQueuedCountChanged = nil
            recordingConfiguration = nil
            recordingStartedAt = nil
        case .idle, .preview:
            break
        }
    }

    private func clearDraftSilently() {
        title = ""
        audience = ""
        summary = ""
        aiEngineLabel = ""
        steps = []
        selectedStepID = nil
        clearPendingCapture()
    }

    private func seedPreviewDemo(keepPending: Bool) {
        let demo = DebugFixtureFactory.previewSession()
        clearDraftSilently()
        previewFrames = demo.frames
        pendingInputEvents = demo.events
        previewInputMode = .images
        previewModelLabel = modelConfiguration.isConfigured
            ? modelConfiguration.displayName
            : "DeepSeek · deepseek-flash"
        previewInputMonitoringAvailable = true
        if keepPending {
            pendingConfiguration = modelConfiguration.isConfigured
                ? modelConfiguration
                : ModelAPIConfiguration(
                    provider: .deepSeek,
                    inputMode: .images,
                    endpoint: ModelProvider.deepSeek.defaultEndpoint,
                    model: ModelProvider.deepSeek.defaultModel,
                    apiKey: "debug-preview-key"
                )
        }
    }

    private func makeSteps(
        from draft: AIProcedureDraft,
        frames: [CapturedFrame]
    ) throws -> [SOPStep] {
        let steps = draft.steps.enumerated().compactMap { index, generated -> SOPStep? in
            let frame: CapturedFrame
            if let frameIndex = generated.frameIndex, frames.indices.contains(frameIndex - 1) {
                frame = frames[frameIndex - 1]
            } else if frames.indices.contains(index) {
                frame = frames[index]
            } else {
                return nil
            }
            let timestamp = " · \(String(format: "%.1f", generated.timestamp)) 秒"
            return SOPStep(
                title: generated.title,
                note: generated.note,
                tip: generated.tip,
                image: frame.image,
                sourceName: "操作截图 \(String(format: "%02d", index + 1))\(timestamp)"
            )
        }
        guard !steps.isEmpty else { throw CaptureError.emptyCapture }
        return steps
    }

    func exportHTML() {
        guard !steps.isEmpty else {
            banner = SOPBanner(text: "先采集一遍电脑操作，再导出说明。", tone: .warning)
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.html]
        panel.nameFieldStringValue = safeFileName(displayTitle) + ".html"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try ExportService.html(title: displayTitle, audience: audience, steps: steps).write(to: url, atomically: true, encoding: .utf8)
            banner = SOPBanner(text: "HTML 已导出。", tone: .success)
            noteGuidedTourEvent(.exported)
        } catch {
            banner = SOPBanner(text: "HTML 导出失败：\(error.localizedDescription)", tone: .error)
        }
    }

    func exportMarkdown() {
        guard !steps.isEmpty else {
            banner = SOPBanner(text: "先采集一遍电脑操作，再导出说明。", tone: .warning)
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = safeFileName(displayTitle) + ".md"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try ExportService.markdown(title: displayTitle, audience: audience, steps: steps).write(to: url, atomically: true, encoding: .utf8)
            banner = SOPBanner(text: "Markdown 已导出。", tone: .success)
            noteGuidedTourEvent(.exported)
        } catch {
            banner = SOPBanner(text: "Markdown 导出失败：\(error.localizedDescription)", tone: .error)
        }
    }

    private func safeFileName(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " _-"))
        let name = value.unicodeScalars.map { allowed.contains($0) ? Character($0) : " " }
        let normalized = String(name).trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? "sopshot-draft" : normalized
    }
}

enum CaptureError: LocalizedError {
    case unsupported
    case permissionDenied
    case contentUnavailable(String)
    case captureStartFailed(String)
    case emptyCapture
    case screenshotFailed(expected: Int, captured: Int)

    var errorDescription: String? {
        switch self {
        case .unsupported:
            return "当前 macOS 版本不支持屏幕截图采集。"
        case .permissionDenied:
            return "macOS 的屏幕录制授权没有匹配当前这份 SOPShot。请在系统设置的“隐私与安全性 > 录屏与系统录音”中允许当前应用，然后完全退出并重新打开。"
        case .contentUnavailable(let reason):
            return "macOS 已授予屏幕录制权限，但读取屏幕内容失败：\(reason)"
        case .captureStartFailed(let reason):
            return "macOS 已授予屏幕录制权限，但启动截图采集失败：\(reason)"
        case .emptyCapture:
            return "这次没有捕获到可截图的鼠标或键盘操作，请确认输入监控权限已打开后再试。"
        case .screenshotFailed(let expected, let captured):
            return "操作截图没有完整保存，应该有 \(expected) 张，实际得到 \(captured) 张，请重试。"
        }
    }
}

enum ExportService {
    static func imageData(_ image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.82])
    }

    static func html(title: String, audience: String, steps: [SOPStep]) -> String {
        let renderedSteps = steps.enumerated().map { index, step in
            let data = imageData(step.image)?.base64EncodedString() ?? ""
            let note = step.note.isEmpty ? "" : "<p>\(escape(step.note))</p>"
            let tip = step.tip.isEmpty ? "" : "<p class=\"tip\">提醒：\(escape(step.tip))</p>"
            return """
            <section class="step">
              <div class="image-wrap"><img src="data:image/jpeg;base64,\(data)" alt="\(escape(step.title.isEmpty ? "步骤截图" : step.title)) 的截图"><span>\(String(format: "%02d", index + 1))</span></div>
              <div class="copy"><h2>\(escape(step.title.isEmpty ? "未命名步骤" : step.title))</h2>\(note)\(tip)</div>
            </section>
            """
        }.joined(separator: "\n")
        let audienceLine = audience.isEmpty ? "" : "<p class=\"audience\">适用对象：\(escape(audience))</p>"
        return """
        <!doctype html>
        <html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>\(escape(title))</title>
        <style>:root{font-family:-apple-system,BlinkMacSystemFont,"PingFang SC","Microsoft YaHei",sans-serif;color:#202728;background:#e9e4d9}body{margin:0;padding:40px 20px}main{width:min(760px,100%);margin:0 auto;padding:42px 48px 30px;background:#fffdf7;box-shadow:0 12px 28px rgba(45,40,30,.12)}.kicker{color:#5f6b67;font-size:12px;letter-spacing:.05em}h1{margin:24px 0 8px;font-size:34px;letter-spacing:-.05em}.audience{color:#53605e;font-size:13px}.step{display:grid;grid-template-columns:1fr minmax(180px,.9fr);gap:18px;padding:0 0 18px;margin-bottom:18px;border-bottom:1px solid #d2cdc0}.image-wrap{position:relative;border:1px solid #d2cdc0;background:#eee9de}.image-wrap img{display:block;width:100%;max-height:300px;object-fit:cover}.image-wrap span{position:absolute;top:10px;left:10px;padding:5px 7px;border:1px solid #202728;background:#fffdf7;font:11px monospace}.copy h2{font-size:17px}.copy p{color:#53605e;font-size:14px;line-height:1.65;white-space:pre-wrap}.tip{padding:10px 11px;border-left:2px solid #b84f2c;background:#f4d8ca;color:#9f4022!important;font-size:12px!important}@media(max-width:640px){body{padding:16px 8px}main{padding:26px 20px}.step{grid-template-columns:1fr}h1{font-size:28px}}</style></head>
        <body><main><div class="kicker">操作说明 · 本地导出</div><h1>\(escape(title))</h1>\(audienceLine)\(renderedSteps)<footer>由 SOPShot 原生应用生成。文件内含截图，可离线打开。</footer></main></body></html>
        """
    }

    static func markdown(title: String, audience: String, steps: [SOPStep]) -> String {
        var lines = ["# \(title)", "", "> 本地导出，可离线打开。", ""]
        if !audience.isEmpty { lines.append(contentsOf: ["适用对象：\(audience)", ""]) }
        for (index, step) in steps.enumerated() {
            let data = imageData(step.image)?.base64EncodedString() ?? ""
            lines.append(contentsOf: ["## \(String(format: "%02d", index + 1)) \(step.title.isEmpty ? "未命名步骤" : step.title)", "", "![步骤截图](data:image/jpeg;base64,\(data))", ""])
            if !step.note.isEmpty { lines.append(contentsOf: [step.note, ""]) }
            if !step.tip.isEmpty { lines.append(contentsOf: ["> 提醒：\(step.tip)", ""]) }
        }
        lines.append(contentsOf: ["---", "", "由 SOPShot 原生应用生成。图片以内嵌数据保存。"])
        return lines.joined(separator: "\n")
    }

    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

enum DemoImageFactory {
    static func steps() -> [SOPStep] {
        [
            SOPStep(title: "进入费用管理", note: "在左侧菜单打开费用管理。", tip: "先确认已经登录办公系统。", image: image(stage: "费用管理", detail: "选择要办理的事项", focus: "新建报销单"), sourceName: "演示画面 01"),
            SOPStep(title: "选择报销类型", note: "点击新建报销单，在报销类型中选择差旅报销。", tip: "类型选错时，后面的字段也会跟着变化。", image: image(stage: "新建报销单", detail: "填写报销基本信息", focus: "差旅报销"), sourceName: "演示画面 02"),
            SOPStep(title: "填写金额并上传发票", note: "填写报销金额，上传发票和其他需要的资料。", tip: "提交前检查附件是否已经显示在列表里。", image: image(stage: "新建报销单", detail: "补充金额并上传资料", focus: "上传发票"), sourceName: "演示画面 03"),
            SOPStep(title: "提交审批", note: "确认金额、附件和收款信息后，点击提交审批。", tip: "提交后可以在审批进度里查看状态。", image: image(stage: "提交前检查", detail: "确认信息后送出审批", focus: "提交审批"), sourceName: "演示画面 04")
        ]
    }

    private static func image(stage: String, detail: String, focus: String) -> NSImage {
        let image = NSImage(size: NSSize(width: 720, height: 430))
        image.lockFocus()
        NSColor(calibratedRed: 0.94, green: 0.93, blue: 0.89, alpha: 1).setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 720, height: 430)).fill()
        let window = NSRect(x: 26, y: 24, width: 668, height: 382)
        NSColor(calibratedRed: 1, green: 0.99, blue: 0.97, alpha: 1).setFill()
        NSBezierPath(roundedRect: window, xRadius: 8, yRadius: 8).fill()
        NSColor(calibratedRed: 0.15, green: 0.19, blue: 0.18, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 26, y: 364, width: 668, height: 42), xRadius: 8, yRadius: 8).fill()
        NSColor(calibratedRed: 0.86, green: 0.48, blue: 0.32, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: 44, y: 381, width: 10, height: 10)).fill()
        NSColor(calibratedRed: 0.90, green: 0.88, blue: 0.82, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: 62, y: 381, width: 10, height: 10)).fill()
        NSBezierPath(ovalIn: NSRect(x: 80, y: 381, width: 10, height: 10)).fill()
        NSColor(calibratedRed: 0.95, green: 0.93, blue: 0.89, alpha: 1).setFill()
        NSBezierPath(rect: NSRect(x: 48, y: 52, width: 144, height: 286)).fill()
        drawText("\(stage)", at: NSPoint(x: 222, y: 278), size: 22, weight: .bold, color: NSColor(calibratedRed: 0.15, green: 0.19, blue: 0.18, alpha: 1))
        drawText(detail, at: NSPoint(x: 222, y: 252), size: 13, weight: .regular, color: NSColor(calibratedRed: 0.37, green: 0.42, blue: 0.40, alpha: 1))
        NSColor(calibratedRed: 0.97, green: 0.96, blue: 0.92, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 222, y: 194, width: 406, height: 56), xRadius: 6, yRadius: 6).fill()
        NSColor(calibratedRed: 0.82, green: 0.79, blue: 0.72, alpha: 1).setStroke()
        NSBezierPath(roundedRect: NSRect(x: 222, y: 194, width: 406, height: 56), xRadius: 6, yRadius: 6).stroke()
        drawText(focus, at: NSPoint(x: 244, y: 210), size: 15, weight: .semibold, color: NSColor(calibratedRed: 0.15, green: 0.19, blue: 0.18, alpha: 1))
        for (index, label) in ["报销金额", "附件资料", "备注"].enumerated() {
            let x = index == 0 ? 222 : 434
            let y = index == 0 ? 138 : 138
            NSColor(calibratedRed: 0.97, green: 0.96, blue: 0.92, alpha: 1).setFill()
            NSBezierPath(roundedRect: NSRect(x: x, y: y, width: index == 0 ? 194 : 194, height: 56), xRadius: 6, yRadius: 6).fill()
            drawText(label, at: NSPoint(x: x + 22, y: y + 23), size: 12, weight: .regular, color: NSColor(calibratedRed: 0.37, green: 0.42, blue: 0.40, alpha: 1))
        }
        NSColor(calibratedRed: 0.18, green: 0.41, blue: 0.40, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 222, y: 72, width: 124, height: 30), xRadius: 5, yRadius: 5).fill()
        drawText("继续", at: NSPoint(x: 249, y: 82), size: 12, weight: .bold, color: .white)
        image.unlockFocus()
        return image
    }

    private static func drawText(_ text: String, at point: NSPoint, size: CGFloat, weight: NSFont.Weight, color: NSColor) {
        let font = NSFont.systemFont(ofSize: size, weight: weight)
        text.draw(at: point, withAttributes: [.font: font, .foregroundColor: color])
    }
}

enum DebugFixtureFactory {
    struct PreviewSession {
        let frames: [CapturedFrame]
        let events: [InputTimelineEvent]
    }

    static func previewSession() -> PreviewSession {
        let demoSteps = DemoImageFactory.steps()
        let clickPoints: [CGPoint] = [
            CGPoint(x: 0.22, y: 0.48),
            CGPoint(x: 0.58, y: 0.52),
            CGPoint(x: 0.36, y: 0.61),
            CGPoint(x: 0.34, y: 0.78)
        ]
        var events: [InputTimelineEvent] = []
        var frames: [CapturedFrame] = []

        for (index, step) in demoSteps.enumerated() {
            let timestamp = Double(index) * 4.2 + 1.1
            let click = InputTimelineEvent(
                timestamp: timestamp,
                kind: .click,
                location: clickPoints[index % clickPoints.count]
            )
            events.append(click)
            if index == 1 {
                events.append(
                    InputTimelineEvent(
                        timestamp: timestamp + 0.8,
                        kind: .typing,
                        location: nil
                    )
                )
            }
            if index == 3 {
                events.append(
                    InputTimelineEvent(
                        timestamp: timestamp + 0.4,
                        kind: .confirm,
                        location: nil,
                        keyLabel: "回车"
                    )
                )
            }
            frames.append(
                CapturedFrame(
                    image: step.image,
                    timestamp: timestamp,
                    primaryInputEvent: click
                )
            )
        }

        return PreviewSession(frames: frames, events: events)
    }
}
