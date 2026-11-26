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

public enum SidebarSortOrder: String, Codable, CaseIterable, Sendable {
    case custom = "custom"
    case name = "name"
    case createdAt = "createdAt"
    case count = "count"

    public var displayName: String {
        switch self {
        case .custom: return "自定义排序"
        case .name: return "名称排序"
        case .createdAt: return "创建时间排序"
        case .count: return "数量排序"
        }
    }
}

public enum AppAppearanceMode: String, Codable, CaseIterable, Sendable {
    case system = "system"
    case light = "light"
    case dark = "dark"

    public var displayName: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }
}

public enum LiquidGlassMaterialStyle: String, Codable, CaseIterable, Sendable {
    case regular = "regular"
    case clear = "clear"
    case frosted = "frosted"
    case solid = "solid"

    public var displayName: String {
        switch self {
        case .regular: return "标准液态玻璃"
        case .clear: return "通透晶莹"
        case .frosted: return "柔雾磨砂"
        case .solid: return "极简纯色"
        }
    }

    public var subtitle: String {
        switch self {
        case .regular: return "原生 macOS 液态折射玻璃，光影层次与可读性平衡"
        case .clear: return "高通透清澈玻璃质感，更轻盈灵动"
        case .frosted: return "经典细腻磨砂半透明，柔和护眼"
        case .solid: return "去除玻璃折射，专注纯净阅读与内容本身"
        }
    }
}

public enum LiquidGlassAmbientTheme: String, Codable, CaseIterable, Sendable {
    case ocean = "ocean"
    case graphite = "graphite"
    case aurora = "aurora"
    case forest = "forest"
    case warmPaper = "warmPaper"

    public var displayName: String {
        switch self {
        case .ocean: return "极光海蓝"
        case .graphite: return "静谧石墨"
        case .aurora: return "紫霞微光"
        case .forest: return "晨雾松绿"
        case .warmPaper: return "暖阳米纸"
        }
    }
}

public struct LiquidGlassPreferences: Codable, Hashable, Sendable {
    public var appearance: AppAppearanceMode
    public var materialStyle: LiquidGlassMaterialStyle
    public var ambientTheme: LiquidGlassAmbientTheme
    public var glassTintOpacity: Double
    public var ambientIntensity: Double
    public var rimHighlightOpacity: Double
    public var cardTranslucent: Bool

    public init(
        appearance: AppAppearanceMode = .system,
        materialStyle: LiquidGlassMaterialStyle = .regular,
        ambientTheme: LiquidGlassAmbientTheme = .ocean,
        glassTintOpacity: Double = 0.0,
        ambientIntensity: Double = 0.85,
        rimHighlightOpacity: Double = 0.65,
        cardTranslucent: Bool = true
    ) {
        self.appearance = appearance
        self.materialStyle = materialStyle
        self.ambientTheme = ambientTheme
        self.glassTintOpacity = glassTintOpacity
        self.ambientIntensity = ambientIntensity
        self.rimHighlightOpacity = rimHighlightOpacity
        self.cardTranslucent = cardTranslucent
    }

    enum CodingKeys: String, CodingKey {
        case appearance, materialStyle, ambientTheme
        case glassTintOpacity, ambientIntensity, rimHighlightOpacity, cardTranslucent
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.appearance = try c.decodeIfPresent(AppAppearanceMode.self, forKey: .appearance) ?? .system
        self.materialStyle = try c.decodeIfPresent(LiquidGlassMaterialStyle.self, forKey: .materialStyle) ?? .regular
        self.ambientTheme = try c.decodeIfPresent(LiquidGlassAmbientTheme.self, forKey: .ambientTheme) ?? .ocean
        self.glassTintOpacity = try c.decodeIfPresent(Double.self, forKey: .glassTintOpacity) ?? 0.0
        self.ambientIntensity = try c.decodeIfPresent(Double.self, forKey: .ambientIntensity) ?? 0.85
        self.rimHighlightOpacity = try c.decodeIfPresent(Double.self, forKey: .rimHighlightOpacity) ?? 0.65
        self.cardTranslucent = try c.decodeIfPresent(Bool.self, forKey: .cardTranslucent) ?? true
    }

    public static let standard = LiquidGlassPreferences()

    public static let crystalClear = LiquidGlassPreferences(
        appearance: .system,
        materialStyle: .clear,
        ambientTheme: .ocean,
        glassTintOpacity: 0.06,
        ambientIntensity: 1.15,
        rimHighlightOpacity: 0.85,
        cardTranslucent: true
    )

    public static let softFrosted = LiquidGlassPreferences(
        appearance: .system,
        materialStyle: .frosted,
        ambientTheme: .graphite,
        glassTintOpacity: 0.04,
        ambientIntensity: 0.55,
        rimHighlightOpacity: 0.50,
        cardTranslucent: true
    )

    public static let minimalSolid = LiquidGlassPreferences(
        appearance: .system,
        materialStyle: .solid,
        ambientTheme: .graphite,
        glassTintOpacity: 0.0,
        ambientIntensity: 0.0,
        rimHighlightOpacity: 0.25,
        cardTranslucent: false
    )
}

public struct FloatingCaptureSettings: Codable, Hashable, Sendable {
    /// Carbon virtual keyCode (default: 8 = 'C')
    public static let defaultHotKeyCode: UInt32 = 8
    /// Carbon modifier flags (default: optionKey 2048 | shiftKey 512 = 2560 -> ⌥⇧C)
    public static let defaultHotKeyModifiers: UInt32 = 2560

    public var alwaysVisible: Bool
    public var globalHotKeyEnabled: Bool
    public var hotKeyCode: UInt32
    public var hotKeyModifiers: UInt32
    public var autoHideAfterSave: Bool
    public var savedOriginX: Double?
    public var savedOriginY: Double?

    public init(
        alwaysVisible: Bool = false,
        globalHotKeyEnabled: Bool = true,
        hotKeyCode: UInt32 = FloatingCaptureSettings.defaultHotKeyCode,
        hotKeyModifiers: UInt32 = FloatingCaptureSettings.defaultHotKeyModifiers,
        autoHideAfterSave: Bool = true,
        savedOriginX: Double? = nil,
        savedOriginY: Double? = nil
    ) {
        self.alwaysVisible = alwaysVisible
        self.globalHotKeyEnabled = globalHotKeyEnabled
        self.hotKeyCode = hotKeyCode
        self.hotKeyModifiers = hotKeyModifiers
        self.autoHideAfterSave = autoHideAfterSave
        self.savedOriginX = savedOriginX
        self.savedOriginY = savedOriginY
    }

    enum CodingKeys: String, CodingKey {
        case alwaysVisible, globalHotKeyEnabled, hotKeyCode, hotKeyModifiers
        case autoHideAfterSave, savedOriginX, savedOriginY
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.alwaysVisible = try c.decodeIfPresent(Bool.self, forKey: .alwaysVisible) ?? false
        self.globalHotKeyEnabled = try c.decodeIfPresent(Bool.self, forKey: .globalHotKeyEnabled) ?? true
        self.hotKeyCode = try c.decodeIfPresent(UInt32.self, forKey: .hotKeyCode) ?? Self.defaultHotKeyCode
        self.hotKeyModifiers = try c.decodeIfPresent(UInt32.self, forKey: .hotKeyModifiers) ?? Self.defaultHotKeyModifiers
        self.autoHideAfterSave = try c.decodeIfPresent(Bool.self, forKey: .autoHideAfterSave) ?? true
        self.savedOriginX = try c.decodeIfPresent(Double.self, forKey: .savedOriginX)
        self.savedOriginY = try c.decodeIfPresent(Double.self, forKey: .savedOriginY)
    }

    public static let standard = FloatingCaptureSettings()
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
    public var folderSortOrder: SidebarSortOrder
    public var tagSortOrder: SidebarSortOrder
    public var liquidGlass: LiquidGlassPreferences
    public var floatingCapture: FloatingCaptureSettings

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
        defaultSynthesisTemplateId: String = "tpl-knowledge-system",
        folderSortOrder: SidebarSortOrder = .custom,
        tagSortOrder: SidebarSortOrder = .custom,
        liquidGlass: LiquidGlassPreferences = LiquidGlassPreferences(),
        floatingCapture: FloatingCaptureSettings = FloatingCaptureSettings()
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
        self.folderSortOrder = folderSortOrder
        self.tagSortOrder = tagSortOrder
        self.liquidGlass = liquidGlass
        self.floatingCapture = floatingCapture
    }

    enum CodingKeys: String, CodingKey {
        case vaultPath, activeProviderId, activeModelName, providers, reader
        case clipboardMonitorEnabled, autoInsightOnSave, customQuickPrompts
        case synthesisTemplates, defaultSynthesisTemplateId
        case folderSortOrder, tagSortOrder, liquidGlass, floatingCapture
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
        self.folderSortOrder = try c.decodeIfPresent(SidebarSortOrder.self, forKey: .folderSortOrder) ?? .custom
        self.tagSortOrder = try c.decodeIfPresent(SidebarSortOrder.self, forKey: .tagSortOrder) ?? .custom
        self.liquidGlass = try c.decodeIfPresent(LiquidGlassPreferences.self, forKey: .liquidGlass) ?? LiquidGlassPreferences()
        self.floatingCapture = try c.decodeIfPresent(FloatingCaptureSettings.self, forKey: .floatingCapture) ?? FloatingCaptureSettings()
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
