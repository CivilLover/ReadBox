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
    case untagged
    case folder(String)
    case tag(String)
}

public enum LibraryViewMode: String, CaseIterable {
    case cards = "详情卡片"
    case list = "简洁列表"
}

public enum LibrarySortOrder: String, CaseIterable {
    case newest = "按时间（从新到旧）"
    case oldest = "按时间（从旧到新）"
    case updated = "按更新时间"
    case title = "按名称（A→Z）"
    case highlights = "按标注数量"
}

public enum RightPanelTab: String, CaseIterable {
    case ai = "AI 助手"
    case note = "笔记"
    case highlights = "标注"
}

public enum GlobalSearchMode: Hashable {
    case overview
    case allResults
    case fullText
    case annotations
    case archived
    case aiAsk
}

public struct GlobalSearchClipHit: Identifiable, Hashable {
    public var id: String { clip.id }
    public var clip: ClipItem
    public var snippet: String
    public var isFullTextMatch: Bool
}

public struct GlobalSearchHighlightHit: Identifiable, Hashable {
    public var id: String { highlight.id }
    public var clip: ClipItem
    public var highlight: HighlightItem
}

public struct GlobalSearchKnowledgeHit: Identifiable, Hashable {
    public var id: String { doc.id }
    public var doc: KnowledgeDoc
    public var snippet: String
}

public struct GlobalSearchSnapshot {
    public var query: String
    public var matchingFolders: [FolderItem]
    public var matchingTags: [(tag: TagItem, count: Int)]
    public var activeClipHits: [GlobalSearchClipHit]
    public var fullTextClipHits: [GlobalSearchClipHit]
    public var highlightHits: [GlobalSearchHighlightHit]
    public var archivedClipHits: [GlobalSearchClipHit]
    public var knowledgeHits: [GlobalSearchKnowledgeHit]

    public var totalResultCount: Int {
        matchingFolders.count + matchingTags.count + activeClipHits.count + highlightHits.count + knowledgeHits.count + archivedClipHits.count
    }

    public static let empty = GlobalSearchSnapshot(
        query: "",
        matchingFolders: [],
        matchingTags: [],
        activeClipHits: [],
        fullTextClipHits: [],
        highlightHits: [],
        archivedClipHits: [],
        knowledgeHits: []
    )
}

@MainActor
public final class AppState: ObservableObject {
    public let vault: VaultManager
    public let clipper = WebClipperService()
    public let aiService = AIService()
    public let clipboardMonitor = ClipboardMonitor()
    public let globalHotKeyManager = GlobalHotKeyManager()
    private var floatingClipController: FloatingQuickClipController?
    private var registeredHotKeySignature: (Bool, UInt32, UInt32)?

    @Published public var settings: AppSettings
    @Published public var folders: [FolderItem] = []
    @Published public var savedTags: [TagItem] = []
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
    @Published public var quickSearchInitialMode: GlobalSearchMode = .overview
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
    @Published public var isFloatingClipVisible: Bool = false
    @Published public var hotKeyRegistrationError: String? = nil
    private var toastTask: Task<Void, Never>?
    private var externalVaultObserver: NSObjectProtocol?
    private var externalReloadTask: Task<Void, Never>?
    private let persistSettings: Bool

    public init(vaultPath: String? = nil, persistSettings: Bool = true) {
        self.persistSettings = persistSettings
        let initialVault = VaultManager(vaultPath: vaultPath)
        let loadedSettings: AppSettings
        if persistSettings {
            let loaded = initialVault.loadSettings()
            if vaultPath == nil && loaded.vaultPath != initialVault.vaultURL.path {
                initialVault.switchVault(to: URL(fileURLWithPath: loaded.vaultPath, isDirectory: true))
            }
            loadedSettings = loaded
        } else {
            loadedSettings = AppSettings(vaultPath: initialVault.vaultURL.path, clipboardMonitorEnabled: false)
        }
        self.vault = initialVault
        self.settings = loadedSettings
        self.reloadVaultData()
        if persistSettings && loadedSettings.clipboardMonitorEnabled {
            self.clipboardMonitor.start()
        }
        if persistSettings {
            self.floatingClipController = FloatingQuickClipController(appState: self)
            DispatchQueue.main.async { [weak self] in
                self?.syncFloatingCaptureSystem()
            }
            self.externalVaultObserver = DistributedNotificationCenter.default().addObserver(
                forName: .readBoxVaultDidChange,
                object: nil,
                queue: .main
            ) { [weak self] note in
                let changedPath = note.object as? String
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let changedPath, !changedPath.isEmpty, changedPath != self.vault.vaultURL.path {
                        return
                    }
                    self.scheduleExternalVaultReload()
                }
            }
        }
    }

    private func scheduleExternalVaultReload() {
        externalReloadTask?.cancel()
        externalReloadTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard let self, !Task.isCancelled else { return }
            self.reloadVaultData()
        }
    }

    public func refreshMCPAccessKey() {
        settings.mcpAccessKey = AppSettings.generateMCPAccessKey()
        saveSettingsSilently()
        showToast("已刷新 MCP 访问密钥，请更新客户端配置")
    }

    public func reloadVaultData() {
        vault.ensureStructure()
        vault.seedWelcomeContentIfEmpty()
        folders = vault.loadFolders()
        savedTags = vault.loadTags()
        clips = vault.loadAllClips()
        knowledgeDocs = vault.loadAllKnowledgeDocs()
        syncSavedTagsFromClips()
        vault.rebuildSearchIndex(clips: clips, docs: knowledgeDocs)
        if activeKnowledgeDocId == nil {
            activeKnowledgeDocId = knowledgeDocs.first?.id
        }
    }

    private func syncSavedTagsFromClips() {
        var existingNames = Set(savedTags.map(\.name))
        var changed = false
        for clip in clips {
            for t in clip.tags where !existingNames.contains(t) {
                existingNames.insert(t)
                savedTags.append(TagItem(name: t, sortOrder: savedTags.count, createdAt: clip.createdAt))
                changed = true
            }
        }
        if changed {
            vault.saveTags(savedTags)
        }
    }

    public func saveSettings() {
        if persistSettings {
            vault.saveSettings(settings)
        }
        if persistSettings && settings.clipboardMonitorEnabled {
            clipboardMonitor.start()
        } else {
            clipboardMonitor.stop()
        }
        if persistSettings {
            syncFloatingCaptureSystem()
        }
    }

    public func saveSettingsSilently() {
        if persistSettings {
            vault.saveSettings(settings)
        }
    }

    // MARK: - Floating Quick-Clip Panel & Global HotKey

    public var floatingHotKeyDisplayString: String {
        GlobalHotKeyFormatter.displayString(
            keyCode: settings.floatingCapture.hotKeyCode,
            carbonModifiers: settings.floatingCapture.hotKeyModifiers
        )
    }

    public func toggleFloatingClipPanel() {
        guard persistSettings else { return }
        if floatingClipController == nil {
            floatingClipController = FloatingQuickClipController(appState: self)
        }
        floatingClipController?.toggleVisibility()
    }

    public func showFloatingClipPanel() {
        guard persistSettings else { return }
        if floatingClipController == nil {
            floatingClipController = FloatingQuickClipController(appState: self)
        }
        floatingClipController?.showAndFocus()
    }

    public func hideFloatingClipPanel() {
        floatingClipController?.hide()
    }

    public func suspendGlobalHotKey() {
        globalHotKeyManager.unregister()
        registeredHotKeySignature = nil
    }

    public func syncFloatingCaptureSystem() {
        guard persistSettings else { return }
        let fc = settings.floatingCapture
        let desiredSig = (fc.globalHotKeyEnabled, fc.hotKeyCode, fc.hotKeyModifiers)
        let needsHotKeyUpdate = registeredHotKeySignature.map { $0 != desiredSig } ?? true

        if needsHotKeyUpdate {
            registeredHotKeySignature = desiredSig
            if fc.globalHotKeyEnabled {
                let ok = globalHotKeyManager.register(
                    keyCode: fc.hotKeyCode,
                    modifiers: fc.hotKeyModifiers
                ) { [weak self] in
                    self?.floatingClipController?.toggleFromHotKey()
                }
                hotKeyRegistrationError = ok ? nil : "快捷键 \(floatingHotKeyDisplayString) 可能与其他应用冲突，请换一个组合键"
            } else {
                globalHotKeyManager.unregister()
                hotKeyRegistrationError = nil
            }
        }

        floatingClipController?.syncWithSettings()
    }

    public func switchVaultDirectory(to url: URL) {
        vault.switchVault(to: url)
        settings.vaultPath = url.path
        if persistSettings {
            vault.saveSettings(settings)
        }
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

    public var allTagsWithCount: [(tag: TagItem, count: Int)] {
        var counts: [String: Int] = [:]
        for clip in clips where !clip.isArchived {
            for t in clip.tags {
                counts[t, default: 0] += 1
            }
        }
        let merged: [(tag: TagItem, count: Int)] = savedTags.map { ($0, counts[$0.name] ?? 0) }
        switch settings.tagSortOrder {
        case .custom:
            return merged.sorted { $0.tag.sortOrder < $1.tag.sortOrder }
        case .name:
            return merged.sorted { $0.tag.name.localizedStandardCompare($1.tag.name) == .orderedAscending }
        case .createdAt:
            return merged.sorted { $0.tag.createdAt > $1.tag.createdAt }
        case .count:
            return merged.sorted { $0.count > $1.count || ($0.count == $1.count && $0.tag.name.localizedStandardCompare($1.tag.name) == .orderedAscending) }
        }
    }

    public func sortedFolders(parentId: String?) -> [FolderItem] {
        let siblings = folders.filter { $0.parentId == parentId }
        switch settings.folderSortOrder {
        case .custom:
            return siblings.sorted { $0.sortOrder < $1.sortOrder }
        case .name:
            return siblings.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .createdAt:
            return siblings.sorted { $0.createdAt > $1.createdAt }
        case .count:
            return siblings.sorted {
                let c0 = countForDestination(.folder($0.id))
                let c1 = countForDestination(.folder($1.id))
                return c0 > c1 || (c0 == c1 && $0.name.localizedStandardCompare($1.name) == .orderedAscending)
            }
        }
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
        case .untagged:
            result = clips.filter { !$0.isArchived && $0.tags.isEmpty }
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
        case .updated:
            result.sort { $0.updatedAt > $1.updatedAt }
        case .title:
            result.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .highlights:
            result.sort { $0.highlights.count > $1.highlights.count || ($0.highlights.count == $1.highlights.count && $0.createdAt > $1.createdAt) }
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
        case .untagged: return clips.filter { !$0.isArchived && $0.tags.isEmpty }.count
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

    @discardableResult
    public func addClipFromURL(_ rawURL: String, folderId: String? = nil, tags: [String] = []) async -> ClipItem? {
        let trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

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
            if parsed.needsManualWebExtract {
                showToast("已保存链接（原站限流/需登录）：打开后点「原网页 → 提取正文」即可离线保存")
            } else {
                showToast("已收藏：\(finalClip.title)")
            }

            if settings.autoInsightOnSave && !parsed.needsManualWebExtract {
                Task { await generateInsight(for: finalClip) }
            }
            return finalClip
        } catch {
            showToast("收藏失败：\(error.localizedDescription)")
            return nil
        }
    }

    /// Re-extracts clean offline article & localized images from live HTML rendered in the Reader's「原网页」WebView.
    public func reextractClip(_ clip: ClipItem, fromRenderedHTML html: String) async -> Bool {
        guard let url = URL(string: clip.url), !clip.url.isEmpty else { return false }
        isClipping = true
        defer { isClipping = false }

        let assetsDir = vault.clipAssetsURL(for: clip)
        let parsed = await clipper.parseRenderedHTML(html, sourceURL: url, assetsDirectory: assetsDir)
        if parsed.needsManualWebExtract {
            showToast("页面尚未加载出正文（请先完成站点登录/验证后再点提取）")
            return false
        }

        var updated = clip
        updated.title = parsed.title
        updated.author = parsed.author
        updated.excerpt = parsed.excerpt
        updated.coverImageName = parsed.coverImageName ?? updated.coverImageName
        updated.updatedAt = Date()

        do {
            try vault.saveClip(
                updated,
                articleHTML: parsed.cleanedHTML,
                articleMarkdown: parsed.markdown,
                snapshotHTML: parsed.snapshotHTML,
                noteMarkdown: nil
            )
            if let idx = clips.firstIndex(where: { $0.id == updated.id }) {
                clips[idx] = updated
            }
            showToast("已成功提取离线正文：\(updated.title)")
            return true
        } catch {
            showToast("保存提取结果失败：\(error.localizedDescription)")
            return false
        }
    }

    public func moveClips(ids: [String], toFolderId folderId: String?) {
        var movedCount = 0
        for id in ids {
            if let c = clips.first(where: { $0.id == id }) {
                moveClip(c, toFolderId: folderId)
                movedCount += 1
            }
        }
        guard movedCount > 0 else { return }
        if let fid = folderId, let f = folders.first(where: { $0.id == fid }) {
            showToast("已将 \(movedCount) 篇移入「\(f.emoji) \(f.name)」")
        } else {
            showToast("已将 \(movedCount) 篇移回收集箱")
        }
    }

    public func starClips(ids: [String]) {
        var count = 0
        for id in ids {
            if var c = clips.first(where: { $0.id == id }), !c.isStarred {
                c.isStarred = true
                updateClip(c)
                count += 1
            }
        }
        if count > 0 { showToast("已为 \(count) 篇收藏添加星标") }
    }

    public func archiveClips(ids: [String]) {
        var count = 0
        for id in ids {
            if var c = clips.first(where: { $0.id == id }), !c.isArchived {
                c.isArchived = true
                updateClip(c)
                count += 1
            }
        }
        if count > 0 { showToast("已归档 \(count) 篇收藏") }
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
        syncSavedTagsFromClips()
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

    // MARK: - Tags CRUD

    public func createTag(name: String) {
        let trimmed = name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard !trimmed.isEmpty else { return }
        if savedTags.contains(where: { $0.name == trimmed }) {
            showToast("标签 #\(trimmed) 已存在")
            return
        }
        let item = TagItem(name: trimmed, sortOrder: savedTags.count, createdAt: Date())
        savedTags.append(item)
        vault.saveTags(savedTags)
        showToast("已创建标签 #\(trimmed)")
    }

    public func renameTag(_ tag: TagItem, to newName: String) {
        let trimmed = newName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard !trimmed.isEmpty, trimmed != tag.name else { return }
        let oldName = tag.name
        if let idx = savedTags.firstIndex(where: { $0.id == tag.id }) {
            savedTags[idx].name = trimmed
            vault.saveTags(savedTags)
        }
        for i in clips.indices {
            if clips[i].tags.contains(oldName) {
                clips[i].tags = clips[i].tags.map { $0 == oldName ? trimmed : $0 }
                try? vault.saveClip(clips[i])
            }
        }
        if case .tag(let active) = destination, active == oldName {
            destination = .tag(trimmed)
        }
        showToast("已将标签重命名为 #\(trimmed)")
    }

    public func deleteTag(_ tag: TagItem) {
        savedTags.removeAll { $0.id == tag.id }
        vault.saveTags(savedTags)
        for i in clips.indices {
            if clips[i].tags.contains(tag.name) {
                clips[i].tags.removeAll { $0 == tag.name }
                try? vault.saveClip(clips[i])
            }
        }
        if case .tag(let active) = destination, active == tag.name {
            destination = .all
        }
        showToast("已删除标签 #\(tag.name)")
    }

    public func addTag(_ tagName: String, toClipIds ids: [String]) {
        var updatedCount = 0
        for id in ids {
            if var c = clips.first(where: { $0.id == id }), !c.tags.contains(tagName) {
                c.tags.append(tagName)
                updateClip(c)
                updatedCount += 1
            }
        }
        if updatedCount > 0 {
            if !savedTags.contains(where: { $0.name == tagName }) {
                savedTags.append(TagItem(name: tagName, sortOrder: savedTags.count, createdAt: Date()))
                vault.saveTags(savedTags)
            }
            showToast("已为 \(updatedCount) 篇收藏添加标签 #\(tagName)")
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

    // MARK: - Global Search & AI Search Engine

    public func openGlobalSearch(initialMode: GlobalSearchMode = .overview) {
        quickSearchInitialMode = initialMode
        showQuickSearchOverlay = true
    }

    /// Unified global search across folders, tags, active collections, full-text articles,
    /// highlights/annotations, knowledge base docs, and archived clips.
    public func runGlobalSearch(query rawQuery: String) -> GlobalSearchSnapshot {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return .empty }

        let matchingFolders = folders.filter {
            $0.name.localizedCaseInsensitiveContains(query) || $0.emoji.contains(query)
        }

        let matchingTags = allTagsWithCount.filter {
            $0.tag.name.localizedCaseInsensitiveContains(query)
        }

        let clipById = Dictionary(uniqueKeysWithValues: clips.map { ($0.id, $0) })
        let ftsClipHits = vault.searchDB.search(query: query, kindFilter: .clip, limit: 100)
        var ftsSnippetByClipId: [String: String] = [:]
        for hit in ftsClipHits {
            let cleaned = hit.snippet
                .replacingOccurrences(of: "【", with: "")
                .replacingOccurrences(of: "】", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty {
                ftsSnippetByClipId[hit.targetId] = cleaned
            }
        }

        var activeHits: [GlobalSearchClipHit] = []
        var seenActive = Set<String>()
        var archivedHits: [GlobalSearchClipHit] = []
        var seenArchived = Set<String>()

        // 1. Prioritize direct title / excerpt / tag / author / domain matches in memory
        for clip in clips {
            let inMeta = clip.title.localizedCaseInsensitiveContains(query)
                || clip.excerpt.localizedCaseInsensitiveContains(query)
                || clip.author.localizedCaseInsensitiveContains(query)
                || clip.domain.localizedCaseInsensitiveContains(query)
                || clip.tags.contains(where: { $0.localizedCaseInsensitiveContains(query) })

            guard inMeta else { continue }
            let snippet = Self.makeSearchSnippet(
                preferred: [ftsSnippetByClipId[clip.id], clip.excerpt],
                keyword: query
            )
            let hit = GlobalSearchClipHit(clip: clip, snippet: snippet, isFullTextMatch: ftsSnippetByClipId[clip.id] != nil)
            if clip.isArchived {
                if seenArchived.insert(clip.id).inserted { archivedHits.append(hit) }
            } else {
                if seenActive.insert(clip.id).inserted { activeHits.append(hit) }
            }
        }

        // 2. Append FTS5 full-text / note body hits (for both active and archived)
        var fullTextHits: [GlobalSearchClipHit] = []
        var seenFullText = Set<String>()

        for fts in ftsClipHits {
            guard let clip = clipById[fts.targetId] else { continue }
            let snippet = Self.makeSearchSnippet(
                preferred: [ftsSnippetByClipId[clip.id], clip.excerpt],
                keyword: query
            )
            let hit = GlobalSearchClipHit(clip: clip, snippet: snippet, isFullTextMatch: true)
            if clip.isArchived {
                if seenArchived.insert(clip.id).inserted { archivedHits.append(hit) }
            } else {
                if seenActive.insert(clip.id).inserted { activeHits.append(hit) }
                if seenFullText.insert(clip.id).inserted { fullTextHits.append(hit) }
            }
        }

        // Ensure active meta hits also appear in full-text results if not already present
        for hit in activeHits where seenFullText.insert(hit.clip.id).inserted {
            fullTextHits.append(hit)
        }

        // 3. Highlight / Annotation search (direct scan guarantees CJK substrings & exact highlightId)
        let highlightHits: [GlobalSearchHighlightHit] = allHighlights.compactMap { pair in
            let matches = pair.highlight.quote.localizedCaseInsensitiveContains(query)
                || pair.highlight.note.localizedCaseInsensitiveContains(query)
                || pair.clip.title.localizedCaseInsensitiveContains(query)
            return matches ? GlobalSearchHighlightHit(clip: pair.clip, highlight: pair.highlight) : nil
        }

        // 4. Knowledge Base document hits
        let ftsKnowledgeHits = vault.searchDB.search(query: query, kindFilter: .knowledge, limit: 40)
        var knowledgeSnippetById: [String: String] = [:]
        for hit in ftsKnowledgeHits {
            knowledgeSnippetById[hit.targetId] = hit.snippet
                .replacingOccurrences(of: "【", with: "")
                .replacingOccurrences(of: "】", with: "")
        }

        var knowledgeHits: [GlobalSearchKnowledgeHit] = []
        var seenKnowledge = Set<String>()
        for doc in knowledgeDocs {
            let matches = knowledgeSnippetById[doc.id] != nil
                || doc.title.localizedCaseInsensitiveContains(query)
                || doc.content.localizedCaseInsensitiveContains(query)
                || doc.tags.contains(where: { $0.localizedCaseInsensitiveContains(query) })
            guard matches, seenKnowledge.insert(doc.id).inserted else { continue }
            let snippet = Self.makeSearchSnippet(
                preferred: [knowledgeSnippetById[doc.id], doc.content],
                keyword: query
            )
            knowledgeHits.append(GlobalSearchKnowledgeHit(doc: doc, snippet: snippet))
        }

        return GlobalSearchSnapshot(
            query: query,
            matchingFolders: matchingFolders,
            matchingTags: matchingTags,
            activeClipHits: activeHits,
            fullTextClipHits: fullTextHits,
            highlightHits: highlightHits,
            archivedClipHits: archivedHits,
            knowledgeHits: knowledgeHits
        )
    }

    public static func makeSearchSnippet(preferred candidates: [String?], keyword: String) -> String {
        for raw in candidates {
            guard let text = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { continue }
            let compact = text
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "  ", with: " ")
            if let range = compact.range(of: keyword, options: .caseInsensitive) {
                let start = compact.index(range.lowerBound, offsetBy: -24, limitedBy: compact.startIndex) ?? compact.startIndex
                let end = compact.index(range.upperBound, offsetBy: 60, limitedBy: compact.endIndex) ?? compact.endIndex
                let prefix = start > compact.startIndex ? "…" : ""
                let suffix = end < compact.endIndex ? "…" : ""
                return prefix + String(compact[start..<end]) + suffix
            }
        }
        for raw in candidates {
            if let text = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                let compact = text.replacingOccurrences(of: "\n", with: " ")
                return String(compact.prefix(90))
            }
        }
        return ""
    }

    /// Retrieves relevant clips & knowledge docs for Global AI Search and builds the RAG system prompt.
    public func buildGlobalAISearchContext(for query: String) -> (systemPrompt: String, citedClips: [ClipItem], citedDocs: [KnowledgeDoc]) {
        let snapshot = runGlobalSearch(query: query)
        var citedClips: [ClipItem] = []
        var seenClipIds = Set<String>()

        for hit in snapshot.activeClipHits {
            if seenClipIds.insert(hit.clip.id).inserted {
                citedClips.append(hit.clip)
                if citedClips.count >= 6 { break }
            }
        }
        if citedClips.count < 6 {
            for hit in snapshot.highlightHits {
                if seenClipIds.insert(hit.clip.id).inserted {
                    citedClips.append(hit.clip)
                    if citedClips.count >= 6 { break }
                }
            }
        }
        if citedClips.count < 4 {
            for clip in clips where !clip.isArchived && seenClipIds.insert(clip.id).inserted {
                citedClips.append(clip)
                if citedClips.count >= 5 { break }
            }
        }

        let citedDocs = Array(snapshot.knowledgeHits.prefix(3).map(\.doc))

        var blocks: [String] = []
        for (idx, clip) in citedClips.enumerated() {
            let md = String(vault.loadArticleMarkdown(for: clip).prefix(2000))
            let hl = clip.highlights.prefix(4).map { "「\($0.quote)」" }.joined(separator: "；")
            blocks.append("""
            [来源\(idx + 1)] 《\(clip.title)》(\(clip.domain) | 收藏夹：\(folderName(for: clip.folderId) ?? "收集箱") | 标签：\(clip.tags.joined(separator: ", ")))
            摘要：\(clip.excerpt)
            标注：\(hl.isEmpty ? "无" : hl)
            正文节选：\(md)
            """)
        }
        for (idx, doc) in citedDocs.enumerated() {
            let content = String(doc.content.prefix(1500))
            blocks.append("""
            [知识库\(idx + 1)] 《\(doc.title)》(标签：\(doc.tags.joined(separator: ", ")))
            内容节选：\(content)
            """)
        }

        let folderSummary = folders.map { "\($0.emoji)\($0.name)" }.joined(separator: "、")
        let systemPrompt = """
        你是 ReadBox AI 搜索助手。用户正在通过全局搜索栏向自己的本地阅读收藏库提问。
        请优先基于下方检索到的收藏文章、高亮标注与知识沉淀文档作答，用清晰简洁的中文 Markdown 给出直接答案；引用资料时请标注来源名称如《文章标题》。如果收藏库中没有直接相关内容，也请明确说明「收藏库中暂未直接涉及」并结合你的通用知识给予有帮助的回答。

        【用户收藏库概览】共 \(clips.count) 篇收藏，\(allHighlights.count) 条标注，\(knowledgeDocs.count) 篇知识文档；收藏夹：\(folderSummary.isEmpty ? "默认收集箱" : folderSummary)。

        【检索到的相关资料】
        \(blocks.isEmpty ? "（当前收藏库暂无内容）" : blocks.joined(separator: "\n\n---\n\n"))
        """

        return (systemPrompt, citedClips, citedDocs)
    }

    /// Transfers an inline Global AI Search Q&A into the Global AI Side Drawer so the user can keep chatting.
    public func handoffAISearchToGlobalDrawer(question: String, answer: String, reasoning: String, citedTitles: [String]) {
        var history = chatHistories["global"] ?? []
        history.append(ChatMessage(role: .user, content: question))
        if !answer.isEmpty {
            history.append(ChatMessage(role: .assistant, content: answer, reasoningContent: reasoning, citedClipTitles: citedTitles))
        }
        chatHistories["global"] = history
        activeClipId = nil
        showQuickSearchOverlay = false
        withAnimation(.easeInOut(duration: 0.2)) {
            showGlobalAIDrawer = true
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
