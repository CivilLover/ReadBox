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

public struct SynthesisPromptTemplate: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var emoji: String
    public var prompt: String
    public var isBuiltIn: Bool

    public init(
        id: String = UUID().uuidString,
        name: String,
        emoji: String = "✨",
        prompt: String,
        isBuiltIn: Bool = false
    ) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.prompt = prompt
        self.isBuiltIn = isBuiltIn
    }

    public static let builtInPresets: [SynthesisPromptTemplate] = [
        SynthesisPromptTemplate(
            id: "tpl-knowledge-system",
            name: "体系化知识沉淀",
            emoji: "📚",
            prompt: "请深度阅读我选中的收藏文章、高亮与笔记，去伪存真，提炼出核心共识、关键分歧、底层框架与可复用方法论，按「背景脉络 → 核心观点 → 对比与分歧 → 可落地启发」整理成一篇结构清晰的个人知识库文档。",
            isBuiltIn: true
        ),
        SynthesisPromptTemplate(
            id: "tpl-compare-matrix",
            name: "多源观点对比矩阵",
            emoji: "⚖️",
            prompt: "请重点对比选中各篇文章的核心立场、关键论据、优势局限与适用场景。先用一张 Markdown 对比表格横向总览，再提炼各方最值得借鉴的观点，最后给出面向个人实践的综合判断。",
            isBuiltIn: true
        ),
        SynthesisPromptTemplate(
            id: "tpl-action-sop",
            name: "实战行动清单 (SOP)",
            emoji: "🛠️",
            prompt: "请过滤掉空泛的背景铺垫，只从选中资料中提炼可直接落地的执行步骤、关键工具/参数、常见避坑点，输出一份带 `- [ ]` 待办复选框的实战操作手册（SOP）。",
            isBuiltIn: true
        ),
        SynthesisPromptTemplate(
            id: "tpl-critical-thinking",
            name: "深度批判与思维延伸",
            emoji: "🧠",
            prompt: "请像资深研究顾问一样审视这些文章：拆解作者隐含的前提假设、可能存在的盲区与反例，找出最反直觉的 3 个洞见，并在文末提出 3–5 个值得继续深挖的研究问题。",
            isBuiltIn: true
        ),
        SynthesisPromptTemplate(
            id: "tpl-weekly-digest",
            name: "阅读周报 / 精华速览",
            emoji: "📰",
            prompt: "请用流畅、克制、信息密度高的周报口吻，把这些收藏串成一篇 3 分钟能读完的专题导读：包含「本期核心主题」「逐篇一句话精华」「跨文章串联启发」。",
            isBuiltIn: true
        )
    ]
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
    public var synthesisTemplates: [SynthesisPromptTemplate]
    public var defaultSynthesisTemplateId: String

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
        ],
        synthesisTemplates: [SynthesisPromptTemplate] = SynthesisPromptTemplate.builtInPresets,
        defaultSynthesisTemplateId: String = "tpl-knowledge-system"
    ) {
        self.vaultPath = vaultPath
        self.activeProviderId = activeProviderId
        self.activeModelName = activeModelName
        self.providers = providers
        self.reader = reader
        self.clipboardMonitorEnabled = clipboardMonitorEnabled
        self.autoInsightOnSave = autoInsightOnSave
        self.customQuickPrompts = customQuickPrompts
        self.synthesisTemplates = synthesisTemplates
        self.defaultSynthesisTemplateId = defaultSynthesisTemplateId
    }

    enum CodingKeys: String, CodingKey {
        case vaultPath, activeProviderId, activeModelName, providers, reader
        case clipboardMonitorEnabled, autoInsightOnSave, customQuickPrompts
        case synthesisTemplates, defaultSynthesisTemplateId
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.vaultPath = try c.decodeIfPresent(String.self, forKey: .vaultPath) ?? ""
        self.activeProviderId = try c.decodeIfPresent(String.self, forKey: .activeProviderId) ?? "deepseek"
        self.activeModelName = try c.decodeIfPresent(String.self, forKey: .activeModelName) ?? "deepseek-chat"
        self.providers = try c.decodeIfPresent([AIProviderProfile].self, forKey: .providers) ?? AIProviderProfile.presets
        self.reader = try c.decodeIfPresent(ReaderPreferences.self, forKey: .reader) ?? ReaderPreferences()
        self.clipboardMonitorEnabled = try c.decodeIfPresent(Bool.self, forKey: .clipboardMonitorEnabled) ?? true
        self.autoInsightOnSave = try c.decodeIfPresent(Bool.self, forKey: .autoInsightOnSave) ?? false
        self.customQuickPrompts = try c.decodeIfPresent([String].self, forKey: .customQuickPrompts) ?? [
            "用 3 句话总结核心结论",
            "提炼这篇文章最反直觉的观点",
            "列出可以立即落地的行动清单",
            "把它整理成一份结构化的知识卡片"
        ]
        self.synthesisTemplates = try c.decodeIfPresent([SynthesisPromptTemplate].self, forKey: .synthesisTemplates) ?? SynthesisPromptTemplate.builtInPresets
        self.defaultSynthesisTemplateId = try c.decodeIfPresent(String.self, forKey: .defaultSynthesisTemplateId) ?? "tpl-knowledge-system"
    }

    public var activeProvider: AIProviderProfile {
        providers.first(where: { $0.id == activeProviderId }) ?? providers.first ?? AIProviderProfile.presets[0]
    }

    public var defaultSynthesisTemplate: SynthesisPromptTemplate {
        synthesisTemplates.first(where: { $0.id == defaultSynthesisTemplateId })
            ?? synthesisTemplates.first
            ?? SynthesisPromptTemplate.builtInPresets[0]
    }
}
