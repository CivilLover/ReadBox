import Foundation

public enum AIAPIFormat: String, Codable, CaseIterable, Sendable {
    case openAICompatible = "openai_compatible"
    case anthropic = "anthropic"

    public var displayName: String {
        switch self {
        case .openAICompatible: return "OpenAI 兼容协议 (DeepSeek / OpenAI / Ollama / 中转)"
        case .anthropic: return "Anthropic Claude 原生协议"
        }
    }
}

public struct AIProviderProfile: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var apiFormat: AIAPIFormat
    public var baseURL: String
    public var defaultModel: String
    public var availableModels: [String]
    public var temperature: Double
    public var requiresAPIKey: Bool

    public init(
        id: String = UUID().uuidString,
        name: String,
        apiFormat: AIAPIFormat = .openAICompatible,
        baseURL: String,
        defaultModel: String,
        availableModels: [String],
        temperature: Double = 0.4,
        requiresAPIKey: Bool = true
    ) {
        self.id = id
        self.name = name
        self.apiFormat = apiFormat
        self.baseURL = baseURL
        self.defaultModel = defaultModel
        self.availableModels = availableModels
        self.temperature = temperature
        self.requiresAPIKey = requiresAPIKey
    }

    public static let presets: [AIProviderProfile] = [
        AIProviderProfile(
            id: "deepseek",
            name: "DeepSeek",
            apiFormat: .openAICompatible,
            baseURL: "https://api.deepseek.com/v1",
            defaultModel: "deepseek-chat",
            availableModels: ["deepseek-chat", "deepseek-reasoner"],
            temperature: 0.4,
            requiresAPIKey: true
        ),
        AIProviderProfile(
            id: "openai",
            name: "OpenAI",
            apiFormat: .openAICompatible,
            baseURL: "https://api.openai.com/v1",
            defaultModel: "gpt-4o-mini",
            availableModels: ["gpt-4o", "gpt-4o-mini", "o3-mini"],
            temperature: 0.4,
            requiresAPIKey: true
        ),
        AIProviderProfile(
            id: "anthropic",
            name: "Anthropic Claude",
            apiFormat: .anthropic,
            baseURL: "https://api.anthropic.com/v1",
            defaultModel: "claude-sonnet-4-20250514",
            availableModels: ["claude-sonnet-4-20250514", "claude-3-5-haiku-latest"],
            temperature: 0.4,
            requiresAPIKey: true
        ),
        AIProviderProfile(
            id: "ollama",
            name: "Ollama (本地模型)",
            apiFormat: .openAICompatible,
            baseURL: "http://127.0.0.1:11434/v1",
            defaultModel: "qwen2.5:7b",
            availableModels: ["qwen2.5:7b", "deepseek-r1:8b", "llama3.1:8b"],
            temperature: 0.4,
            requiresAPIKey: false
        )
    ]
}

public struct ChatMessage: Identifiable, Codable, Hashable, Sendable {
    public enum Role: String, Codable, Sendable {
        case user
        case assistant
        case system
    }

    public var id: String
    public var role: Role
    public var content: String
    public var reasoningContent: String
    public var citedClipTitles: [String]
    public var createdAt: Date

    public init(
        id: String = UUID().uuidString,
        role: Role,
        content: String,
        reasoningContent: String = "",
        citedClipTitles: [String] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.reasoningContent = reasoningContent
        self.citedClipTitles = citedClipTitles
        self.createdAt = createdAt
    }
}

public enum ReaderTheme: String, Codable, CaseIterable, Sendable {
    case system = "system"
    case light = "light"
    case sepia = "sepia"
    case dark = "dark"

    public var displayName: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "纯净白"
        case .sepia: return "护眼纸"
        case .dark: return "暗夜黑"
        }
    }
}

public struct ReaderPreferences: Codable, Hashable, Sendable {
    public var theme: ReaderTheme = .system
    public var fontFamily: String = "-apple-system, 'PingFang SC', 'Helvetica Neue', sans-serif"
    public var fontSize: Double = 17
    public var lineHeight: Double = 1.8
    public var contentWidth: Double = 700

    public init() {}
}

public struct AppSettings: Codable, Sendable {
    public var vaultPath: String
    public var activeProviderId: String
    public var activeModelName: String
    public var providers: [AIProviderProfile]
    public var reader: ReaderPreferences
    public var clipboardMonitorEnabled: Bool
    public var autoInsightOnSave: Bool
    public var customQuickPrompts: [String]

    public init(
        vaultPath: String,
        activeProviderId: String = "deepseek",
        activeModelName: String = "deepseek-chat",
        providers: [AIProviderProfile] = AIProviderProfile.presets,
        reader: ReaderPreferences = ReaderPreferences(),
        clipboardMonitorEnabled: Bool = true,
        autoInsightOnSave: Bool = false,
        customQuickPrompts: [String] = [
            "用 3 句话总结核心结论",
            "提炼这篇文章最反直觉的观点",
            "列出可以立即落地的行动清单",
            "把它整理成一份结构化的知识卡片"
        ]
    ) {
        self.vaultPath = vaultPath
        self.activeProviderId = activeProviderId
        self.activeModelName = activeModelName
        self.providers = providers
        self.reader = reader
        self.clipboardMonitorEnabled = clipboardMonitorEnabled
        self.autoInsightOnSave = autoInsightOnSave
        self.customQuickPrompts = customQuickPrompts
    }

    public var activeProvider: AIProviderProfile {
        providers.first(where: { $0.id == activeProviderId }) ?? providers.first ?? AIProviderProfile.presets[0]
    }
}
