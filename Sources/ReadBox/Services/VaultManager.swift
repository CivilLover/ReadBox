import Foundation
import AppKit

/// Local-First transparent file vault supporting iCloud Drive & arbitrary local folders.
/// Every clip and distilled knowledge document lives as clean Markdown/HTML files on disk,
/// while `.readbox/index.sqlite` serves purely as a rebuildable full-text search index.
public final class VaultManager {
    private let fm = FileManager.default
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    public private(set) var vaultURL: URL
    public let searchDB = SearchDatabase()

    public static var iCloudDriveRootURL: URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let cloudDocs = home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: cloudDocs.path, isDirectory: &isDir), isDir.boolValue {
            return cloudDocs
        }
        return nil
    }

    public static var defaultiCloudVaultURL: URL? {
        iCloudDriveRootURL?.appendingPathComponent("ReadBox", isDirectory: true)
    }

    public static var defaultLocalVaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/ReadBox", isDirectory: true)
    }

    public static var appSupportSettingsURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("ReadBox", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        return support.appendingPathComponent("settings.json")
    }

    public var isUsingiCloudDrive: Bool {
        vaultURL.path.contains("Mobile Documents/com~apple~CloudDocs")
    }

    public init(vaultPath: String? = nil) {
        if let path = vaultPath, !path.isEmpty {
            self.vaultURL = URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
        } else if let iCloud = Self.defaultiCloudVaultURL {
            self.vaultURL = iCloud
        } else {
            self.vaultURL = Self.defaultLocalVaultURL
        }
        ensureStructure()
    }

    public func switchVault(to newURL: URL) {
        self.vaultURL = newURL
        ensureStructure()
    }

    public var clipsRootURL: URL { vaultURL.appendingPathComponent("clips", isDirectory: true) }
    public var knowledgeRootURL: URL { vaultURL.appendingPathComponent("knowledge", isDirectory: true) }
    public var internalDirURL: URL { vaultURL.appendingPathComponent(".readbox", isDirectory: true) }
    public var foldersFileURL: URL { vaultURL.appendingPathComponent("folders.json") }
    public var tagsFileURL: URL { vaultURL.appendingPathComponent("tags.json") }
    public var searchDBURL: URL { internalDirURL.appendingPathComponent("index.sqlite") }

    public func ensureStructure() {
        try? fm.createDirectory(at: vaultURL, withIntermediateDirectories: true)
        try? fm.createDirectory(at: clipsRootURL, withIntermediateDirectories: true)
        try? fm.createDirectory(at: knowledgeRootURL, withIntermediateDirectories: true)
        try? fm.createDirectory(at: internalDirURL, withIntermediateDirectories: true)
        searchDB.open(at: searchDBURL)
    }

    // MARK: - Settings Persistence

    public func loadSettings() -> AppSettings {
        if let data = try? Data(contentsOf: Self.appSupportSettingsURL),
           var loaded = try? decoder.decode(AppSettings.self, from: data) {
            var needsPersist = false
            if loaded.vaultPath.isEmpty {
                loaded.vaultPath = vaultURL.path
                needsPersist = true
            }
            if let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               (raw["mcpAccessKey"] as? String)?.isEmpty ?? true {
                needsPersist = true
            }
            if needsPersist {
                saveSettings(loaded)
            }
            return loaded
        }
        let defaults = AppSettings(vaultPath: vaultURL.path)
        saveSettings(defaults)
        return defaults
    }

    public func saveSettings(_ settings: AppSettings) {
        if let data = try? encoder.encode(settings) {
            try? data.write(to: Self.appSupportSettingsURL, options: .atomic)
        }
    }

    // MARK: - Folders

    public func loadFolders() -> [FolderItem] {
        if let data = try? Data(contentsOf: foldersFileURL),
           let folders = try? decoder.decode([FolderItem].self, from: data) {
            return folders.sorted { $0.sortOrder < $1.sortOrder }
        }
        let defaults = [
            FolderItem(id: "folder-tech", name: "技术研发", emoji: "💻", sortOrder: 0),
            FolderItem(id: "folder-ai", name: "AI 与大模型", emoji: "🤖", parentId: "folder-tech", sortOrder: 1),
            FolderItem(id: "folder-product", name: "产品与思考", emoji: "💡", sortOrder: 2),
            FolderItem(id: "folder-reading", name: "深度阅读", emoji: "📚", sortOrder: 3)
        ]
        saveFolders(defaults)
        return defaults
    }

    public func saveFolders(_ folders: [FolderItem]) {
        if let data = try? encoder.encode(folders) {
            try? data.write(to: foldersFileURL, options: .atomic)
        }
    }

    // MARK: - Standalone Tags

    public func loadTags() -> [TagItem] {
        if let data = try? Data(contentsOf: tagsFileURL),
           let loaded = try? decoder.decode([TagItem].self, from: data) {
            return loaded.sorted { $0.sortOrder < $1.sortOrder }
        }
        return []
    }

    public func saveTags(_ tags: [TagItem]) {
        if let data = try? encoder.encode(tags) {
            try? data.write(to: tagsFileURL, options: .atomic)
        }
    }

    // MARK: - Clips Storage

    public func makeRelativeClipDir(title: String, id: String, date: Date = Date()) -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM"
        let ym = df.string(from: date)
        let slug = Self.sanitizeFilename(title, maxLength: 42)
        let shortId = String(id.prefix(6)).lowercased()
        return "clips/\(ym)/\(slug)-\(shortId)"
    }

    public func clipDirectoryURL(for clip: ClipItem) -> URL {
        vaultURL.appendingPathComponent(clip.relativeDir, isDirectory: true)
    }

    public func clipAssetsURL(for clip: ClipItem) -> URL {
        clipDirectoryURL(for: clip).appendingPathComponent("assets", isDirectory: true)
    }

    public func coverImageURL(for clip: ClipItem) -> URL? {
        guard let name = clip.coverImageName, !name.isEmpty else { return nil }
        let url = clipAssetsURL(for: clip).appendingPathComponent(name)
        return fm.fileExists(atPath: url.path) ? url : nil
    }

    public func saveClip(
        _ clip: ClipItem,
        articleHTML: String? = nil,
        articleMarkdown: String? = nil,
        snapshotHTML: String? = nil,
        noteMarkdown: String? = nil
    ) throws {
        let dir = clipDirectoryURL(for: clip)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        try fm.createDirectory(at: dir.appendingPathComponent("assets", isDirectory: true), withIntermediateDirectories: true)

        let metaURL = dir.appendingPathComponent("meta.json")
        let data = try encoder.encode(clip)
        try data.write(to: metaURL, options: .atomic)

        if let articleHTML {
            try articleHTML.write(to: dir.appendingPathComponent("article.html"), atomically: true, encoding: .utf8)
        }
        if let articleMarkdown {
            let fullMD = FrontmatterParser.renderClipArticleMarkdown(clip: clip, bodyMarkdown: articleMarkdown)
            try fullMD.write(to: dir.appendingPathComponent("article.md"), atomically: true, encoding: .utf8)
        }
        if let snapshotHTML {
            try snapshotHTML.write(to: dir.appendingPathComponent("snapshot.html"), atomically: true, encoding: .utf8)
        }
        if let noteMarkdown {
            try noteMarkdown.write(to: dir.appendingPathComponent("note.md"), atomically: true, encoding: .utf8)
        }

        indexClip(clip)
    }

    public func loadAllClips() -> [ClipItem] {
        var clips: [ClipItem] = []
        guard let enumerator = fm.enumerator(
            at: clipsRootURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return clips }

        for case let fileURL as URL in enumerator {
            if fileURL.lastPathComponent == "meta.json" {
                if let data = try? Data(contentsOf: fileURL),
                   let clip = try? decoder.decode(ClipItem.self, from: data) {
                    clips.append(clip)
                }
            }
        }
        return clips.sorted { $0.createdAt > $1.createdAt }
    }

    public func loadArticleHTML(for clip: ClipItem) -> String {
        let url = clipDirectoryURL(for: clip).appendingPathComponent("article.html")
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    public func loadArticleMarkdown(for clip: ClipItem) -> String {
        let url = clipDirectoryURL(for: clip).appendingPathComponent("article.md")
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    public func loadSnapshotHTML(for clip: ClipItem) -> String {
        let url = clipDirectoryURL(for: clip).appendingPathComponent("snapshot.html")
        if let html = try? String(contentsOf: url, encoding: .utf8), !html.isEmpty {
            return html
        }
        return loadArticleHTML(for: clip)
    }

    public func loadClipNote(for clip: ClipItem) -> String {
        let url = clipDirectoryURL(for: clip).appendingPathComponent("note.md")
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    public func saveClipNote(_ markdown: String, for clip: ClipItem) {
        let dir = clipDirectoryURL(for: clip)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("note.md")
        try? markdown.write(to: url, atomically: true, encoding: .utf8)
        indexClip(clip)
    }

    public func deleteClip(_ clip: ClipItem) {
        let dir = clipDirectoryURL(for: clip)
        try? fm.removeItem(at: dir)
        searchDB.deleteDocument(key: "clip:\(clip.id)")
        for h in clip.highlights {
            searchDB.deleteDocument(key: "highlight:\(h.id)")
        }
    }

    // MARK: - Knowledge Base Documents (.md in knowledge/)

    public func knowledgeFileURL(for doc: KnowledgeDoc) -> URL {
        knowledgeRootURL.appendingPathComponent(doc.fileName)
    }

    public func makeKnowledgeFileName(title: String) -> String {
        let base = Self.sanitizeFilename(title, maxLength: 60)
        var candidate = "\(base).md"
        var suffix = 2
        while fm.fileExists(atPath: knowledgeRootURL.appendingPathComponent(candidate).path) {
            candidate = "\(base)-\(suffix).md"
            suffix += 1
        }
        return candidate
    }

    public func saveKnowledgeDoc(_ doc: KnowledgeDoc) throws {
        try fm.createDirectory(at: knowledgeRootURL, withIntermediateDirectories: true)
        let rendered = FrontmatterParser.renderKnowledgeMarkdown(doc: doc)
        let url = knowledgeFileURL(for: doc)
        try rendered.write(to: url, atomically: true, encoding: .utf8)
        indexKnowledgeDoc(doc)
    }

    public func loadAllKnowledgeDocs() -> [KnowledgeDoc] {
        var docs: [KnowledgeDoc] = []
        guard let items = try? fm.contentsOfDirectory(at: knowledgeRootURL, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) else {
            return docs
        }
        for url in items where url.pathExtension.lowercased() == "md" {
            if let raw = try? String(contentsOf: url, encoding: .utf8) {
                let attrs = try? url.resourceValues(forKeys: [.contentModificationDateKey])
                let doc = FrontmatterParser.parseKnowledgeMarkdown(
                    raw,
                    fileName: url.lastPathComponent,
                    fallbackDate: attrs?.contentModificationDate ?? Date()
                )
                docs.append(doc)
            }
        }
        return docs.sorted { $0.updatedAt > $1.updatedAt }
    }

    public func deleteKnowledgeDoc(_ doc: KnowledgeDoc) {
        try? fm.removeItem(at: knowledgeFileURL(for: doc))
        searchDB.deleteDocument(key: "knowledge:\(doc.id)")
    }

    /// Exports a KnowledgeDoc `.md` file to any local or iCloud folder chosen by the user.
    public func exportKnowledgeDoc(_ doc: KnowledgeDoc, toDirectory dirURL: URL) throws -> URL {
        try fm.createDirectory(at: dirURL, withIntermediateDirectories: true)
        let targetName = Self.sanitizeFilename(doc.title, maxLength: 72) + ".md"
        let dest = dirURL.appendingPathComponent(targetName)
        let rendered = FrontmatterParser.renderKnowledgeMarkdown(doc: doc)
        try rendered.write(to: dest, atomically: true, encoding: .utf8)
        return dest
    }

    /// Exports a Clip (article + highlights + personal notes) as a clean standalone Markdown file to any folder.
    public func exportClipAsMarkdown(_ clip: ClipItem, toDirectory dirURL: URL) throws -> URL {
        try fm.createDirectory(at: dirURL, withIntermediateDirectories: true)
        let targetName = Self.sanitizeFilename(clip.title, maxLength: 72) + ".md"
        let dest = dirURL.appendingPathComponent(targetName)

        var sections: [String] = []
        let articleMD = loadArticleMarkdown(for: clip)
        sections.append(articleMD.isEmpty ? "# \(clip.title)\n\n\(clip.excerpt)" : articleMD)

        if !clip.highlights.isEmpty {
            sections.append("\n---\n\n## 高亮标注\n")
            for h in clip.highlights {
                sections.append("> \(h.quote)")
                if !h.note.isEmpty {
                    sections.append("\n- 批注：\(h.note)")
                }
                sections.append("")
            }
        }

        let personalNote = loadClipNote(for: clip).trimmingCharacters(in: .whitespacesAndNewlines)
        if !personalNote.isEmpty {
            sections.append("\n---\n\n## 个人笔记\n\n\(personalNote)")
        }

        try sections.joined(separator: "\n").write(to: dest, atomically: true, encoding: .utf8)
        return dest
    }

    // MARK: - Full-Text Indexing

    public func indexClip(_ clip: ClipItem) {
        let articleMD = loadArticleMarkdown(for: clip)
        let noteMD = loadClipNote(for: clip)
        let body = [clip.excerpt, articleMD, noteMD].joined(separator: "\n")
        let meta = ([clip.domain, clip.author] + clip.tags).filter { !$0.isEmpty }.joined(separator: " ")
        searchDB.upsertDocument(
            key: "clip:\(clip.id)",
            kind: .clip,
            targetId: clip.id,
            title: clip.title,
            body: body,
            meta: meta
        )
        for h in clip.highlights {
            searchDB.upsertDocument(
                key: "highlight:\(h.id)",
                kind: .highlight,
                targetId: clip.id,
                title: clip.title,
                body: "\(h.quote)\n\(h.note)",
                meta: h.color.displayName
            )
        }
    }

    public func indexKnowledgeDoc(_ doc: KnowledgeDoc) {
        searchDB.upsertDocument(
            key: "knowledge:\(doc.id)",
            kind: .knowledge,
            targetId: doc.id,
            title: doc.title,
            body: doc.content,
            meta: doc.tags.joined(separator: " ")
        )
    }

    public func rebuildSearchIndex(clips: [ClipItem], docs: [KnowledgeDoc]) {
        searchDB.clearAll()
        for clip in clips {
            indexClip(clip)
        }
        for doc in docs {
            indexKnowledgeDoc(doc)
        }
    }

    // MARK: - Seed First-Run Welcome Content

    public func seedWelcomeContentIfEmpty() {
        let existingClips = loadAllClips()
        let existingDocs = loadAllKnowledgeDocs()
        guard existingClips.isEmpty && existingDocs.isEmpty else { return }

        let clipId = UUID().uuidString
        let relDir = makeRelativeClipDir(title: "欢迎使用 ReadBox 个人阅读与知识工作台", id: clipId)
        let welcomeHTML = """
        <p>欢迎来到 <strong>ReadBox</strong> —— 专为 macOS 个人用户打造的 Local-First AI 剪藏阅读与知识沉淀工作台。</p>
        <h2>你可以立即体验的核心工作流</h2>
        <ol>
            <li><strong>剪藏微信公众号与任意网页</strong>：按 <code>⌘N</code> 或直接复制微信公众号/网页链接，ReadBox 会自动提取纯净正文并把防盗链图片下载到本地，原文删了也能永久离线阅读。</li>
            <li><strong>沉浸阅读 + 5 色划词高亮</strong>：用鼠标选中这段文字试试看！你可以直接添加黄色/绿色/蓝色/粉色/紫色高亮，或者一键「引用到笔记」「问 AI」。</li>
            <li><strong>右侧 AI 助手（支持 DeepSeek）</strong>：点击右上角打开右侧栏，在「设置 (⌘,)」填入你的 DeepSeek API Key 后，即可像 Chrome 侧边栏一样随时就当前文章或全库内容提问。</li>
            <li><strong>单栏所见即所得 Markdown 笔记</strong>：切换到右侧栏的「📝 笔记」标签，输入 <code># 标题</code>、<code>**加粗**</code>、<code>- [ ] 待办</code>，享受 Typora 风格的纯单栏实时渲染，拒绝左右分栏割裂感。</li>
            <li><strong>知识库沉淀与 iCloud 同步</strong>：选中多篇文章后点击「AI 归纳沉淀」，AI 会帮你梳理归档成标准 Markdown 知识文档，直接落盘在你的 iCloud Drive 或任意本地目录中，未来无缝衔接 Obsidian。</li>
        </ol>
        <blockquote>阅读本身不是终点，思考、整理并沉淀为属于你自己的知识体系，才是收藏的意义。</blockquote>
        """
        let welcomeMD = """
        欢迎来到 **ReadBox** —— 专为 macOS 个人用户打造的 Local-First AI 剪藏阅读与知识沉淀工作台。

        ## 你可以立即体验的核心工作流

        1. **剪藏微信公众号与任意网页**：按 `⌘N` 或直接复制微信公众号/网页链接，ReadBox 会自动提取纯净正文并把防盗链图片下载到本地。
        2. **沉浸阅读 + 5 色划词高亮**：用鼠标选中文字即可弹出 5 色高亮工具条，并一键引用到笔记或发送给 AI 提问。
        3. **右侧 AI 助手（支持 DeepSeek）**：在设置填入 DeepSeek API Key，即可在侧边栏流式对话，并支持 DeepSeek-R1 思维链折叠展示。
        4. **单栏所见即所得 Markdown 笔记**：纯单栏实时渲染，所见即所得。
        5. **知识库沉淀与 iCloud 同步**：支持全库/多篇归纳成标准 `.md` 知识文档，透明保存在 iCloud Drive 或任意本地文件夹。

        > 阅读本身不是终点，思考、整理并沉淀为属于你自己的知识体系，才是收藏的意义。
        """

        let sampleHighlight = HighlightItem(
            clipId: clipId,
            quote: "阅读本身不是终点，思考、整理并沉淀为属于你自己的知识体系，才是收藏的意义。",
            note: "收藏的终极目标是知识沉淀。",
            color: .yellow
        )

        let welcomeClip = ClipItem(
            id: clipId,
            relativeDir: relDir,
            title: "欢迎使用 ReadBox：打造属于你的 MacBook AI 知识工作台",
            excerpt: "专为 macOS 个人用户打造的 Local-First AI 剪藏阅读与知识沉淀工作台，支持公众号解析、DeepSeek 侧边问答、单栏所见即所得笔记与 iCloud 同步。",
            url: "https://readbox.local/welcome",
            domain: "readbox.local",
            author: "ReadBox 指南",
            sourceType: .note,
            folderId: nil,
            tags: ["指南", "工作流"],
            isStarred: true,
            isRead: false,
            highlights: [sampleHighlight]
        )

        let welcomeNote = """
        ## 我的阅读想法

        - [x] 配置 DeepSeek API Key（`⌘,` 打开设置）
        - [ ] 试试复制一篇微信公众号文章链接并一键收藏
        - [ ] 选中几篇文章体验「AI 归纳沉淀到知识库」

        > 阅读本身不是终点，思考、整理并沉淀为属于你自己的知识体系，才是收藏的意义。
        """

        try? saveClip(
            welcomeClip,
            articleHTML: welcomeHTML,
            articleMarkdown: welcomeMD,
            snapshotHTML: welcomeHTML,
            noteMarkdown: welcomeNote
        )

        let sampleDoc = KnowledgeDoc(
            fileName: makeKnowledgeFileName(title: "个人知识沉淀模板"),
            title: "个人知识沉淀模板",
            tags: ["知识库", "模板"],
            sourceClipIds: [clipId],
            sourceLinks: ["https://readbox.local/welcome"],
            content: """
            ## 核心洞见

            这里存放由你亲自整理，或由 **AI 跨文章归纳生成** 的知识沉淀文档。每一篇文档都是标准的 `.md` 文件（带 YAML Frontmatter），直接保存在你的 iCloud Drive 或本地文件夹中。

            ### 推荐沉淀结构

            - **问题背景**：我为什么关注这个主题？
            - **多源观点对比**：不同公众号文章、博客的核心分歧在哪里？
            - **我的结论与行动项**：下一步可以怎么应用到工作或项目中？

            > 提示：直接在当前页面编辑即可体验纯单栏所见即所得 Markdown 渲染，也可以点击右上角一键导出到任意本地或 iCloud 文件夹。
            """,
            generatedByModel: "ReadBox Built-in"
        )
        try? saveKnowledgeDoc(sampleDoc)
    }

    // MARK: - Helpers

    public static func sanitizeFilename(_ raw: String, maxLength: Int = 56) -> String {
        let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>#\n\r\t")
        let cleaned = raw
            .components(separatedBy: invalid)
            .joined(separator: "-")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = String(cleaned.prefix(maxLength)).trimmingCharacters(in: CharacterSet(charactersIn: "- ."))
        return prefix.isEmpty ? "untitled" : prefix
    }
}
