import Foundation

/// Reserved integration architecture for future Obsidian & Notion synchronization.
/// Per PRD: intentionally kept as TODO stubs for v1; Vault files are already Obsidian-ready Markdown + YAML Frontmatter.
public enum ExternalSyncTarget: String, CaseIterable, Identifiable {
    case obsidian
    case notion

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .obsidian: return "Obsidian 知识库集成"
        case .notion: return "Notion 数据库同步"
        }
    }

    public var statusBadge: String {
        switch self {
        case .obsidian: return "TODO · 高优预留"
        case .notion: return "TODO · 远期规划"
        }
    }

    public var description: String {
        switch self {
        case .obsidian:
            return "当前知识沉淀已直接采用标准 Markdown + YAML Frontmatter，未来将支持绑定 Obsidian Vault 子目录、自定义文件名模板、自动双向链接 [[...]] 与增量同步。"
        case .notion:
            return "预留外部同步适配器协议，未来可对接 Notion API 将收藏卡片与高亮自动同步至指定 Database。"
        }
    }
}

public protocol VaultSyncAdapter {
    var target: ExternalSyncTarget { get }
    var isConfigured: Bool { get }
    func syncKnowledgeDoc(_ doc: KnowledgeDoc) async throws
    func syncClip(_ clip: ClipItem, articleMarkdown: String, noteMarkdown: String) async throws
}

// TODO(Obsidian): Implement ObsidianVaultSyncAdapter conforming to VaultSyncAdapter
//   - Configure target Obsidian vault subfolder & filename template (e.g. "{{date}}-{{title}}.md")
//   - Map ReadBox tags -> Obsidian nested #tags & wikilinks [[...]]
//   - Copy referenced local assets into Obsidian attachments directory
// TODO(Notion): Implement NotionSyncAdapter conforming to VaultSyncAdapter
