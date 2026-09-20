import AppKit
import CoreGraphics
import Foundation

struct CapturedFrame {
    let image: NSImage
    let timestamp: TimeInterval
    let primaryInputEvent: InputTimelineEvent?

    init(
        image: NSImage,
        timestamp: TimeInterval,
        primaryInputEvent: InputTimelineEvent? = nil
    ) {
        self.image = image
        self.timestamp = timestamp
        self.primaryInputEvent = primaryInputEvent
    }
}

struct AIProcedureStep {
    let timestamp: TimeInterval
    let frameIndex: Int?
    let title: String
    let note: String
    let tip: String

    init(
        timestamp: TimeInterval,
        frameIndex: Int? = nil,
        title: String,
        note: String,
        tip: String
    ) {
        self.timestamp = timestamp
        self.frameIndex = frameIndex
        self.title = title
        self.note = note
        self.tip = tip
    }
}

struct AIProcedureDraft {
    let title: String
    let audience: String
    let summary: String
    let steps: [AIProcedureStep]
    let engineLabel: String
}

enum ModelInputMode: String, CaseIterable, Identifiable {
    case images

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .images: return "操作截图"
        }
    }

    var description: String {
        switch self {
        case .images:
            return "每次鼠标点击或关键按键后在本机截取一张图，确认后一次性发给模型。"
        }
    }
}

enum ModelProvider: String, CaseIterable, Identifiable, Hashable {
    case gemini
    case qwen
    case doubao
    case openAI
    case anthropic
    case deepSeek
    case xAI
    case zhipu
    case kimi
    case mistral
    case customOpenAICompatible

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .gemini: return "Google Gemini"
        case .qwen: return "阿里云百炼 · 通义千问"
        case .doubao: return "火山方舟 · 豆包"
        case .openAI: return "OpenAI"
        case .anthropic: return "Anthropic · Claude"
        case .deepSeek: return "DeepSeek"
        case .xAI: return "xAI · Grok"
        case .zhipu: return "智谱 AI · GLM"
        case .kimi: return "Moonshot AI · Kimi"
        case .mistral: return "Mistral AI"
        case .customOpenAICompatible: return "自定义 OpenAI 兼容接口"
        }
    }

    var description: String {
        switch self {
        case .gemini:
            return "Gemini 视觉模型，支持理解操作截图。"
        case .qwen:
            return "百炼官方视觉模型，支持理解操作截图。"
        case .doubao:
            return "方舟 Seed 视觉模型，支持理解操作截图。"
        case .openAI:
            return "GPT 视觉模型，支持理解操作截图。"
        case .anthropic:
            return "Claude 视觉模型，支持逐张理解操作截图。"
        case .deepSeek:
            return "DeepSeek 视觉模型，只接收图片，适合操作截图。"
        case .xAI:
            return "Grok 视觉模型，只接收图片，适合操作截图。"
        case .zhipu:
            return "GLM 视觉模型，支持理解操作截图。"
        case .kimi:
            return "Kimi 多模态模型，适合理解操作截图。"
        case .mistral:
            return "Mistral 视觉模型，适合理解操作截图。"
        case .customOpenAICompatible:
            return "只连接你确认支持视觉输入的兼容接口。"
        }
    }

    var defaultEndpoint: String {
        switch self {
        case .gemini:
            return "https://generativelanguage.googleapis.com/v1beta/interactions"
        case .qwen:
            return "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"
        case .doubao:
            return "https://ark.cn-beijing.volces.com/api/v3/chat/completions"
        case .openAI:
            return "https://api.openai.com/v1/chat/completions"
        case .anthropic:
            return "https://api.anthropic.com/v1/messages"
        case .deepSeek:
            return "https://api.deepseek.com/chat/completions"
        case .xAI:
            return "https://api.x.ai/v1/responses"
        case .zhipu:
            return "https://open.bigmodel.cn/api/paas/v4/chat/completions"
        case .kimi:
            return "https://api.moonshot.ai/v1/chat/completions"
        case .mistral:
            return "https://api.mistral.ai/v1/chat/completions"
        case .customOpenAICompatible:
            return ""
        }
    }

    var presets: [ModelPreset] {
        switch self {
        case .gemini:
            return [
                ModelPreset(id: "gemini-3.8-flash", name: "Gemini 3.8 Flash", detail: "操作截图 · 当前主推"),
                ModelPreset(id: "gemini-3.7-flash", name: "Gemini 3.7 Flash", detail: "操作截图 · 稳定"),
                ModelPreset(id: "gemini-3.6-flash", name: "Gemini 3.6 Flash", detail: "操作截图 · 平衡"),
                ModelPreset(id: "gemini-3.5-flash-lite", name: "Gemini 3.5 Flash-Lite", detail: "操作截图 · 成本优先"),
                ModelPreset(id: "gemini-3.1-pro-preview", name: "Gemini 3.1 Pro Preview", detail: "操作截图 · 复杂推理")
            ]
        case .qwen:
            return [
                ModelPreset(id: "qwen3.8-max", name: "Qwen 3.8 Max", detail: "操作截图 · 能力优先"),
                ModelPreset(id: "qwen3.8-max-0902", name: "Qwen 3.8 Max · 0902", detail: "操作截图 · 固定快照"),
                ModelPreset(id: "qwen3.8-flash", name: "Qwen 3.8 Flash", detail: "操作截图 · 速度优先"),
                ModelPreset(id: "qwen3.7-plus", name: "Qwen 3.7 Plus", detail: "操作截图 · 平衡"),
                ModelPreset(id: "qwen3.7-flash", name: "Qwen 3.7 Flash", detail: "操作截图 · 轻量"),
                ModelPreset(id: "qwen3.6-plus", name: "Qwen 3.6 Plus", detail: "操作截图 · 稳定"),
                ModelPreset(id: "qwen3.6-flash", name: "Qwen 3.6 Flash", detail: "操作截图 · 成本优先"),
                ModelPreset(id: "qwen3.5-omni-plus", name: "Qwen 3.5 Omni Plus", detail: "操作截图 · 多模态")
            ]
        case .doubao:
            return [
                ModelPreset(id: "doubao-seed-2-0-lite-260428", name: "Doubao Seed 2.0 Lite · 260428", detail: "操作截图 · 推荐"),
                ModelPreset(id: "doubao-seed-2-0-mini-260428", name: "Doubao Seed 2.0 Mini · 260428", detail: "操作截图 · 速度优先"),
                ModelPreset(id: "doubao-seed-2-0-lite-260215", name: "Doubao Seed 2.0 Lite · 260215", detail: "操作截图 · 兼容快照")
            ]
        case .openAI:
            return [
                ModelPreset(id: "gpt-6-astra", name: "GPT-6 Astra", detail: "图片理解 · 当前旗舰"),
                ModelPreset(id: "gpt-5.6-sol", name: "GPT-5.6 Sol", detail: "图片理解 · 复杂工作"),
                ModelPreset(id: "gpt-5.6-terra", name: "GPT-5.6 Terra", detail: "图片理解 · 平衡推荐"),
                ModelPreset(id: "gpt-5.6-luna", name: "GPT-5.6 Luna", detail: "图片理解 · 成本优先")
            ]
        case .anthropic:
            return [
                ModelPreset(id: "claude-fable-5-1", name: "Claude Fable 5.1", detail: "图片理解 · 长程推理"),
                ModelPreset(id: "claude-opus-5", name: "Claude Opus 5", detail: "图片理解 · 当前旗舰"),
                ModelPreset(id: "claude-sonnet-5", name: "Claude Sonnet 5", detail: "图片理解 · 平衡推荐"),
                ModelPreset(id: "claude-haiku-4-5-20251001", name: "Claude Haiku 4.5", detail: "图片理解 · 速度优先")
            ]
        case .deepSeek:
            return [
                ModelPreset(id: "deepseek-flash", name: "DeepSeek Flash", detail: "图片理解 · 当前视觉型号")
            ]
        case .xAI:
            return [
                ModelPreset(id: "grok-4.6", name: "Grok 4.6", detail: "图片理解 · 通用")
            ]
        case .zhipu:
            return [
                ModelPreset(id: "glm-5.3-flash", name: "GLM-5.3-Flash", detail: "操作截图 · 当前高速旗舰"),
                ModelPreset(id: "glm-5v-turbo", name: "GLM-5V-Turbo", detail: "操作截图 · 视觉编码"),
                ModelPreset(id: "glm-4.6v", name: "GLM-4.6V", detail: "操作截图 · 稳定"),
                ModelPreset(id: "glm-4.6v-flashx", name: "GLM-4.6V-FlashX", detail: "操作截图 · 高速"),
                ModelPreset(id: "glm-4.6v-flash", name: "GLM-4.6V-Flash", detail: "操作截图 · 轻量")
            ]
        case .kimi:
            return [
                ModelPreset(id: "kimi-k3", name: "Kimi K3", detail: "图片理解 · 当前旗舰"),
                ModelPreset(id: "kimi-k2.6", name: "Kimi K2.6", detail: "图片理解 · 稳定")
            ]
        case .mistral:
            return [
                ModelPreset(id: "mistral-large-2512", name: "Mistral Large 3", detail: "图片理解 · 能力优先"),
                ModelPreset(id: "mistral-medium-2508", name: "Mistral Medium 3.1", detail: "图片理解 · 平衡"),
                ModelPreset(id: "mistral-small-2506", name: "Mistral Small 3.2", detail: "图片理解 · 推荐"),
                ModelPreset(id: "ministral-14b-2512", name: "Ministral 3 14B", detail: "图片理解 · 轻量")
            ]
        case .customOpenAICompatible:
            return []
        }
    }

    var defaultModel: String {
        presets.first?.id ?? ""
    }

    var supportedInputModes: [ModelInputMode] { [.images] }

    var defaultInputMode: ModelInputMode { .images }
}

struct ModelPreset: Identifiable, Hashable {
    let id: String
    let name: String
    let detail: String
}

struct ConfiguredModelOption: Identifiable, Hashable {
    let provider: ModelProvider
    let modelID: String
    let modelLabel: String

    var id: String {
        Self.identifier(provider: provider, modelID: modelID)
    }

    var displayName: String {
        "\(provider.displayName) · \(modelLabel)"
    }

    static func identifier(provider: ModelProvider, modelID: String) -> String {
        "\(provider.rawValue)::\(modelID)"
    }
}

struct ModelAPIConfiguration {
    let provider: ModelProvider
    let inputMode: ModelInputMode
    let endpoint: String
    let model: String
    let apiKey: String

    var isConfigured: Bool {
        !endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var displayName: String {
        let modelName = model.trimmingCharacters(in: .whitespacesAndNewlines)
        return modelName.isEmpty ? provider.displayName : "\(provider.displayName) · \(modelName)"
    }
}

enum ModelTestState: Equatable {
    case idle
    case testing
    case success(String)
    case failure(String)
}

enum ModelAPIError: LocalizedError {
    case notConfigured
    case invalidEndpoint
    case imageEncodingFailed
    case httpFailure(statusCode: Int, message: String)
    case invalidResponse
    case noSteps

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "请先在“模型设置”中选择多模态模型，并填写 API Key。"
        case .invalidEndpoint:
            return "接口地址无效。请填写完整的 http 或 https 地址。"
        case .imageEncodingFailed:
            return "操作截图无法转换为图片，请重试。"
        case .httpFailure(let statusCode, let message):
            return "模型接口返回 HTTP \(statusCode)：\(message)"
        case .invalidResponse:
            return "模型返回的内容无法解析为 SOPShot 预览。"
        case .noSteps:
            return "模型没有返回有效步骤，请确认使用的是支持视觉输入的多模态模型。"
        }
    }
}

enum ModelAPIClient {
    static func analyze(
        frames: [CapturedFrame],
        configuration: ModelAPIConfiguration,
        inputEvents: [InputTimelineEvent] = [],
        userNote: String = ""
    ) async throws -> AIProcedureDraft {
        guard configuration.isConfigured else { throw ModelAPIError.notConfigured }

        guard !frames.isEmpty else { throw ModelAPIError.invalidResponse }
        let duration = max(1, (frames.map(\.timestamp).max() ?? 0) + 0.05)
        let frameTimestamps = frames.map(\.timestamp)
        let captureEventCount = inputEvents.filter(\.kind.producesScreenshot).count
        let prompt = userPrompt(
            duration: duration,
            frameTimestamps: frameTimestamps,
            captureEventCount: captureEventCount,
            inputEvents: inputEvents,
            userNote: userNote
        )
        let responseText: String
        switch configuration.provider {
        case .gemini:
            responseText = try await sendGeminiImages(
                frames: frames,
                configuration: configuration,
                duration: duration,
                promptText: prompt
            )
        case .anthropic:
            responseText = try await sendAnthropicImages(
                frames: frames,
                configuration: configuration,
                duration: duration,
                promptText: prompt
            )
        case .xAI:
            responseText = try await sendXAIImages(
                frames: frames,
                configuration: configuration,
                duration: duration,
                promptText: prompt
            )
        case .qwen, .doubao, .openAI, .deepSeek, .zhipu, .kimi, .mistral, .customOpenAICompatible:
            responseText = try await sendOpenAICompatibleImages(
                frames: frames,
                configuration: configuration,
                duration: duration,
                promptText: prompt
            )
        }

        let parsed = try parseProcedure(
            responseText,
            duration: duration,
            frameTimestamps: frameTimestamps
        )
        return makeDraft(from: parsed, configuration: configuration)
    }

    static func test(configuration: ModelAPIConfiguration) async throws -> String {
        guard configuration.isConfigured else { throw ModelAPIError.notConfigured }
        return try await testVisualInput(configuration: configuration)
    }

    private static func testVisualInput(configuration: ModelAPIConfiguration) async throws -> String {
        guard let demoImage = DemoImageFactory.steps().first?.image else {
            throw ModelAPIError.imageEncodingFailed
        }
        let testFrame = CapturedFrame(image: demoImage, timestamp: 0)
        let prompt = "这是 SOPShot 内置的视觉输入测试画面。请只回复 OK，不要输出其他内容。"
        let responseText: String

        switch configuration.provider {
        case .gemini:
            responseText = try await sendGeminiImages(
                frames: [testFrame],
                configuration: configuration,
                duration: 1,
                promptText: prompt
            )
        case .anthropic:
            responseText = try await sendAnthropicImages(
                frames: [testFrame],
                configuration: configuration,
                duration: 1,
                promptText: prompt
            )
        case .xAI:
            responseText = try await sendXAIImages(
                frames: [testFrame],
                configuration: configuration,
                duration: 1,
                promptText: prompt
            )
        case .qwen, .doubao, .openAI, .deepSeek, .zhipu, .kimi, .mistral, .customOpenAICompatible:
            responseText = try await sendOpenAICompatibleImages(
                frames: [testFrame],
                configuration: configuration,
                duration: 1,
                promptText: prompt
            )
        }

        guard !responseText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ModelAPIError.invalidResponse
        }
        return "视觉输入测试成功。每次鼠标点击或关键按键会生成一张截图，确认后再发送给模型。"
    }

    private static func makeDraft(
        from parsed: ParsedProcedure,
        configuration: ModelAPIConfiguration
    ) -> AIProcedureDraft {
        AIProcedureDraft(
            title: cleaned(parsed.title, fallback: "操作说明"),
            audience: cleaned(parsed.audience, fallback: "办公同事"),
            summary: cleaned(parsed.summary, fallback: "这份说明由多模态模型根据操作顺序截取的画面整理。"),
            steps: parsed.steps,
            engineLabel: "模型 API · \(configuration.displayName) · \(configuration.inputMode.displayName)"
        )
    }

    private static func sendGeminiImages(
        frames: [CapturedFrame],
        configuration: ModelAPIConfiguration,
        duration: TimeInterval,
        promptText: String? = nil
    ) async throws -> String {
        let imageParts = try frames.map { frame -> [String: Any] in
            guard let data = jpegData(for: frame.image) else { throw ModelAPIError.imageEncodingFailed }
            return [
                "type": "image",
                "data": data.base64EncodedString(),
                "mime_type": "image/jpeg"
            ]
        }
        let prompt = promptText ?? userPrompt(
            duration: duration,
            frameTimestamps: frames.map(\.timestamp),
            captureEventCount: frames.count
        )
        var input: [[String: Any]] = [
            [
                "type": "text",
                "text": "\(systemPrompt)\n\n\(prompt)"
            ]
        ]
        input.append(contentsOf: imageParts)
        let body: [String: Any] = [
            "model": configuration.model,
            "input": input
        ]
        guard let url = endpointURL(from: configuration.endpoint) else {
            throw ModelAPIError.invalidEndpoint
        }
        let data = try await perform(
            body: body,
            url: url,
            headers: [
                "Content-Type": "application/json",
                "x-goog-api-key": configuration.apiKey
            ]
        )
        return try geminiText(from: data)
    }

    private static func sendOpenAICompatibleImages(
        frames: [CapturedFrame],
        configuration: ModelAPIConfiguration,
        duration: TimeInterval,
        promptText: String? = nil
    ) async throws -> String {
        let prompt = promptText ?? userPrompt(
            duration: duration,
            frameTimestamps: frames.map(\.timestamp),
            captureEventCount: frames.count
        )
        var content: [[String: Any]] = [
            [
                "type": "text",
                "text": "\(systemPrompt)\n\n\(prompt)"
            ]
        ]
        for frame in frames {
            guard let data = jpegData(for: frame.image) else { throw ModelAPIError.imageEncodingFailed }
            let imageURL = "data:image/jpeg;base64,\(data.base64EncodedString())"
            if configuration.provider == .mistral {
                content.append([
                    "type": "image_url",
                    "image_url": imageURL
                ])
            } else {
                content.append([
                    "type": "image_url",
                    "image_url": [
                        "url": imageURL,
                        "detail": "high"
                    ]
                ])
            }
        }

        let body: [String: Any] = [
            "model": configuration.model,
            "messages": [
                [
                    "role": "user",
                    "content": content
                ]
            ]
        ]
        return try await sendOpenAICompatible(body: body, configuration: configuration)
    }

    private static func sendAnthropicImages(
        frames: [CapturedFrame],
        configuration: ModelAPIConfiguration,
        duration: TimeInterval,
        promptText: String? = nil
    ) async throws -> String {
        var content: [[String: Any]] = [
            [
                "type": "text",
                "text": promptText ?? userPrompt(
                    duration: duration,
                    frameTimestamps: frames.map(\.timestamp),
                    captureEventCount: frames.count
                )
            ]
        ]
        for frame in frames {
            guard let data = jpegData(for: frame.image) else { throw ModelAPIError.imageEncodingFailed }
            content.append([
                "type": "image",
                "source": [
                    "type": "base64",
                    "media_type": "image/jpeg",
                    "data": data.base64EncodedString()
                ]
            ])
        }

        let body: [String: Any] = [
            "model": configuration.model,
            "max_tokens": 4096,
            "system": systemPrompt,
            "messages": [
                [
                    "role": "user",
                    "content": content
                ]
            ]
        ]
        guard let url = endpointURL(from: configuration.endpoint) else {
            throw ModelAPIError.invalidEndpoint
        }
        let data = try await perform(
            body: body,
            url: url,
            headers: [
                "Content-Type": "application/json",
                "x-api-key": configuration.apiKey,
                "anthropic-version": "2023-06-01"
            ]
        )
        return try anthropicText(from: data)
    }

    private static func sendXAIImages(
        frames: [CapturedFrame],
        configuration: ModelAPIConfiguration,
        duration: TimeInterval,
        promptText: String? = nil
    ) async throws -> String {
        let prompt = promptText ?? userPrompt(
            duration: duration,
            frameTimestamps: frames.map(\.timestamp),
            captureEventCount: frames.count
        )
        var content: [[String: Any]] = [
            [
                "type": "input_text",
                "text": "\(systemPrompt)\n\n\(prompt)"
            ]
        ]
        for frame in frames {
            guard let data = jpegData(for: frame.image) else { throw ModelAPIError.imageEncodingFailed }
            content.append([
                "type": "input_image",
                "image_url": "data:image/jpeg;base64,\(data.base64EncodedString())",
                "detail": "high"
            ])
        }

        let body: [String: Any] = [
            "model": configuration.model,
            "input": [
                [
                    "role": "user",
                    "content": content
                ]
            ]
        ]
        guard let url = endpointURL(from: configuration.endpoint) else {
            throw ModelAPIError.invalidEndpoint
        }
        let data = try await perform(
            body: body,
            url: url,
            headers: [
                "Content-Type": "application/json",
                "Authorization": "Bearer \(configuration.apiKey)"
            ]
        )
        return try geminiText(from: data)
    }

    private static func sendOpenAICompatible(
        body: [String: Any],
        configuration: ModelAPIConfiguration
    ) async throws -> String {
        guard let url = chatCompletionsURL(from: configuration.endpoint) else {
            throw ModelAPIError.invalidEndpoint
        }
        let data = try await perform(
            body: body,
            url: url,
            headers: [
                "Content-Type": "application/json",
                "Authorization": "Bearer \(configuration.apiKey)"
            ]
        )
        let object = try JSONSerialization.jsonObject(with: data)
        guard let dictionary = object as? [String: Any],
              let choices = dictionary["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any] else {
            throw ModelAPIError.invalidResponse
        }

        if let content = message["content"] as? String {
            return content
        }
        if let parts = message["content"] as? [[String: Any]] {
            let text = parts.compactMap { part -> String? in
                part["text"] as? String ?? part["content"] as? String
            }.joined(separator: "\n")
            if !text.isEmpty { return text }
        }
        throw ModelAPIError.invalidResponse
    }

    private static func perform(
        body: [String: Any],
        url: URL,
        headers: [String: String]
    ) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ModelAPIError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw ModelAPIError.httpFailure(
                statusCode: httpResponse.statusCode,
                message: responseMessage(from: data)
            )
        }
        return data
    }

    private static func responseMessage(from data: Data) -> String {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let error = object["error"] as? [String: Any], let message = error["message"] as? String {
                return String(message.prefix(600))
            }
            if let message = object["message"] as? String {
                return String(message.prefix(600))
            }
        }
        return String((String(data: data, encoding: .utf8) ?? "接口没有提供错误详情。").prefix(600))
    }

    private static func endpointURL(from value: String) -> URL? {
        let endpoint = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !endpoint.isEmpty,
              let url = URL(string: endpoint),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil else {
            return nil
        }
        return url
    }

    private static func chatCompletionsURL(from value: String) -> URL? {
        var endpoint = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !endpoint.isEmpty else { return nil }
        if !endpoint.lowercased().hasSuffix("/chat/completions") {
            endpoint = endpoint.hasSuffix("/") ? String(endpoint.dropLast()) : endpoint
            endpoint += "/chat/completions"
        }
        return endpointURL(from: endpoint)
    }

    private static func geminiText(from data: Data) throws -> String {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let dictionary = object as? [String: Any] else {
            throw ModelAPIError.invalidResponse
        }
        for key in ["output_text", "output", "response", "content"] {
            if let value = dictionary[key], let text = collectText(from: value), !text.isEmpty {
                return text
            }
        }
        throw ModelAPIError.invalidResponse
    }

    private static func anthropicText(from data: Data) throws -> String {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let dictionary = object as? [String: Any],
              let content = dictionary["content"],
              let text = collectText(from: content),
              !text.isEmpty else {
            throw ModelAPIError.invalidResponse
        }
        return text
    }

    private static func collectText(from value: Any) -> String? {
        if let string = value as? String {
            return string
        }
        if let dictionary = value as? [String: Any] {
            for key in ["text", "output_text", "value", "content"] {
                if let nested = dictionary[key], let text = collectText(from: nested), !text.isEmpty {
                    return text
                }
            }
        }
        if let array = value as? [Any] {
            let parts = array.compactMap { collectText(from: $0) }.filter { !$0.isEmpty }
            if !parts.isEmpty { return parts.joined(separator: "\n") }
        }
        return nil
    }

    private static func jpegData(for image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else {
            return nil
        }
        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.68])
    }

    private static let systemPrompt = """
    你是一个专门把电脑操作整理成 SOP 的多模态 Agent。
    你必须理解用户按操作发生顺序提供的操作截图，识别真实发生的操作和页面状态变化。
    不要要求用户挑截图，不要输出需要用户继续整理的中间结果。
    只输出严格 JSON，不要输出 Markdown，不要输出解释文字。
    """

    private static func userPrompt(
        duration: TimeInterval,
        frameTimestamps: [TimeInterval],
        captureEventCount: Int,
        inputEvents: [InputTimelineEvent] = [],
        userNote: String = ""
    ) -> String {
        let frameGuide = frameTimestamps.enumerated().map { index, timestamp in
            let eventLabel = inputEvents
                .filter(\.kind.producesScreenshot)
                .min(by: {
                    abs($0.timestamp - timestamp) < abs($1.timestamp - timestamp)
                })?
                .displayLabel ?? "关键操作"
            return "画面 \(index + 1)：第 \(String(format: "%.1f", timestamp)) 秒发生的第 \(index + 1) 次\(eventLabel)"
        }.joined(separator: "\n")
        let trimmedNote = userNote.trimmingCharacters(in: .whitespacesAndNewlines)
        let noteBlock: String
        if trimmedNote.isEmpty {
            noteBlock = ""
        } else {
            noteBlock = """

            用户补充说明（请优先采纳，用于校正流程理解、适用对象、术语和提醒）：
            \(trimmedNote)
            """
        }
        return """
        请把这组按操作顺序截取的电脑操作画面整理成最终可交接说明。
        一共捕获了 \(captureEventCount) 次关键操作（鼠标点击、拖拽、滚动或重要键盘按键）和 \(frameTimestamps.count) 张截图，截图已经按操作发生顺序发送给你：
        \(frameGuide)
        普通字母和数字只属于输入过程，不会触发截图，也不会记录具体字符。请结合每张画面标注的操作类型理解流程。
        连续滚动或拖拽只保留手势结束后的一张画面，请把它们当作一个完整步骤（例如“滚动到页面底部”）。
        每张截图最多对应一个步骤。只保留真正有意义的操作和页面状态变化，忽略重复画面。
        最多返回 12 个步骤，并按照 timestamp 从小到大排列。
        每一个步骤都必须引用一个画面，frame_index 从 1 开始且不能重复。
        timestamp 请填写该画面对应的操作时间，范围是 0 到约 \(String(format: "%.1f", duration)) 秒。\(noteBlock)

        严格返回以下 JSON 结构：
        {\"title\":\"流程标题\",\"audience\":\"适用对象\",\"summary\":\"流程目标\",\"steps\":[{\"frame_index\":3,\"timestamp\":4.2,\"title\":\"步骤标题\",\"note\":\"告诉接手的人要做什么\",\"tip\":\"确实需要时填写提醒，否则留空\"}]}
        """
    }

    private static func parseProcedure(
        _ text: String,
        duration: TimeInterval,
        frameTimestamps: [TimeInterval]?
    ) throws -> ParsedProcedure {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let start = normalized.firstIndex(of: "{"),
              let end = normalized.lastIndex(of: "}"),
              start <= end else {
            throw ModelAPIError.invalidResponse
        }
        let jsonText = String(normalized[start...end])
        let object = try JSONSerialization.jsonObject(with: Data(jsonText.utf8))
        guard let dictionary = object as? [String: Any],
              let rawSteps = dictionary["steps"] as? [[String: Any]] else {
            throw ModelAPIError.invalidResponse
        }

        let candidates = rawSteps.compactMap { raw -> AIProcedureStep? in
            if let frameTimestamps {
                guard !frameTimestamps.isEmpty else { return nil }
                let requestedIndex = integerValue(raw["frame_index"])
                let timestamp = doubleValue(raw["timestamp"])
                let resolvedIndex: Int
                if let requestedIndex, frameTimestamps.indices.contains(requestedIndex - 1) {
                    resolvedIndex = requestedIndex - 1
                } else if let timestamp, timestamp.isFinite {
                    resolvedIndex = frameTimestamps.indices.min {
                        abs(frameTimestamps[$0] - timestamp) < abs(frameTimestamps[$1] - timestamp)
                    } ?? 0
                } else {
                    return nil
                }
                return AIProcedureStep(
                    timestamp: frameTimestamps[resolvedIndex],
                    frameIndex: resolvedIndex + 1,
                    title: cleaned(raw["title"] as? String ?? "", fallback: "完成这一步操作"),
                    note: cleaned(raw["note"] as? String ?? "", fallback: "按照操作截图中的画面完成这一步操作。"),
                    tip: cleaned(raw["tip"] as? String ?? "", fallback: "")
                )
            }

            guard let timestamp = doubleValue(raw["timestamp"]),
                  timestamp.isFinite,
                  timestamp >= 0,
                  timestamp <= duration else {
                return nil
            }
            return AIProcedureStep(
                timestamp: timestamp,
                title: cleaned(raw["title"] as? String ?? "", fallback: "完成这一步操作"),
                note: cleaned(raw["note"] as? String ?? "", fallback: "按照操作截图中的画面完成这一步操作。"),
                tip: cleaned(raw["tip"] as? String ?? "", fallback: "")
            )
        }

        var lastTimestamp: TimeInterval = -1
        let steps = candidates.sorted { $0.timestamp < $1.timestamp }.filter { step in
            guard step.timestamp > lastTimestamp + 0.25 else { return false }
            lastTimestamp = step.timestamp
            return true
        }

        guard !steps.isEmpty else { throw ModelAPIError.noSteps }
        return ParsedProcedure(
            title: dictionary["title"] as? String ?? "",
            audience: dictionary["audience"] as? String ?? "",
            summary: dictionary["summary"] as? String ?? "",
            steps: Array(steps.prefix(12))
        )
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        if let value = value as? NSNumber {
            return value.doubleValue
        }
        if let value = value as? Double {
            return value
        }
        if let value = value as? Int {
            return Double(value)
        }
        return nil
    }

    private static func integerValue(_ value: Any?) -> Int? {
        if let value = value as? NSNumber {
            return value.intValue
        }
        if let value = value as? Int {
            return value
        }
        if let value = value as? Double {
            return Int(value)
        }
        return nil
    }

    private static func cleaned(_ value: String, fallback: String) -> String {
        let normalized = value
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? fallback : normalized
    }
}

private struct ParsedProcedure {
    let title: String
    let audience: String
    let summary: String
    let steps: [AIProcedureStep]
}
