import Foundation

public extension Notification.Name {
    /// Posted via `DistributedNotificationCenter` whenever the external MCP server mutates the vault,
    /// so a running ReadBox GUI instance reloads immediately without restart.
    static let readBoxVaultDidChange = Notification.Name("com.readbox.macos.vaultDidChange")
}

/// Core JSON-RPC 2.0 MCP handler for ReadBox.
/// Pure Swift, zero third-party dependencies, fully unit-testable without stdio.
public final class ReadBoxMCPHandler {
    public let vault: VaultManager
    public let clipper: WebClipperService
    private let providedToken: String
    private let expectedTokenProvider: () -> String
    private let notifyVaultChange: Bool

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    public init(
        vault: VaultManager,
        providedToken: String,
        expectedTokenProvider: @escaping () -> String,
        clipper: WebClipperService = WebClipperService(),
        notifyVaultChange: Bool = true
    ) {
        self.vault = vault
        self.providedToken = providedToken.trimmingCharacters(in: .whitespacesAndNewlines)
        self.expectedTokenProvider = expectedTokenProvider
        self.clipper = clipper
        self.notifyVaultChange = notifyVaultChange
    }

    // MARK: - JSON-RPC Entrypoint

    /// Handles a single JSON-RPC 2.0 message line and returns an optional response dictionary
    /// (`nil` for notifications that expect no reply).
    public func handleMessage(_ request: [String: Any]) async -> [String: Any]? {
        guard let method = request["method"] as? String else {
            if let id = request["id"] {
                return jsonRPCError(id: id, code: -32600, message: "Invalid Request: missing method")
            }
            return nil
        }

        let id = request["id"]
        let params = request["params"] as? [String: Any] ?? [:]

        switch method {
        case "initialize":
            let clientVersion = (params["protocolVersion"] as? String) ?? "2024-11-05"
            let result: [String: Any] = [
                "protocolVersion": clientVersion,
                "capabilities": [
                    "tools": [
                        "listChanged": false
                    ]
                ],
                "serverInfo": [
                    "name": "readbox",
                    "version": "1.0.0"
                ]
            ]
            return id.map { jsonRPCResult(id: $0, result: result) }

        case "notifications/initialized", "notifications/cancelled":
            return nil

        case "ping":
            return id.map { jsonRPCResult(id: $0, result: [:]) }

        case "tools/list":
            let result: [String: Any] = [
                "tools": Self.toolDefinitions
            ]
            return id.map { jsonRPCResult(id: $0, result: result) }

        case "tools/call":
            guard let id else { return nil }
            // Verify shared MCP access key dynamically so key refresh in ReadBox takes effect immediately.
            let expected = expectedTokenProvider().trimmingCharacters(in: .whitespacesAndNewlines)
            guard !expected.isEmpty && !providedToken.isEmpty && providedToken == expected else {
                return jsonRPCResult(
                    id: id,
                    result: toolError("鉴权失败：MCP 密钥无效或已在 ReadBox 中刷新。请在 ReadBox「偏好设置 → MCP 集成」中复制最新的 --token 配置。")
                )
            }

            guard let toolName = params["name"] as? String else {
                return jsonRPCError(id: id, code: -32602, message: "Missing tool name")
            }
            let args = params["arguments"] as? [String: Any] ?? [:]
            let toolResult = await executeTool(name: toolName, args: args)
            return jsonRPCResult(id: id, result: toolResult)

        default:
            if let id {
                return jsonRPCError(id: id, code: -32601, message: "Method not found: \(method)")
            }
            return nil
        }
    }

    /// Convenience helper for handling a raw UTF-8 JSON line.
    public func handleLine(_ line: String) async -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let data = trimmed.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return encodeJSON(jsonRPCError(id: NSNull(), code: -32700, message: "Parse error"))
        }
        guard let response = await handleMessage(obj) else { return nil }
        return encodeJSON(response)
    }

    // MARK: - Tool Dispatcher

    private func executeTool(name: String, args: [String: Any]) async -> [String: Any] {
        switch name {
        case "list_clips":
            return toolListClips(args)
        case "search_clips":
            return toolSearchClips(args)
        case "get_clip":
            return toolGetClip(args)
        case "clip_url":
            return await toolClipURL(args)
        case "save_clip_markdown":
            return toolSaveClipMarkdown(args)
        case "update_clip":
            return toolUpdateClip(args)
        case "delete_clip":
            return toolDeleteClip(args)
        case "set_clip_insight":
            return toolSetClipInsight(args)
        case "add_highlight":
            return toolAddHighlight(args)
        case "update_highlight":
            return toolUpdateHighlight(args)
        case "delete_highlight":
            return toolDeleteHighlight(args)
        case "update_clip_note":
            return toolUpdateClipNote(args)
        case "list_folders_and_tags":
            return toolListFoldersAndTags()
        case "manage_folder":
            return toolManageFolder(args)
        case "manage_tag":
            return toolManageTag(args)
        case "list_knowledge_docs":
            return toolListKnowledgeDocs(args)
        case "get_knowledge_doc":
            return toolGetKnowledgeDoc(args)
        case "save_knowledge_doc":
            return toolSaveKnowledgeDoc(args)
        case "delete_knowledge_doc":
            return toolDeleteKnowledgeDoc(args)
        default:
            return toolError("未知工具: \(name)")
        }
    }

    // MARK: - Clip Tools

    private func toolListClips(_ args: [String: Any]) -> [String: Any] {
        var clips = vault.loadAllClips()

        if let folderId = args["folder_id"] as? String {
            if folderId == "inbox" || folderId.isEmpty {
                clips = clips.filter { $0.folderId == nil && !$0.isArchived }
            } else {
                clips = clips.filter { $0.folderId == folderId }
            }
        }
        if let tag = args["tag"] as? String, !tag.isEmpty {
            clips = clips.filter { $0.tags.contains(tag) }
        }
        if let isStarred = args["is_starred"] as? Bool {
            clips = clips.filter { $0.isStarred == isStarred }
        }
        if let isRead = args["is_read"] as? Bool {
            clips = clips.filter { $0.isRead == isRead }
        }
        if let isArchived = args["is_archived"] as? Bool {
            clips = clips.filter { $0.isArchived == isArchived }
        } else if args["folder_id"] == nil {
            // Default to non-archived unless caller explicitly requests archived
            clips = clips.filter { !$0.isArchived }
        }

        let limit = max(1, min(200, (args["limit"] as? Int) ?? 30))
        let sliced = Array(clips.prefix(limit))
        let foldersById = Dictionary(uniqueKeysWithValues: vault.loadFolders().map { ($0.id, $0.name) })

        let items: [[String: Any]] = sliced.map { clipSummaryDict($0, foldersById: foldersById) }
        return toolSuccessJSON([
            "total": clips.count,
            "returned": items.count,
            "clips": items
        ])
    }

    private func toolSearchClips(_ args: [String: Any]) -> [String: Any] {
        guard let query = (args["query"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !query.isEmpty else {
            return toolError("缺少搜索关键词 query")
        }
        let limit = max(1, min(100, (args["limit"] as? Int) ?? 20))
        let clips = vault.loadAllClips()
        let docs = vault.loadAllKnowledgeDocs()

        // Ensure FTS5 index is up to date before searching
        vault.rebuildSearchIndex(clips: clips, docs: docs)
        let ftsHits = vault.searchDB.search(query: query, limit: limit)

        let clipsById = Dictionary(uniqueKeysWithValues: clips.map { ($0.id, $0) })
        let docsById = Dictionary(uniqueKeysWithValues: docs.map { ($0.id, $0) })

        var results: [[String: Any]] = []
        var seenKeys = Set<String>()
        for hit in ftsHits {
            let dedupKey = "\(hit.kind.rawValue):\(hit.targetId)"
            guard !seenKeys.contains(dedupKey) else { continue }
            seenKeys.insert(dedupKey)

            var entry: [String: Any] = [
                "kind": hit.kind.rawValue,
                "id": hit.targetId,
                "title": hit.title,
                "snippet": hit.snippet
            ]
            if hit.kind == .clip || hit.kind == .highlight, let c = clipsById[hit.targetId] {
                entry["url"] = c.url
                entry["tags"] = c.tags
                entry["folder_id"] = c.folderId ?? ""
            } else if hit.kind == .knowledge, let d = docsById[hit.targetId] {
                entry["tags"] = d.tags
                entry["file_name"] = d.fileName
            }
            results.append(entry)
        }

        // Substring fallback for CJK partial matches that unicode61 tokenizer might miss
        if results.count < limit {
            let lowered = query.lowercased()
            for clip in clips {
                if results.count >= limit { break }
                let key = "clip:\(clip.id)"
                guard !seenKeys.contains(key) else { continue }
                if clip.title.lowercased().contains(lowered)
                    || clip.excerpt.lowercased().contains(lowered)
                    || clip.tags.contains(where: { $0.lowercased().contains(lowered) }) {
                    seenKeys.insert(key)
                    results.append([
                        "kind": "clip",
                        "id": clip.id,
                        "title": clip.title,
                        "snippet": clip.excerpt,
                        "url": clip.url,
                        "tags": clip.tags,
                        "folder_id": clip.folderId ?? ""
                    ])
                }
            }
        }

        return toolSuccessJSON([
            "query": query,
            "count": results.count,
            "results": results
        ])
    }

    private func toolGetClip(_ args: [String: Any]) -> [String: Any] {
        guard let clipId = args["clip_id"] as? String, !clipId.isEmpty else {
            return toolError("缺少参数 clip_id")
        }
        guard let clip = vault.loadAllClips().first(where: { $0.id == clipId }) else {
            return toolError("未找到收藏: \(clipId)")
        }

        let includeArticle = (args["include_article"] as? Bool) ?? true
        let foldersById = Dictionary(uniqueKeysWithValues: vault.loadFolders().map { ($0.id, $0.name) })
        var payload = clipSummaryDict(clip, foldersById: foldersById)
        payload["note_markdown"] = vault.loadClipNote(for: clip)
        payload["highlights"] = clip.highlights.map { highlightDict($0) }
        if let insight = clip.aiInsight {
            payload["ai_insight"] = insightDict(insight)
        }
        if includeArticle {
            payload["article_markdown"] = vault.loadArticleMarkdown(for: clip)
        }
        return toolSuccessJSON(payload)
    }

    private func toolClipURL(_ args: [String: Any]) async -> [String: Any] {
        guard let rawURL = (args["url"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawURL.isEmpty else {
            return toolError("缺少参数 url")
        }
        let normalized = (rawURL.hasPrefix("http://") || rawURL.hasPrefix("https://")) ? rawURL : "https://\(rawURL)"
        guard URL(string: normalized) != nil else {
            return toolError("无效的 URL: \(rawURL)")
        }

        let folderId = resolveFolderId(args["folder_id"] as? String, folderName: args["folder_name"] as? String)
        let extraTags = stringArray(args["tags"])

        let clipId = UUID().uuidString
        let tempDir = vault.clipsRootURL.appendingPathComponent("tmp-\(clipId.prefix(8))", isDirectory: true)
        let tempAssets = tempDir.appendingPathComponent("assets", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempAssets, withIntermediateDirectories: true)

        do {
            let result = try await clipper.clipURL(normalized, assetsDirectory: tempAssets)
            let finalTitle = (args["title"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? result.title
            let relDir = vault.makeRelativeClipDir(title: finalTitle, id: clipId)
            let clip = ClipItem(
                id: clipId,
                relativeDir: relDir,
                title: finalTitle,
                excerpt: result.excerpt,
                url: normalized,
                domain: result.domain,
                author: result.author,
                sourceType: result.sourceType,
                coverImageName: result.coverImageName,
                folderId: folderId,
                tags: extraTags
            )

            let finalDir = vault.clipDirectoryURL(for: clip)
            try? FileManager.default.createDirectory(at: finalDir, withIntermediateDirectories: true)
            let finalAssets = vault.clipAssetsURL(for: clip)
            if FileManager.default.fileExists(atPath: finalAssets.path) {
                try? FileManager.default.removeItem(at: finalAssets)
            }
            if FileManager.default.fileExists(atPath: tempAssets.path) {
                try? FileManager.default.moveItem(at: tempAssets, to: finalAssets)
            }
            try? FileManager.default.removeItem(at: tempDir)

            try vault.saveClip(
                clip,
                articleHTML: result.cleanedHTML,
                articleMarkdown: result.markdown,
                snapshotHTML: result.snapshotHTML,
                noteMarkdown: args["note_markdown"] as? String
            )
            syncTagsToVault(extraTags)
            postVaultChanged()

            return toolSuccessJSON([
                "status": "clipped",
                "clip_id": clip.id,
                "title": clip.title,
                "url": clip.url,
                "domain": clip.domain,
                "folder_id": clip.folderId ?? "",
                "tags": clip.tags,
                "needs_manual_web_extract": result.needsManualWebExtract
            ])
        } catch {
            try? FileManager.default.removeItem(at: tempDir)
            return toolError("抓取网页失败: \(error.localizedDescription)")
        }
    }

    private func toolSaveClipMarkdown(_ args: [String: Any]) -> [String: Any] {
        guard let title = (args["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty else {
            return toolError("缺少参数 title")
        }
        guard let markdown = args["markdown"] as? String, !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return toolError("缺少参数 markdown")
        }

        let urlStr = (args["url"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let domain = URL(string: urlStr)?.host ?? (urlStr.isEmpty ? "readbox.local" : "")
        let author = (args["author"] as? String) ?? ""
        let tags = stringArray(args["tags"])
        let folderId = resolveFolderId(args["folder_id"] as? String, folderName: args["folder_name"] as? String)
        let sourceType: ClipSourceType = {
            if domain.contains("mp.weixin.qq.com") { return .wechat }
            return urlStr.isEmpty ? .note : .webpage
        }()

        let plainExcerpt: String = {
            if let explicit = args["excerpt"] as? String, !explicit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return explicit.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            let stripped = markdown
                .replacingOccurrences(of: #"[#*`>\[\]()_~-]+"#, with: " ", options: .regularExpression)
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return String(stripped.prefix(180))
        }()

        let clipId = UUID().uuidString
        let relDir = vault.makeRelativeClipDir(title: title, id: clipId)
        let clip = ClipItem(
            id: clipId,
            relativeDir: relDir,
            title: title,
            excerpt: plainExcerpt,
            url: urlStr,
            domain: domain,
            author: author,
            sourceType: sourceType,
            folderId: folderId,
            tags: tags,
            isStarred: (args["is_starred"] as? Bool) ?? false
        )

        let renderedHTML = Self.markdownToSimpleHTML(markdown)
        do {
            try vault.saveClip(
                clip,
                articleHTML: renderedHTML,
                articleMarkdown: markdown,
                snapshotHTML: renderedHTML,
                noteMarkdown: args["note_markdown"] as? String
            )
            syncTagsToVault(tags)
            postVaultChanged()
            return toolSuccessJSON([
                "status": "saved",
                "clip_id": clip.id,
                "title": clip.title,
                "folder_id": clip.folderId ?? "",
                "tags": clip.tags
            ])
        } catch {
            return toolError("保存收藏失败: \(error.localizedDescription)")
        }
    }

    private func toolUpdateClip(_ args: [String: Any]) -> [String: Any] {
        guard let clipId = args["clip_id"] as? String, !clipId.isEmpty else {
            return toolError("缺少参数 clip_id")
        }
        guard var clip = vault.loadAllClips().first(where: { $0.id == clipId }) else {
            return toolError("未找到收藏: \(clipId)")
        }

        if let title = args["title"] as? String, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            clip.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let excerpt = args["excerpt"] as? String {
            clip.excerpt = excerpt
        }
        if args.keys.contains("folder_id") || args.keys.contains("folder_name") {
            let fid = args["folder_id"] as? String
            let fname = args["folder_name"] as? String
            if fid == "" || fid == "inbox" {
                clip.folderId = nil
            } else {
                clip.folderId = resolveFolderId(fid, folderName: fname)
            }
        }
        if let tags = args["tags"] as? [String] {
            clip.tags = tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            syncTagsToVault(clip.tags)
        }
        if let isStarred = args["is_starred"] as? Bool { clip.isStarred = isStarred }
        if let isRead = args["is_read"] as? Bool { clip.isRead = isRead }
        if let isArchived = args["is_archived"] as? Bool { clip.isArchived = isArchived }
        clip.updatedAt = Date()

        do {
            try vault.saveClip(clip)
            postVaultChanged()
            return toolSuccessJSON([
                "status": "updated",
                "clip_id": clip.id,
                "title": clip.title,
                "folder_id": clip.folderId ?? "",
                "tags": clip.tags,
                "is_starred": clip.isStarred,
                "is_read": clip.isRead,
                "is_archived": clip.isArchived
            ])
        } catch {
            return toolError("更新收藏失败: \(error.localizedDescription)")
        }
    }

    private func toolDeleteClip(_ args: [String: Any]) -> [String: Any] {
        guard let clipId = args["clip_id"] as? String, !clipId.isEmpty else {
            return toolError("缺少参数 clip_id")
        }
        guard let clip = vault.loadAllClips().first(where: { $0.id == clipId }) else {
            return toolError("未找到收藏: \(clipId)")
        }
        vault.deleteClip(clip)
        postVaultChanged()
        return toolSuccessJSON(["status": "deleted", "clip_id": clipId, "title": clip.title])
    }

    // MARK: - Insight / Highlights / Notes Tools

    private func toolSetClipInsight(_ args: [String: Any]) -> [String: Any] {
        guard let clipId = args["clip_id"] as? String, !clipId.isEmpty else {
            return toolError("缺少参数 clip_id")
        }
        guard let summary = (args["summary"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !summary.isEmpty else {
            return toolError("缺少参数 summary")
        }
        guard var clip = vault.loadAllClips().first(where: { $0.id == clipId }) else {
            return toolError("未找到收藏: \(clipId)")
        }

        let insight = AIInsight(
            summary: summary,
            takeaways: stringArray(args["takeaways"]),
            keyQuestions: stringArray(args["key_questions"]),
            suggestedTags: stringArray(args["suggested_tags"]),
            suggestedFolder: args["suggested_folder"] as? String,
            generatedAt: Date()
        )
        clip.aiInsight = insight
        clip.updatedAt = Date()

        do {
            try vault.saveClip(clip)
            postVaultChanged()
            return toolSuccessJSON([
                "status": "saved",
                "clip_id": clip.id,
                "ai_insight": insightDict(insight)
            ])
        } catch {
            return toolError("写入 AI 解读失败: \(error.localizedDescription)")
        }
    }

    private func toolAddHighlight(_ args: [String: Any]) -> [String: Any] {
        guard let clipId = args["clip_id"] as? String, !clipId.isEmpty else {
            return toolError("缺少参数 clip_id")
        }
        guard let quote = (args["quote"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !quote.isEmpty else {
            return toolError("缺少参数 quote")
        }
        guard var clip = vault.loadAllClips().first(where: { $0.id == clipId }) else {
            return toolError("未找到收藏: \(clipId)")
        }

        let colorRaw = (args["color"] as? String)?.lowercased() ?? "yellow"
        let color = HighlightColor(rawValue: colorRaw) ?? .yellow
        let note = (args["note"] as? String) ?? ""

        let highlight = HighlightItem(
            clipId: clipId,
            quote: quote,
            note: note,
            color: color
        )
        clip.highlights.append(highlight)
        clip.updatedAt = Date()

        do {
            try vault.saveClip(clip)
            postVaultChanged()
            return toolSuccessJSON([
                "status": "added",
                "clip_id": clipId,
                "highlight": highlightDict(highlight)
            ])
        } catch {
            return toolError("添加批注失败: \(error.localizedDescription)")
        }
    }

    private func toolUpdateHighlight(_ args: [String: Any]) -> [String: Any] {
        guard let clipId = args["clip_id"] as? String, !clipId.isEmpty,
              let highlightId = args["highlight_id"] as? String, !highlightId.isEmpty else {
            return toolError("缺少参数 clip_id 或 highlight_id")
        }
        guard var clip = vault.loadAllClips().first(where: { $0.id == clipId }),
              let idx = clip.highlights.firstIndex(where: { $0.id == highlightId }) else {
            return toolError("未找到指定的高亮批注")
        }

        if let note = args["note"] as? String {
            clip.highlights[idx].note = note
        }
        if let colorRaw = (args["color"] as? String)?.lowercased(),
           let color = HighlightColor(rawValue: colorRaw) {
            clip.highlights[idx].color = color
        }
        clip.updatedAt = Date()

        do {
            try vault.saveClip(clip)
            postVaultChanged()
            return toolSuccessJSON([
                "status": "updated",
                "clip_id": clipId,
                "highlight": highlightDict(clip.highlights[idx])
            ])
        } catch {
            return toolError("更新批注失败: \(error.localizedDescription)")
        }
    }

    private func toolDeleteHighlight(_ args: [String: Any]) -> [String: Any] {
        guard let clipId = args["clip_id"] as? String, !clipId.isEmpty,
              let highlightId = args["highlight_id"] as? String, !highlightId.isEmpty else {
            return toolError("缺少参数 clip_id 或 highlight_id")
        }
        guard var clip = vault.loadAllClips().first(where: { $0.id == clipId }) else {
            return toolError("未找到收藏: \(clipId)")
        }
        let before = clip.highlights.count
        clip.highlights.removeAll { $0.id == highlightId }
        guard clip.highlights.count < before else {
            return toolError("未找到高亮批注: \(highlightId)")
        }
        clip.updatedAt = Date()

        do {
            try vault.saveClip(clip)
            vault.searchDB.deleteDocument(key: "highlight:\(highlightId)")
            postVaultChanged()
            return toolSuccessJSON(["status": "deleted", "clip_id": clipId, "highlight_id": highlightId])
        } catch {
            return toolError("删除批注失败: \(error.localizedDescription)")
        }
    }

    private func toolUpdateClipNote(_ args: [String: Any]) -> [String: Any] {
        guard let clipId = args["clip_id"] as? String, !clipId.isEmpty else {
            return toolError("缺少参数 clip_id")
        }
        guard let markdown = args["markdown"] as? String else {
            return toolError("缺少参数 markdown")
        }
        guard var clip = vault.loadAllClips().first(where: { $0.id == clipId }) else {
            return toolError("未找到收藏: \(clipId)")
        }

        let mode = (args["mode"] as? String)?.lowercased() ?? "replace"
        let finalNote: String
        if mode == "append" {
            let existing = vault.loadClipNote(for: clip).trimmingCharacters(in: .whitespacesAndNewlines)
            finalNote = existing.isEmpty ? markdown : "\(existing)\n\n\(markdown)"
        } else {
            finalNote = markdown
        }

        vault.saveClipNote(finalNote, for: clip)
        clip.updatedAt = Date()
        try? vault.saveClip(clip)
        postVaultChanged()
        return toolSuccessJSON([
            "status": "saved",
            "clip_id": clipId,
            "mode": mode,
            "note_length": finalNote.count
        ])
    }

    // MARK: - Folders & Tags Tools

    private func toolListFoldersAndTags() -> [String: Any] {
        let clips = vault.loadAllClips()
        let folders = vault.loadFolders()
        let savedTags = vault.loadTags()

        var tagCounts: [String: Int] = [:]
        for t in savedTags { tagCounts[t.name] = 0 }
        for c in clips where !c.isArchived {
            for t in c.tags { tagCounts[t, default: 0] += 1 }
        }

        let folderList: [[String: Any]] = folders.map { f in
            let count = clips.filter { !$0.isArchived && $0.folderId == f.id }.count
            return [
                "id": f.id,
                "name": f.name,
                "emoji": f.emoji,
                "parent_id": f.parentId ?? "",
                "clip_count": count
            ]
        }

        let tagList: [[String: Any]] = tagCounts.keys.sorted().map { name in
            ["name": name, "clip_count": tagCounts[name] ?? 0]
        }

        return toolSuccessJSON([
            "inbox_count": clips.filter { $0.isInInbox }.count,
            "total_clips": clips.filter { !$0.isArchived }.count,
            "archived_count": clips.filter { $0.isArchived }.count,
            "folders": folderList,
            "tags": tagList
        ])
    }

    private func toolManageFolder(_ args: [String: Any]) -> [String: Any] {
        guard let action = (args["action"] as? String)?.lowercased() else {
            return toolError("缺少参数 action (create | delete)")
        }
        var folders = vault.loadFolders()

        switch action {
        case "create":
            guard let name = (args["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty else {
                return toolError("创建收藏夹缺少参数 name")
            }
            let emoji = (args["emoji"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "📁"
            let parentId = (args["parent_id"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            let item = FolderItem(name: name, emoji: emoji, parentId: parentId, sortOrder: folders.count)
            folders.append(item)
            vault.saveFolders(folders)
            postVaultChanged()
            return toolSuccessJSON([
                "status": "created",
                "folder": ["id": item.id, "name": item.name, "emoji": item.emoji, "parent_id": item.parentId ?? ""]
            ])

        case "delete":
            guard let folderId = args["folder_id"] as? String, !folderId.isEmpty else {
                return toolError("删除收藏夹缺少参数 folder_id")
            }
            let before = folders.count
            folders.removeAll { $0.id == folderId }
            guard folders.count < before else {
                return toolError("未找到收藏夹: \(folderId)")
            }
            for idx in folders.indices where folders[idx].parentId == folderId {
                folders[idx].parentId = nil
            }
            vault.saveFolders(folders)
            for var clip in vault.loadAllClips() where clip.folderId == folderId {
                clip.folderId = nil
                try? vault.saveClip(clip)
            }
            postVaultChanged()
            return toolSuccessJSON(["status": "deleted", "folder_id": folderId])

        default:
            return toolError("不支持的 action: \(action)，请使用 create 或 delete")
        }
    }

    private func toolManageTag(_ args: [String: Any]) -> [String: Any] {
        guard let action = (args["action"] as? String)?.lowercased() else {
            return toolError("缺少参数 action (create | rename | delete)")
        }
        var tags = vault.loadTags()

        switch action {
        case "create":
            guard let name = (args["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty else {
                return toolError("缺少参数 name")
            }
            if !tags.contains(where: { $0.name == name }) {
                tags.append(TagItem(name: name, sortOrder: tags.count))
                vault.saveTags(tags)
                postVaultChanged()
            }
            return toolSuccessJSON(["status": "created", "name": name])

        case "rename":
            guard let oldName = (args["old_name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  let newName = (args["new_name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !oldName.isEmpty, !newName.isEmpty else {
                return toolError("重命名标签缺少参数 old_name 或 new_name")
            }
            for idx in tags.indices where tags[idx].name == oldName {
                tags[idx].name = newName
            }
            vault.saveTags(tags)
            for var clip in vault.loadAllClips() where clip.tags.contains(oldName) {
                clip.tags = clip.tags.map { $0 == oldName ? newName : $0 }
                try? vault.saveClip(clip)
            }
            postVaultChanged()
            return toolSuccessJSON(["status": "renamed", "old_name": oldName, "new_name": newName])

        case "delete":
            guard let name = (args["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty else {
                return toolError("缺少参数 name")
            }
            tags.removeAll { $0.name == name }
            vault.saveTags(tags)
            for var clip in vault.loadAllClips() where clip.tags.contains(name) {
                clip.tags.removeAll { $0 == name }
                try? vault.saveClip(clip)
            }
            postVaultChanged()
            return toolSuccessJSON(["status": "deleted", "name": name])

        default:
            return toolError("不支持的 action: \(action)，请使用 create / rename / delete")
        }
    }

    // MARK: - Knowledge Base Document Tools

    private func toolListKnowledgeDocs(_ args: [String: Any]) -> [String: Any] {
        var docs = vault.loadAllKnowledgeDocs()
        if let tag = args["tag"] as? String, !tag.isEmpty {
            docs = docs.filter { $0.tags.contains(tag) }
        }
        let limit = max(1, min(100, (args["limit"] as? Int) ?? 50))
        let items: [[String: Any]] = docs.prefix(limit).map { doc in
            [
                "id": doc.id,
                "title": doc.title,
                "file_name": doc.fileName,
                "tags": doc.tags,
                "source_clip_ids": doc.sourceClipIds,
                "generated_by_model": doc.generatedByModel ?? "",
                "updated_at": Self.isoFormatter.string(from: doc.updatedAt),
                "preview": String(doc.content.prefix(200))
            ]
        }
        return toolSuccessJSON(["total": docs.count, "docs": items])
    }

    private func toolGetKnowledgeDoc(_ args: [String: Any]) -> [String: Any] {
        guard let docId = args["doc_id"] as? String, !docId.isEmpty else {
            return toolError("缺少参数 doc_id")
        }
        guard let doc = vault.loadAllKnowledgeDocs().first(where: { $0.id == docId }) else {
            return toolError("未找到知识文档: \(docId)")
        }
        return toolSuccessJSON([
            "id": doc.id,
            "title": doc.title,
            "file_name": doc.fileName,
            "tags": doc.tags,
            "source_clip_ids": doc.sourceClipIds,
            "source_links": doc.sourceLinks,
            "generated_by_model": doc.generatedByModel ?? "",
            "created_at": Self.isoFormatter.string(from: doc.createdAt),
            "updated_at": Self.isoFormatter.string(from: doc.updatedAt),
            "content": doc.content
        ])
    }

    private func toolSaveKnowledgeDoc(_ args: [String: Any]) -> [String: Any] {
        let existingId = (args["doc_id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let docs = vault.loadAllKnowledgeDocs()

        if let docId = existingId, !docId.isEmpty, var existing = docs.first(where: { $0.id == docId }) {
            if let title = args["title"] as? String, !title.isEmpty { existing.title = title }
            if let content = args["content"] as? String { existing.content = content }
            if let tags = args["tags"] as? [String] { existing.tags = tags }
            if let sourceIds = args["source_clip_ids"] as? [String] { existing.sourceClipIds = sourceIds }
            if let model = args["generated_by_model"] as? String { existing.generatedByModel = model }
            existing.updatedAt = Date()
            do {
                try vault.saveKnowledgeDoc(existing)
                postVaultChanged()
                return toolSuccessJSON([
                    "status": "updated",
                    "doc_id": existing.id,
                    "title": existing.title,
                    "file_name": existing.fileName
                ])
            } catch {
                return toolError("更新知识文档失败: \(error.localizedDescription)")
            }
        } else {
            guard let title = (args["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !title.isEmpty else {
                return toolError("新建知识文档缺少参数 title")
            }
            guard let content = args["content"] as? String else {
                return toolError("新建知识文档缺少参数 content")
            }
            let tags = stringArray(args["tags"])
            let sourceIds = stringArray(args["source_clip_ids"])
            let clipsById = Dictionary(uniqueKeysWithValues: vault.loadAllClips().map { ($0.id, $0) })
            let sourceLinks = sourceIds.compactMap { clipsById[$0]?.url }.filter { !$0.isEmpty }
            let doc = KnowledgeDoc(
                fileName: vault.makeKnowledgeFileName(title: title),
                title: title,
                tags: tags,
                sourceClipIds: sourceIds,
                sourceLinks: sourceLinks,
                content: content,
                generatedByModel: (args["generated_by_model"] as? String) ?? "External MCP Agent"
            )
            do {
                try vault.saveKnowledgeDoc(doc)
                postVaultChanged()
                return toolSuccessJSON([
                    "status": "created",
                    "doc_id": doc.id,
                    "title": doc.title,
                    "file_name": doc.fileName
                ])
            } catch {
                return toolError("创建知识文档失败: \(error.localizedDescription)")
            }
        }
    }

    private func toolDeleteKnowledgeDoc(_ args: [String: Any]) -> [String: Any] {
        guard let docId = args["doc_id"] as? String, !docId.isEmpty else {
            return toolError("缺少参数 doc_id")
        }
        guard let doc = vault.loadAllKnowledgeDocs().first(where: { $0.id == docId }) else {
            return toolError("未找到知识文档: \(docId)")
        }
        vault.deleteKnowledgeDoc(doc)
        postVaultChanged()
        return toolSuccessJSON(["status": "deleted", "doc_id": docId, "title": doc.title])
    }

    // MARK: - Helpers

    private func resolveFolderId(_ folderId: String?, folderName: String?) -> String? {
        if let fid = folderId, !fid.isEmpty, fid != "inbox" {
            return fid
        }
        if let fname = folderName?.trimmingCharacters(in: .whitespacesAndNewlines), !fname.isEmpty {
            return vault.loadFolders().first(where: { $0.name == fname })?.id
        }
        return nil
    }

    private func syncTagsToVault(_ newTags: [String]) {
        guard !newTags.isEmpty else { return }
        var tags = vault.loadTags()
        var existing = Set(tags.map(\.name))
        var changed = false
        for t in newTags where !t.isEmpty && !existing.contains(t) {
            existing.insert(t)
            tags.append(TagItem(name: t, sortOrder: tags.count))
            changed = true
        }
        if changed {
            vault.saveTags(tags)
        }
    }

    private func postVaultChanged() {
        guard notifyVaultChange else { return }
        DistributedNotificationCenter.default().postNotificationName(
            .readBoxVaultDidChange,
            object: vault.vaultURL.path,
            userInfo: nil,
            deliverImmediately: true
        )
    }

    private func clipSummaryDict(_ clip: ClipItem, foldersById: [String: String]) -> [String: Any] {
        [
            "id": clip.id,
            "title": clip.title,
            "excerpt": clip.excerpt,
            "url": clip.url,
            "domain": clip.domain,
            "author": clip.author,
            "source_type": clip.sourceType.rawValue,
            "folder_id": clip.folderId ?? "",
            "folder_name": clip.folderId.flatMap { foldersById[$0] } ?? "收集箱",
            "tags": clip.tags,
            "is_starred": clip.isStarred,
            "is_read": clip.isRead,
            "is_archived": clip.isArchived,
            "highlight_count": clip.highlights.count,
            "has_ai_insight": clip.aiInsight != nil,
            "created_at": Self.isoFormatter.string(from: clip.createdAt),
            "updated_at": Self.isoFormatter.string(from: clip.updatedAt)
        ]
    }

    private func highlightDict(_ h: HighlightItem) -> [String: Any] {
        [
            "id": h.id,
            "clip_id": h.clipId,
            "quote": h.quote,
            "note": h.note,
            "color": h.color.rawValue,
            "created_at": Self.isoFormatter.string(from: h.createdAt)
        ]
    }

    private func insightDict(_ i: AIInsight) -> [String: Any] {
        [
            "summary": i.summary,
            "takeaways": i.takeaways,
            "key_questions": i.keyQuestions,
            "suggested_tags": i.suggestedTags,
            "suggested_folder": i.suggestedFolder ?? "",
            "generated_at": Self.isoFormatter.string(from: i.generatedAt)
        ]
    }

    private func stringArray(_ value: Any?) -> [String] {
        (value as? [String])?.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty } ?? []
    }

    private func toolSuccessJSON(_ object: [String: Any]) -> [String: Any] {
        let text = encodeJSON(object, pretty: true) ?? "{}"
        return [
            "content": [["type": "text", "text": text]],
            "isError": false
        ]
    }

    private func toolError(_ message: String) -> [String: Any] {
        [
            "content": [["type": "text", "text": message]],
            "isError": true
        ]
    }

    private func jsonRPCResult(id: Any, result: [String: Any]) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "result": result]
    }

    private func jsonRPCError(id: Any, code: Int, message: String) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]]
    }

    private func encodeJSON(_ obj: Any, pretty: Bool = false) -> String? {
        let options: JSONSerialization.WritingOptions = pretty ? [.prettyPrinted, .sortedKeys] : []
        guard let data = try? JSONSerialization.data(withJSONObject: obj, options: options) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Lightweight Markdown -> HTML converter so articles saved directly by an external Agent
    /// render cleanly inside ReadBox's offline `reader.html` canvas.
    public static func markdownToSimpleHTML(_ markdown: String) -> String {
        let lines = markdown.components(separatedBy: .newlines)
        var html: [String] = []
        var inCodeBlock = false
        var inList = false

        func closeListIfNeeded() {
            if inList {
                html.append("</ul>")
                inList = false
            }
        }

        func escapeHTML(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
        }

        func formatInline(_ raw: String) -> String {
            var s = escapeHTML(raw)
            // Inline code
            s = s.replacingOccurrences(of: #"`([^`]+)`"#, with: "<code>$1</code>", options: .regularExpression)
            // Bold
            s = s.replacingOccurrences(of: #"\*\*([^*]+)\*\*"#, with: "<strong>$1</strong>", options: .regularExpression)
            // Links [text](url)
            s = s.replacingOccurrences(of: #"\[([^\]]+)\]\((https?://[^)]+)\)"#, with: "<a href=\"$2\">$1</a>", options: .regularExpression)
            return s
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                closeListIfNeeded()
                if inCodeBlock {
                    html.append("</code></pre>")
                    inCodeBlock = false
                } else {
                    html.append("<pre><code>")
                    inCodeBlock = true
                }
                continue
            }
            if inCodeBlock {
                html.append(escapeHTML(line))
                continue
            }
            if trimmed.isEmpty {
                closeListIfNeeded()
                continue
            }
            if trimmed.hasPrefix("### ") {
                closeListIfNeeded()
                html.append("<h3>\(formatInline(String(trimmed.dropFirst(4))))</h3>")
            } else if trimmed.hasPrefix("## ") {
                closeListIfNeeded()
                html.append("<h2>\(formatInline(String(trimmed.dropFirst(3))))</h2>")
            } else if trimmed.hasPrefix("# ") {
                closeListIfNeeded()
                html.append("<h1>\(formatInline(String(trimmed.dropFirst(2))))</h1>")
            } else if trimmed.hasPrefix("> ") {
                closeListIfNeeded()
                html.append("<blockquote><p>\(formatInline(String(trimmed.dropFirst(2))))</p></blockquote>")
            } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                if !inList {
                    html.append("<ul>")
                    inList = true
                }
                html.append("<li>\(formatInline(String(trimmed.dropFirst(2))))</li>")
            } else if trimmed == "---" || trimmed == "***" {
                closeListIfNeeded()
                html.append("<hr />")
            } else {
                closeListIfNeeded()
                html.append("<p>\(formatInline(trimmed))</p>")
            }
        }
        closeListIfNeeded()
        if inCodeBlock { html.append("</code></pre>") }
        return html.joined(separator: "\n")
    }

    // MARK: - Tool Schemas

    public static let toolDefinitions: [[String: Any]] = [
        toolDef(
            name: "list_clips",
            description: "列出 ReadBox 中的收藏文章，支持按收藏夹、标签、星标、已读/未读、归档状态筛选。",
            properties: [
                "folder_id": prop("string", "收藏夹 ID，传入 \"inbox\" 或空字符串筛选收集箱"),
                "tag": prop("string", "按标签名筛选"),
                "is_starred": prop("boolean", "是否仅返回星标文章"),
                "is_read": prop("boolean", "按已读/未读筛选"),
                "is_archived": prop("boolean", "是否查看已归档文章（默认 false）"),
                "limit": prop("integer", "返回条数上限（默认 30，最大 200）")
            ]
        ),
        toolDef(
            name: "search_clips",
            description: "使用 SQLite FTS5 全文检索 ReadBox 中的收藏正文、高亮批注、个人笔记与知识沉淀文档。",
            properties: [
                "query": prop("string", "搜索关键词"),
                "limit": prop("integer", "最大返回条数（默认 20）")
            ],
            required: ["query"]
        ),
        toolDef(
            name: "get_clip",
            description: "获取单篇收藏的完整详情，包括 Markdown 正文、高亮批注、个人笔记与 AI 快读解读。",
            properties: [
                "clip_id": prop("string", "收藏文章 ID"),
                "include_article": prop("boolean", "是否包含完整 article.md 正文（默认 true）")
            ],
            required: ["clip_id"]
        ),
        toolDef(
            name: "clip_url",
            description: "通过 URL 自动抓取网页或微信公众号文章并离线保存到 ReadBox（自动下载图片与提取正文）。",
            properties: [
                "url": prop("string", "要收藏的网页或公众号文章 URL"),
                "title": prop("string", "可选：自定义覆盖标题"),
                "folder_id": prop("string", "可选：放入的收藏夹 ID"),
                "folder_name": prop("string", "可选：按收藏夹名称匹配"),
                "tags": arrayProp("string", "可选：标签数组"),
                "note_markdown": prop("string", "可选：同时写入该文章的个人笔记 Markdown")
            ],
            required: ["url"]
        ),
        toolDef(
            name: "save_clip_markdown",
            description: "直接传入标题与 Markdown 正文保存为 ReadBox 收藏（适合外部 Agent 已抓取/整理好的文章或笔记）。",
            properties: [
                "title": prop("string", "文章标题"),
                "markdown": prop("string", "文章 Markdown 正文"),
                "url": prop("string", "可选：原始文章链接"),
                "author": prop("string", "可选：作者"),
                "excerpt": prop("string", "可选：摘要（不传则自动截取）"),
                "folder_id": prop("string", "可选：收藏夹 ID"),
                "folder_name": prop("string", "可选：收藏夹名称"),
                "tags": arrayProp("string", "可选：标签数组"),
                "is_starred": prop("boolean", "可选：是否标星"),
                "note_markdown": prop("string", "可选：同时写入的个人笔记 Markdown")
            ],
            required: ["title", "markdown"]
        ),
        toolDef(
            name: "update_clip",
            description: "修改收藏的标题、摘要、所属收藏夹、标签、星标、已读或归档状态。",
            properties: [
                "clip_id": prop("string", "收藏文章 ID"),
                "title": prop("string", "新标题"),
                "excerpt": prop("string", "新摘要"),
                "folder_id": prop("string", "新收藏夹 ID（传 \"inbox\" 或空字符串移回收集箱）"),
                "folder_name": prop("string", "按名称指定收藏夹"),
                "tags": arrayProp("string", "替换标签列表"),
                "is_starred": prop("boolean", "是否星标"),
                "is_read": prop("boolean", "是否已读"),
                "is_archived": prop("boolean", "是否归档")
            ],
            required: ["clip_id"]
        ),
        toolDef(
            name: "delete_clip",
            description: "永久删除指定收藏及其本地文件与搜索索引。",
            properties: [
                "clip_id": prop("string", "要删除的收藏 ID")
            ],
            required: ["clip_id"]
        ),
        toolDef(
            name: "set_clip_insight",
            description: "为收藏写入或覆盖结构化的「AI 快读解读」（摘要、核心要点、关键问题、推荐标签与分类），会直接展示在 ReadBox 阅读页右侧 AI 面板中。",
            properties: [
                "clip_id": prop("string", "收藏文章 ID"),
                "summary": prop("string", "文章核心摘要"),
                "takeaways": arrayProp("string", "核心要点列表"),
                "key_questions": arrayProp("string", "值得思考的关键问题列表"),
                "suggested_tags": arrayProp("string", "推荐标签列表"),
                "suggested_folder": prop("string", "推荐归类收藏夹名称")
            ],
            required: ["clip_id", "summary"]
        ),
        toolDef(
            name: "add_highlight",
            description: "为收藏添加一条划词高亮及批注，打开文章时可原生高亮显示。",
            properties: [
                "clip_id": prop("string", "收藏文章 ID"),
                "quote": prop("string", "文章中要高亮的原文摘录"),
                "note": prop("string", "对该摘录的批注或点评"),
                "color": prop("string", "高亮颜色：yellow | green | blue | pink | purple（默认 yellow）")
            ],
            required: ["clip_id", "quote"]
        ),
        toolDef(
            name: "update_highlight",
            description: "修改已有高亮批注的批注文字或颜色。",
            properties: [
                "clip_id": prop("string", "收藏文章 ID"),
                "highlight_id": prop("string", "高亮批注 ID"),
                "note": prop("string", "更新后的批注内容"),
                "color": prop("string", "更新后的颜色：yellow | green | blue | pink | purple")
            ],
            required: ["clip_id", "highlight_id"]
        ),
        toolDef(
            name: "delete_highlight",
            description: "删除收藏中的某一条高亮批注。",
            properties: [
                "clip_id": prop("string", "收藏文章 ID"),
                "highlight_id": prop("string", "高亮批注 ID")
            ],
            required: ["clip_id", "highlight_id"]
        ),
        toolDef(
            name: "update_clip_note",
            description: "写入或追加指定收藏的侧边 Markdown 笔记（note.md）。",
            properties: [
                "clip_id": prop("string", "收藏文章 ID"),
                "markdown": prop("string", "笔记 Markdown 内容"),
                "mode": prop("string", "replace（覆盖，默认）或 append（追加到末尾）")
            ],
            required: ["clip_id", "markdown"]
        ),
        toolDef(
            name: "list_folders_and_tags",
            description: "列出 ReadBox 中的所有收藏夹（含层级与文章数）、标签及收集箱统计。",
            properties: [:]
        ),
        toolDef(
            name: "manage_folder",
            description: "创建或删除 ReadBox 收藏夹。",
            properties: [
                "action": prop("string", "create 或 delete"),
                "name": prop("string", "创建时的收藏夹名称"),
                "emoji": prop("string", "创建时的图标 emoji（默认 📁）"),
                "parent_id": prop("string", "可选：父收藏夹 ID"),
                "folder_id": prop("string", "删除时的收藏夹 ID")
            ],
            required: ["action"]
        ),
        toolDef(
            name: "manage_tag",
            description: "创建、重命名或删除 ReadBox 标签。",
            properties: [
                "action": prop("string", "create | rename | delete"),
                "name": prop("string", "create/delete 时的标签名"),
                "old_name": prop("string", "rename 时的原标签名"),
                "new_name": prop("string", "rename 时的目标标签名")
            ],
            required: ["action"]
        ),
        toolDef(
            name: "list_knowledge_docs",
            description: "列出 ReadBox 知识沉淀库中的所有 Markdown 文档。",
            properties: [
                "tag": prop("string", "可选：按标签筛选"),
                "limit": prop("integer", "最大返回条数（默认 50）")
            ]
        ),
        toolDef(
            name: "get_knowledge_doc",
            description: "读取某篇知识沉淀文档的完整 Markdown 内容与元信息。",
            properties: [
                "doc_id": prop("string", "知识文档 ID")
            ],
            required: ["doc_id"]
        ),
        toolDef(
            name: "save_knowledge_doc",
            description: "新建或更新一篇知识沉淀文档（传入 doc_id 为更新，不传为新建），适合跨多篇收藏归纳沉淀。",
            properties: [
                "doc_id": prop("string", "可选：要更新的知识文档 ID（不传则新建）"),
                "title": prop("string", "文档标题"),
                "content": prop("string", "文档 Markdown 正文"),
                "tags": arrayProp("string", "标签列表"),
                "source_clip_ids": arrayProp("string", "关联的源收藏 ID 列表"),
                "generated_by_model": prop("string", "可选：来源模型/Agent 标识")
            ]
        ),
        toolDef(
            name: "delete_knowledge_doc",
            description: "永久删除指定的知识沉淀文档。",
            properties: [
                "doc_id": prop("string", "要删除的知识文档 ID")
            ],
            required: ["doc_id"]
        )
    ]

    private static func toolDef(
        name: String,
        description: String,
        properties: [String: Any],
        required: [String] = []
    ) -> [String: Any] {
        var schema: [String: Any] = [
            "type": "object",
            "properties": properties
        ]
        if !required.isEmpty {
            schema["required"] = required
        }
        return [
            "name": name,
            "description": description,
            "inputSchema": schema
        ]
    }

    private static func prop(_ type: String, _ description: String) -> [String: Any] {
        ["type": type, "description": description]
    }

    private static func arrayProp(_ itemType: String, _ description: String) -> [String: Any] {
        ["type": "array", "items": ["type": itemType], "description": description]
    }
}

/// Stdio MCP server runner invoked via `ReadBox --mcp --token <mcpAccessKey>`.
public enum ReadBoxMCPStdioServer {
    public static func runFromCommandLine(arguments: [String] = CommandLine.arguments) {
        let token = parseOption("--token", in: arguments)
            ?? ProcessInfo.processInfo.environment["READBOX_MCP_TOKEN"]
            ?? ""
        let explicitVault = parseOption("--vault", in: arguments)

        let vault = VaultManager(vaultPath: explicitVault)
        let settings = vault.loadSettings()
        if explicitVault == nil, !settings.vaultPath.isEmpty, settings.vaultPath != vault.vaultURL.path {
            vault.switchVault(to: URL(fileURLWithPath: settings.vaultPath, isDirectory: true))
        }

        let handler = ReadBoxMCPHandler(
            vault: vault,
            providedToken: token,
            expectedTokenProvider: {
                // Reload settings dynamically so refreshing the key in ReadBox Settings takes effect immediately.
                vault.loadSettings().mcpAccessKey
            }
        )

        let stdout = FileHandle.standardOutput
        while let line = readLine(strippingNewline: true) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }

            let semaphore = DispatchSemaphore(value: 0)
            var reply: String?
            Task {
                reply = await handler.handleLine(trimmed)
                semaphore.signal()
            }
            semaphore.wait()

            if let reply, let data = (reply + "\n").data(using: .utf8) {
                stdout.write(data)
                fflush(Darwin.stdout)
            }
        }
    }

    private static func parseOption(_ flag: String, in arguments: [String]) -> String? {
        for idx in 0..<arguments.count {
            let arg = arguments[idx]
            if arg == flag, idx + 1 < arguments.count {
                return arguments[idx + 1]
            }
            if arg.hasPrefix("\(flag)=") {
                return String(arg.dropFirst(flag.count + 1))
            }
        }
        return nil
    }
}
