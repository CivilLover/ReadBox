import Foundation
import SwiftUI
import AppKit

public enum SidebarDestination: Hashable {
    case inbox
    case all
    case unread
    case starred
    case knowledgeBase
    case annotations
    case archived
    case folder(String)
    case tag(String)
}

public enum LibraryViewMode: String, CaseIterable {
    case cards = "详情卡片"
    case list = "简洁列表"
}

public enum LibrarySortOrder: String, CaseIterable {
    case newest = "从新到旧"
    case oldest = "从旧到新"
    case title = "按标题"
}

public enum RightPanelTab: String, CaseIterable {
    case ai = "AI 助手"
    case note = "笔记"
    case highlights = "标注"
}

@MainActor
public final class AppState: ObservableObject {
    public let vault: VaultManager
    public let clipper = WebClipperService()
    public let aiService = AIService()
    public let clipboardMonitor = ClipboardMonitor()

    @Published public var settings: AppSettings
    @Published public var folders: [FolderItem] = []
    @Published public var clips: [ClipItem] = []
    @Published public var knowledgeDocs: [KnowledgeDoc] = []

    // Navigation & Workspace State
    @Published public var destination: SidebarDestination = .inbox
    @Published public var viewMode: LibraryViewMode = .cards
    @Published public var sortOrder: LibrarySortOrder = .newest
    @Published public var sourceFilter: ClipSourceType? = nil
    @Published public var activeClipId: String? = nil
    @Published public var activeKnowledgeDocId: String? = nil

    // Multi-select for batch organize & AI Knowledge Synthesis
    @Published public var isMultiSelectMode: Bool = false
    @Published public var selectedClipIds: Set<String> = []

    // Right Inspector Drawer (Chrome-side-panel style)
    @Published public var isRightPanelOpen: Bool = true
    @Published public var rightPanelTab: RightPanelTab = .ai
    @Published public var showGlobalAIDrawer: Bool = false

    // Modals & Overlays
    @Published public var showQuickAddSheet: Bool = false
    @Published public var quickAddPrefillURL: String = ""
    @Published public var showQuickSearchOverlay: Bool = false
    @Published public var showSynthesisSheet: Bool = false
    @Published public var synthesisTargetClipIds: [String] = []

    // Reader & Editor live bridges
    @Published public var pendingScrollToHighlightId: String? = nil
    @Published public var pendingNoteAppendMarkdown: String? = nil
    @Published public var pendingAIQuoteQuestion: String? = nil

    // AI Chat Histories (keyed by clipId or "global")
    @Published public var chatHistories: [String: [ChatMessage]] = [:]
    @Published public var isAIStreaming: Bool = false
    @Published public var isGeneratingInsight: Bool = false
    private var activeStreamTask: Task<Void, Never>?

    // Background Clipping & Toast Feedback
    @Published public var isClipping: Bool = false
    @Published public var toastMessage: String? = nil
    private var toastTask: Task<Void, Never>?

    public init() {
        let initialVault = VaultManager()
        let loadedSettings = initialVault.loadSettings()
        if loadedSettings.vaultPath != initialVault.vaultURL.path {
            initialVault.switchVault(to: URL(fileURLWithPath: loadedSettings.vaultPath, isDirectory: true))
        }
        self.vault = initialVault
        self.settings = loadedSettings
        self.reloadVaultData()
        if loadedSettings.clipboardMonitorEnabled {
            self.clipboardMonitor.start()
        }
    }

    public func reloadVaultData() {
        vault.ensureStructure()
        vault.seedWelcomeContentIfEmpty()
        folders = vault.loadFolders()
        clips = vault.loadAllClips()
        knowledgeDocs = vault.loadAllKnowledgeDocs()
        vault.rebuildSearchIndex(clips: clips, docs: knowledgeDocs)
        if activeKnowledgeDocId == nil {
            activeKnowledgeDocId = knowledgeDocs.first?.id
        }
    }

    public func saveSettings() {
        vault.saveSettings(settings)
        if settings.clipboardMonitorEnabled {
            clipboardMonitor.start()
        } else {
            clipboardMonitor.stop()
        }
    }

    public func switchVaultDirectory(to url: URL) {
        vault.switchVault(to: url)
        settings.vaultPath = url.path
        vault.saveSettings(settings)
        activeClipId = nil
        activeKnowledgeDocId = nil
        reloadVaultData()
        showToast("已切换知识库目录：\(url.lastPathComponent)")
    }

    public func showToast(_ message: String) {
        toastMessage = message
        toastTask?.cancel()
        toastTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if !Task.isCancelled {
                toastMessage = nil
            }
        }
    }

    // MARK: - Computed Collections

    public var activeClip: ClipItem? {
        guard let id = activeClipId else { return nil }
        return clips.first(where: { $0.id == id })
    }

    public var activeKnowledgeDoc: KnowledgeDoc? {
        guard let id = activeKnowledgeDocId else { return nil }
        return knowledgeDocs.first(where: { $0.id == id })
    }

    public var allTagsWithCount: [(tag: String, count: Int)] {
        var counts: [String: Int] = [:]
        for clip in clips where !clip.isArchived {
            for t in clip.tags {
                counts[t, default: 0] += 1
            }
        }
        return counts.map { ($0.key, $0.value) }.sorted { $0.count > $1.count || ($0.count == $1.count && $0.tag < $1.tag) }
    }

    public var allHighlights: [(clip: ClipItem, highlight: HighlightItem)] {
        clips
            .flatMap { clip in clip.highlights.map { (clip: clip, highlight: $0) } }
            .sorted { $0.highlight.createdAt > $1.highlight.createdAt }
    }

    public var filteredClips: [ClipItem] {
        var result: [ClipItem]
        switch destination {
        case .inbox:
            result = clips.filter { $0.isInInbox }
        case .all:
            result = clips.filter { !$0.isArchived }
        case .unread:
            result = clips.filter { !$0.isRead && !$0.isArchived }
        case .starred:
            result = clips.filter { $0.isStarred && !$0.isArchived }
        case .archived:
            result = clips.filter { $0.isArchived }
        case .folder(let fid):
            let descendantIds = folderAndDescendantIds(for: fid)
            result = clips.filter { !$0.isArchived && ($0.folderId.map { descendantIds.contains($0) } ?? false) }
        case .tag(let tag):
            result = clips.filter { !$0.isArchived && $0.tags.contains(tag) }
        case .knowledgeBase, .annotations:
            result = []
        }

        if let sourceFilter {
            result = result.filter { $0.sourceType == sourceFilter }
        }

        switch sortOrder {
        case .newest:
            result.sort { $0.createdAt > $1.createdAt }
        case .oldest:
            result.sort { $0.createdAt < $1.createdAt }
        case .title:
            result.sort { $0.title.localizedCompare($1.title) == .orderedAscending }
        }
        return result
    }

    public func folderAndDescendantIds(for folderId: String) -> Set<String> {
        var ids: Set<String> = [folderId]
        var frontier = [folderId]
        while let current = frontier.popLast() {
            for f in folders where f.parentId == current && !ids.contains(f.id) {
                ids.insert(f.id)
                frontier.append(f.id)
            }
        }
        return ids
    }

    public func countForDestination(_ dest: SidebarDestination) -> Int {
        switch dest {
        case .inbox: return clips.filter { $0.isInInbox }.count
        case .all: return clips.filter { !$0.isArchived }.count
        case .unread: return clips.filter { !$0.isRead && !$0.isArchived }.count
        case .starred: return clips.filter { $0.isStarred && !$0.isArchived }.count
        case .knowledgeBase: return knowledgeDocs.count
        case .annotations: return allHighlights.count
        case .archived: return clips.filter { $0.isArchived }.count
        case .folder(let fid):
            let ids = folderAndDescendantIds(for: fid)
            return clips.filter { !$0.isArchived && ($0.folderId.map { ids.contains($0) } ?? false) }.count
        case .tag(let tag):
            return clips.filter { !$0.isArchived && $0.tags.contains(tag) }.count
        }
    }

    public func folderName(for folderId: String?) -> String? {
        guard let fid = folderId else { return nil }
        return folders.first(where: { $0.id == fid })?.name
    }

    // MARK: - Clip CRUD & Web Clipping

    public func addClipFromURL(_ rawURL: String, folderId: String? = nil, tags: [String] = []) async {
        let trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isClipping = true
        defer { isClipping = false }

        let clipId = UUID().uuidString
        let tempDir = vault.makeRelativeClipDir(title: "clip", id: clipId)
        let tempClip = ClipItem(id: clipId, relativeDir: tempDir, title: "抓取中...")
        let assetsDir = vault.clipAssetsURL(for: tempClip)

        do {
            let parsed = try await clipper.clipURL(trimmed, assetsDirectory: assetsDir)
            let finalRelDir = vault.makeRelativeClipDir(title: parsed.title, id: clipId)
            let finalClip = ClipItem(
                id: clipId,
                relativeDir: finalRelDir,
                title: parsed.title,
                excerpt: parsed.excerpt,
                url: trimmed.hasPrefix("http") ? trimmed : "https://\(trimmed)",
                domain: parsed.domain,
                author: parsed.author,
                sourceType: parsed.sourceType,
                coverImageName: parsed.coverImageName,
                folderId: folderId,
                tags: tags
            )

            // Move temp assets directory into final slug directory if path differs
            let oldDir = vault.clipDirectoryURL(for: tempClip)
            let newDir = vault.clipDirectoryURL(for: finalClip)
            if oldDir != newDir, FileManager.default.fileExists(atPath: oldDir.path) {
                try? FileManager.default.createDirectory(at: newDir.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? FileManager.default.moveItem(at: oldDir, to: newDir)
            }

            try vault.saveClip(
                finalClip,
                articleHTML: parsed.cleanedHTML,
                articleMarkdown: parsed.markdown,
                snapshotHTML: parsed.snapshotHTML,
                noteMarkdown: ""
            )

            clips.insert(finalClip, at: 0)
            showToast("已收藏：\(finalClip.title)")

            if settings.autoInsightOnSave {
                Task { await generateInsight(for: finalClip) }
            }
        } catch {
            showToast("收藏失败：\(error.localizedDescription)")
        }
    }

    public func addQuickTextClip(title: String, body: String, folderId: String? = nil, tags: [String] = []) {
        let finalTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? String(body.prefix(36))
            : title.trimmingCharacters(in: .whitespacesAndNewlines)
        let clipId = UUID().uuidString
        let relDir = vault.makeRelativeClipDir(title: finalTitle, id: clipId)

        let escapedParagraphs = body
            .components(separatedBy: "\n\n")
            .map { "<p>\($0.replacingOccurrences(of: "\n", with: "<br/>"))</p>" }
            .joined(separator: "\n")

        let clip = ClipItem(
            id: clipId,
            relativeDir: relDir,
            title: finalTitle,
            excerpt: String(body.prefix(180)),
            url: "",
            domain: "本地速记",
            author: "个人记录",
            sourceType: .note,
            folderId: folderId,
            tags: tags
        )

        do {
            try vault.saveClip(clip, articleHTML: escapedParagraphs, articleMarkdown: body, snapshotHTML: escapedParagraphs, noteMarkdown: "")
            clips.insert(clip, at: 0)
            showToast("已保存速记：\(finalTitle)")
        } catch {
            showToast("保存失败：\(error.localizedDescription)")
        }
    }

    public func updateClip(_ clip: ClipItem) {
        var mutable = clip
        mutable.updatedAt = Date()
        if let idx = clips.firstIndex(where: { $0.id == mutable.id }) {
            clips[idx] = mutable
        }
        try? vault.saveClip(mutable)
    }

    public func deleteClip(_ clip: ClipItem) {
        if activeClipId == clip.id { activeClipId = nil }
        clips.removeAll { $0.id == clip.id }
        selectedClipIds.remove(clip.id)
        vault.deleteClip(clip)
        showToast("已删除：\(clip.title)")
    }

    public func toggleStar(_ clip: ClipItem) {
        var copy = clip
        copy.isStarred.toggle()
        updateClip(copy)
    }

    public func toggleRead(_ clip: ClipItem) {
        var copy = clip
        copy.isRead.toggle()
        updateClip(copy)
    }

    public func toggleArchive(_ clip: ClipItem) {
        var copy = clip
        copy.isArchived.toggle()
        updateClip(copy)
    }

    public func moveClip(_ clip: ClipItem, toFolderId folderId: String?) {
        var copy = clip
        copy.folderId = folderId
        copy.isArchived = false
        updateClip(copy)
    }

    public func addHighlight(to clipId: String, quote: String, color: HighlightColor, note: String = "") {
        guard var clip = clips.first(where: { $0.id == clipId }) else { return }
        let item = HighlightItem(clipId: clipId, quote: quote, note: note, color: color)
        clip.highlights.append(item)
        updateClip(clip)
        showToast("已添加高亮标注")
    }

    public func removeHighlight(id highlightId: String, from clipId: String) {
        guard var clip = clips.first(where: { $0.id == clipId }) else { return }
        clip.highlights.removeAll { $0.id == highlightId }
        updateClip(clip)
        vault.searchDB.deleteDocument(key: "highlight:\(highlightId)")
    }

    public func updateHighlightNote(id highlightId: String, clipId: String, note: String) {
        guard var clip = clips.first(where: { $0.id == clipId }),
              let idx = clip.highlights.firstIndex(where: { $0.id == highlightId }) else { return }
        clip.highlights[idx].note = note
        updateClip(clip)
    }

    // MARK: - Folders CRUD

    public func createFolder(name: String, emoji: String = "📁", parentId: String? = nil) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let folder = FolderItem(name: trimmed, emoji: emoji, parentId: parentId, sortOrder: folders.count)
        folders.append(folder)
        vault.saveFolders(folders)
    }

    public func deleteFolder(_ folder: FolderItem) {
        let removedIds = folderAndDescendantIds(for: folder.id)
        folders.removeAll { removedIds.contains($0.id) }
        vault.saveFolders(folders)
        for i in clips.indices {
            if let fid = clips[i].folderId, removedIds.contains(fid) {
                clips[i].folderId = nil
                try? vault.saveClip(clips[i])
            }
        }
        if case .folder(let activeFid) = destination, removedIds.contains(activeFid) {
            destination = .inbox
        }
    }

    // MARK: - Knowledge Docs CRUD & Export

    public func createBlankKnowledgeDoc(title: String = "未命名知识沉淀") -> KnowledgeDoc {
        let fileName = vault.makeKnowledgeFileName(title: title)
        let doc = KnowledgeDoc(fileName: fileName, title: title, tags: ["知识沉淀"], content: "")
        try? vault.saveKnowledgeDoc(doc)
        knowledgeDocs.insert(doc, at: 0)
        activeKnowledgeDocId = doc.id
        destination = .knowledgeBase
        activeClipId = nil
        return doc
    }

    public func saveKnowledgeDoc(_ doc: KnowledgeDoc) {
        var updated = doc
        updated.updatedAt = Date()
        if let idx = knowledgeDocs.firstIndex(where: { $0.id == updated.id }) {
            knowledgeDocs[idx] = updated
        } else {
            knowledgeDocs.insert(updated, at: 0)
        }
        try? vault.saveKnowledgeDoc(updated)
    }

    public func deleteKnowledgeDoc(_ doc: KnowledgeDoc) {
        knowledgeDocs.removeAll { $0.id == doc.id }
        vault.deleteKnowledgeDoc(doc)
        if activeKnowledgeDocId == doc.id {
            activeKnowledgeDocId = knowledgeDocs.first?.id
        }
        showToast("已删除知识文档：\(doc.title)")
    }

    public func saveMarkdownAsKnowledgeDoc(title: String, markdown: String, tags: [String], sourceClips: [ClipItem]) -> KnowledgeDoc {
        let fileName = vault.makeKnowledgeFileName(title: title)
        let doc = KnowledgeDoc(
            fileName: fileName,
            title: title,
            tags: tags,
            sourceClipIds: sourceClips.map(\.id),
            sourceLinks: sourceClips.map(\.url).filter { !$0.isEmpty },
            content: markdown,
            generatedByModel: "\(settings.activeProvider.name) / \(settings.activeModelName)"
        )
        saveKnowledgeDoc(doc)
        showToast("已沉淀至知识库：\(doc.title)")
        return doc
    }

    public func exportKnowledgeDocToUserFolder(_ doc: KnowledgeDoc) {
        let panel = NSOpenPanel()
        panel.title = "选择导出目录（可选择本地文件夹或 iCloud Drive）"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "导出到此处"
        if panel.runModal() == .OK, let dir = panel.url {
            do {
                let dest = try vault.exportKnowledgeDoc(doc, toDirectory: dir)
                showToast("已导出：\(dest.lastPathComponent)")
            } catch {
                showToast("导出失败：\(error.localizedDescription)")
            }
        }
    }

    public func exportClipToUserFolder(_ clip: ClipItem) {
        let panel = NSOpenPanel()
        panel.title = "导出文章与笔记为 Markdown"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "导出到此处"
        if panel.runModal() == .OK, let dir = panel.url {
            do {
                let dest = try vault.exportClipAsMarkdown(clip, toDirectory: dir)
                showToast("已导出：\(dest.lastPathComponent)")
            } catch {
                showToast("导出失败：\(error.localizedDescription)")
            }
        }
    }

    // MARK: - AI Chat & Article Insight

    public func sendAIChatMessage(prompt: String, contextClip: ClipItem?) {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let sessionKey = contextClip?.id ?? "global"
        var history = chatHistories[sessionKey] ?? []
        let userMsg = ChatMessage(role: .user, content: trimmed)
        history.append(userMsg)

        let assistantId = UUID().uuidString
        let placeholder = ChatMessage(id: assistantId, role: .assistant, content: "")
        history.append(placeholder)
        chatHistories[sessionKey] = history

        let provider = settings.activeProvider
        let model = settings.activeModelName
        let apiKey = KeychainService.shared.loadAPIKey(forProviderId: provider.id)

        let systemPrompt = buildChatSystemPrompt(contextClip: contextClip, query: trimmed)

        activeStreamTask?.cancel()
        isAIStreaming = true

        let messagesToSend = Array(history.dropLast()) // exclude empty assistant placeholder
        activeStreamTask = Task {
            do {
                let stream = aiService.streamChat(
                    provider: provider,
                    model: model,
                    apiKey: apiKey,
                    systemPrompt: systemPrompt,
                    messages: messagesToSend
                )
                for try await chunk in stream {
                    if Task.isCancelled { break }
                    if var currentHistory = chatHistories[sessionKey],
                       let idx = currentHistory.firstIndex(where: { $0.id == assistantId }) {
                        currentHistory[idx].content += chunk.contentDelta
                        currentHistory[idx].reasoningContent += chunk.reasoningDelta
                        chatHistories[sessionKey] = currentHistory
                    }
                }
            } catch {
                if var currentHistory = chatHistories[sessionKey],
                   let idx = currentHistory.firstIndex(where: { $0.id == assistantId }) {
                    currentHistory[idx].content += "\n\n⚠️ \(error.localizedDescription)"
                    chatHistories[sessionKey] = currentHistory
                }
            }
            isAIStreaming = false
        }
    }

    public func stopAIStreaming() {
        activeStreamTask?.cancel()
        activeStreamTask = nil
        isAIStreaming = false
    }

    public func clearChatHistory(for sessionKey: String) {
        chatHistories[sessionKey] = []
    }

    public func generateInsight(for clip: ClipItem) async {
        guard !isGeneratingInsight else { return }
        isGeneratingInsight = true
        defer { isGeneratingInsight = false }

        let provider = settings.activeProvider
        let model = settings.activeModelName
        let apiKey = KeychainService.shared.loadAPIKey(forProviderId: provider.id)
        let md = vault.loadArticleMarkdown(for: clip)
        let prompts = AIService.buildInsightPrompts(clip: clip, articleMarkdown: md, existingFolders: folders.map(\.name))

        do {
            let raw = try await aiService.completeOnce(
                provider: provider,
                model: model,
                apiKey: apiKey,
                systemPrompt: prompts.system,
                userPrompt: prompts.user
            )
            let insight = AIService.parseInsightJSON(raw)
            var updated = clip
            updated.aiInsight = insight
            updateClip(updated)
            showToast("AI 快读解读已生成")
        } catch {
            showToast("AI 解读失败：\(error.localizedDescription)")
        }
    }

    private func buildChatSystemPrompt(contextClip: ClipItem?, query: String) -> String {
        if let clip = contextClip {
            let articleMD = String(vault.loadArticleMarkdown(for: clip).prefix(16000))
            let noteMD = String(vault.loadClipNote(for: clip).prefix(3000))
            let highlightsText = clip.highlights.map { "- 「\($0.quote)」\($0.note.isEmpty ? "" : "（批注：\($0.note)）")" }.joined(separator: "\n")
            return """
            你是 ReadBox 的侧边栏 AI 阅读助手，正在陪伴用户阅读以下收藏文章。请用简洁清晰的中文 Markdown 回答用户问题，必要时直接引用原文观点。

            【文章标题】\(clip.title)
            【来源/作者】\(clip.author) (\(clip.domain))
            【用户高亮】
            \(highlightsText.isEmpty ? "暂无" : highlightsText)
            【用户笔记】
            \(noteMD.isEmpty ? "暂无" : noteMD)
            【文章正文】
            \(articleMD)
            """
        } else {
            // Global library RAG-style retrieval using local FTS5 + recent clips
            let hits = vault.searchDB.search(query: query, limit: 8)
            var matchedClips: [ClipItem] = []
            var seen = Set<String>()
            for h in hits where h.kind == .clip || h.kind == .highlight {
                if let c = clips.first(where: { $0.id == h.targetId }), !seen.contains(c.id) {
                    seen.insert(c.id)
                    matchedClips.append(c)
                }
            }
            if matchedClips.count < 5 {
                for c in clips where !c.isArchived && !seen.contains(c.id) {
                    seen.insert(c.id)
                    matchedClips.append(c)
                    if matchedClips.count >= 6 { break }
                }
            }
            let contextBlocks = matchedClips.enumerated().map { idx, c in
                let md = String(vault.loadArticleMarkdown(for: c).prefix(2200))
                return """
                [来源\(idx + 1)] 《\(c.title)》(\(c.domain) | 标签：\(c.tags.joined(separator: ", ")))
                摘要：\(c.excerpt)
                节选：\(md)
                """
            }.joined(separator: "\n\n---\n\n")

            return """
            你是 ReadBox 的全库 AI 知识助手。用户可以让你查找历史收藏、对比观点、总结本周阅读或提炼知识库大纲。
            以下是从用户本地阅读库中检索到的相关收藏内容（共 \(clips.count) 篇总收藏）：

            \(contextBlocks)

            请基于上述收藏资料回答，引用观点时注明 `[来源N]` 与文章标题。
            """
        }
    }

    // MARK: - URL Scheme Handling (readbox://save?url=...)

    public func handleIncomingURL(_ url: URL) {
        guard url.scheme?.lowercased() == "readbox" else { return }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        if url.host == "save",
           let targetURL = components?.queryItems?.first(where: { $0.name == "url" })?.value,
           !targetURL.isEmpty {
            Task { await addClipFromURL(targetURL) }
        }
    }
}
