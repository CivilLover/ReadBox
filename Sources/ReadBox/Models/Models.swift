import Foundation
import SwiftUI

public enum ClipSourceType: String, Codable, CaseIterable, Sendable {
    case wechat = "wechat"
    case webpage = "webpage"
    case note = "note"

    public var displayName: String {
        switch self {
        case .wechat: return "公众号"
        case .webpage: return "网页"
        case .note: return "速记"
        }
    }

    public var systemImage: String {
        switch self {
        case .wechat: return "message.fill"
        case .webpage: return "globe"
        case .note: return "doc.text.fill"
        }
    }
}

public enum HighlightColor: String, Codable, CaseIterable, Sendable {
    case yellow
    case green
    case blue
    case pink
    case purple

    public var displayName: String {
        switch self {
        case .yellow: return "黄色"
        case .green: return "绿色"
        case .blue: return "蓝色"
        case .pink: return "粉色"
        case .purple: return "紫色"
        }
    }

    public var swiftUIColor: Color {
        switch self {
        case .yellow: return Color(red: 0.98, green: 0.80, blue: 0.22)
        case .green: return Color(red: 0.45, green: 0.85, blue: 0.47)
        case .blue: return Color(red: 0.42, green: 0.72, blue: 0.98)
        case .pink: return Color(red: 0.98, green: 0.56, blue: 0.70)
        case .purple: return Color(red: 0.73, green: 0.58, blue: 0.96)
        }
    }

    public var cssHex: String {
        switch self {
        case .yellow: return "rgba(255, 220, 82, 0.45)"
        case .green: return "rgba(128, 224, 134, 0.42)"
        case .blue: return "rgba(116, 188, 255, 0.42)"
        case .pink: return "rgba(255, 152, 184, 0.42)"
        case .purple: return "rgba(194, 156, 252, 0.42)"
        }
    }
}

public struct HighlightItem: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var clipId: String
    public var quote: String
    public var note: String
    public var color: HighlightColor
    public var contextPrefix: String
    public var contextSuffix: String
    public var createdAt: Date

    public init(
        id: String = UUID().uuidString,
        clipId: String,
        quote: String,
        note: String = "",
        color: HighlightColor = .yellow,
        contextPrefix: String = "",
        contextSuffix: String = "",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.clipId = clipId
        self.quote = quote
        self.note = note
        self.color = color
        self.contextPrefix = contextPrefix
        self.contextSuffix = contextSuffix
        self.createdAt = createdAt
    }
}

public struct AIInsight: Codable, Hashable, Sendable {
    public var summary: String
    public var takeaways: [String]
    public var keyQuestions: [String]
    public var suggestedTags: [String]
    public var suggestedFolder: String?
    public var generatedAt: Date

    public init(
        summary: String,
        takeaways: [String] = [],
        keyQuestions: [String] = [],
        suggestedTags: [String] = [],
        suggestedFolder: String? = nil,
        generatedAt: Date = Date()
    ) {
        self.summary = summary
        self.takeaways = takeaways
        self.keyQuestions = keyQuestions
        self.suggestedTags = suggestedTags
        self.suggestedFolder = suggestedFolder
        self.generatedAt = generatedAt
    }
}

public struct ClipItem: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var relativeDir: String // e.g. "clips/2026-11/slug-shortid"
    public var title: String
    public var excerpt: String
    public var url: String
    public var domain: String
    public var author: String
    public var sourceType: ClipSourceType
    public var coverImageName: String? // relative inside assets/
    public var folderId: String?
    public var tags: [String]
    public var isStarred: Bool
    public var isRead: Bool
    public var isArchived: Bool
    public var readProgress: Double
    public var createdAt: Date
    public var updatedAt: Date
    public var highlights: [HighlightItem]
    public var aiInsight: AIInsight?

    public init(
        id: String = UUID().uuidString,
        relativeDir: String,
        title: String,
        excerpt: String = "",
        url: String = "",
        domain: String = "",
        author: String = "",
        sourceType: ClipSourceType = .webpage,
        coverImageName: String? = nil,
        folderId: String? = nil,
        tags: [String] = [],
        isStarred: Bool = false,
        isRead: Bool = false,
        isArchived: Bool = false,
        readProgress: Double = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        highlights: [HighlightItem] = [],
        aiInsight: AIInsight? = nil
    ) {
        self.id = id
        self.relativeDir = relativeDir
        self.title = title
        self.excerpt = excerpt
        self.url = url
        self.domain = domain
        self.author = author
        self.sourceType = sourceType
        self.coverImageName = coverImageName
        self.folderId = folderId
        self.tags = tags
        self.isStarred = isStarred
        self.isRead = isRead
        self.isArchived = isArchived
        self.readProgress = readProgress
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.highlights = highlights
        self.aiInsight = aiInsight
    }

    public var isInInbox: Bool {
        folderId == nil && !isArchived
    }
}

public struct FolderItem: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var emoji: String
    public var parentId: String?
    public var sortOrder: Int
    public var createdAt: Date

    public init(
        id: String = UUID().uuidString,
        name: String,
        emoji: String = "📁",
        parentId: String? = nil,
        sortOrder: Int = 0,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.parentId = parentId
        self.sortOrder = sortOrder
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id, name, emoji, parentId, sortOrder, createdAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.name = try c.decode(String.self, forKey: .name)
        self.emoji = try c.decodeIfPresent(String.self, forKey: .emoji) ?? "📁"
        self.parentId = try c.decodeIfPresent(String.self, forKey: .parentId)
        self.sortOrder = try c.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
        self.createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date(timeIntervalSince1970: 0)
    }
}

public struct TagItem: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var sortOrder: Int
    public var createdAt: Date

    public init(
        id: String = UUID().uuidString,
        name: String,
        sortOrder: Int = 0,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.sortOrder = sortOrder
        self.createdAt = createdAt
    }
}

public struct KnowledgeDoc: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var fileName: String // relative inside knowledge/
    public var title: String
    public var tags: [String]
    public var sourceClipIds: [String]
    public var sourceLinks: [String]
    public var content: String // Markdown body without frontmatter
    public var createdAt: Date
    public var updatedAt: Date
    public var generatedByModel: String?

    public init(
        id: String = UUID().uuidString,
        fileName: String,
        title: String,
        tags: [String] = [],
        sourceClipIds: [String] = [],
        sourceLinks: [String] = [],
        content: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        generatedByModel: String? = nil
    ) {
        self.id = id
        self.fileName = fileName
        self.title = title
        self.tags = tags
        self.sourceClipIds = sourceClipIds
        self.sourceLinks = sourceLinks
        self.content = content
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.generatedByModel = generatedByModel
    }
}
