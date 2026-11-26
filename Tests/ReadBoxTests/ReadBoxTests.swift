import XCTest
@testable import ReadBox

final class ReadBoxTests: XCTestCase {
    func testFrontmatterKnowledgeRoundtrip() {
        let doc = KnowledgeDoc(
            id: "doc-123",
            fileName: "ai-agent.md",
            title: "LLM Agent 架构对比",
            tags: ["AI", "Agent/架构"],
            sourceClipIds: ["c1", "c2"],
            sourceLinks: ["https://mp.weixin.qq.com/s/demo1"],
            content: "## 核心结论\n\n- 本地优先\n- 透明 Markdown",
            generatedByModel: "DeepSeek / deepseek-chat"
        )

        let rendered = FrontmatterParser.renderKnowledgeMarkdown(doc: doc)
        XCTAssertTrue(rendered.contains("title: LLM Agent 架构对比"))
        XCTAssertTrue(rendered.contains("  - Agent/架构"))

        let parsed = FrontmatterParser.parseKnowledgeMarkdown(rendered, fileName: "ai-agent.md")
        XCTAssertEqual(parsed.id, "doc-123")
        XCTAssertEqual(parsed.title, "LLM Agent 架构对比")
        XCTAssertEqual(parsed.tags, ["AI", "Agent/架构"])
        XCTAssertEqual(parsed.sourceLinks, ["https://mp.weixin.qq.com/s/demo1"])
        XCTAssertTrue(parsed.content.contains("本地优先"))
    }

    func testVaultStorageAndSQLiteFTS5Search() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReadBoxTestVault-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let vault = VaultManager(vaultPath: tempDir.path)
        let clip = ClipItem(
            id: "clip-1",
            relativeDir: vault.makeRelativeClipDir(title: "深度解析微信文章", id: "clip-1"),
            title: "深度解析微信公众号剪藏原理",
            excerpt: "图片本地化防防盗链与离线快照",
            url: "https://mp.weixin.qq.com/s/test",
            domain: "mp.weixin.qq.com",
            author: "技术号",
            sourceType: .wechat,
            tags: ["微信", "剪藏"]
        )

        try vault.saveClip(
            clip,
            articleHTML: "<p>这是一篇测试正文，包含 DeepSeek 模型与知识沉淀。</p>",
            articleMarkdown: "这是一篇测试正文，包含 DeepSeek 模型与知识沉淀。",
            snapshotHTML: "<p>快照</p>",
            noteMarkdown: "我的侧边读书笔记"
        )

        let loaded = vault.loadAllClips()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.title, "深度解析微信公众号剪藏原理")

        let hitsCN = vault.searchDB.search(query: "知识沉淀")
        XCTAssertFalse(hitsCN.isEmpty, "Chinese substring search should return results")

        let hitsEN = vault.searchDB.search(query: "DeepSeek")
        XCTAssertFalse(hitsEN.isEmpty, "English FTS5 search should return results")
    }

    func testHTMLToMarkdownAndInsightJSON() {
        let html = "<h2>标题</h2><p>包含 <strong>加粗</strong> 和 <code>swift</code></p><blockquote>引用一句</blockquote>"
        let md = HTMLToMarkdown.convert(html)
        XCTAssertTrue(md.contains("## 标题"))
        XCTAssertTrue(md.contains("**加粗**"))
        XCTAssertTrue(md.contains("`swift`"))
        XCTAssertTrue(md.contains("> 引用一句"))

        let rawJSON = """
        ```json
        {"summary":"核心摘要","takeaways":["要点1","要点2"],"keyQuestions":["问题1"],"suggestedTags":["AI","效率"],"suggestedFolder":"技术研发"}
        ```
        """
        let insight = AIService.parseInsightJSON(rawJSON)
        XCTAssertEqual(insight.summary, "核心摘要")
        XCTAssertEqual(insight.takeaways.count, 2)
        XCTAssertEqual(insight.suggestedFolder, "技术研发")
    }

    func testZhihuSpecializedParserAndBlockedFallback() async {
        let clipper = WebClipperService()
        let tempAssets = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReadBoxZhihuAssets-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempAssets) }
        let url = URL(string: "https://zhuanlan.zhihu.com/p/771321843")!

        // 1. Valid Zhihu HTML with Post-Title & Post-RichText
        let zhihuHTML = """
        <html><head><title>测试专栏 - 知乎</title></head><body>
          <h1 class="Post-Title">深入理解 Liquid Glass 设计</h1>
          <span class="AuthorInfo-name">知乎作者</span>
          <div class="Post-RichText"><p>这是一篇超过四十个字符的知乎专栏测试正文，验证知乎专项解析器能够精准提取标题、作者与正文内容。</p></div>
        </body></html>
        """
        let parsed = await clipper.parseRenderedHTML(zhihuHTML, sourceURL: url, assetsDirectory: tempAssets)
        XCTAssertFalse(parsed.needsManualWebExtract)
        XCTAssertEqual(parsed.title, "深入理解 Liquid Glass 设计")
        XCTAssertTrue(parsed.markdown.contains("知乎专项解析器"))

        // 2. Blocked 403 gate HTML gracefully returns manual-extract bookmark instead of crashing
        let blockedHTML = "<html><body><h1>40362 安全验证</h1></body></html>"
        let fallback = await clipper.parseRenderedHTML(blockedHTML, sourceURL: url, assetsDirectory: tempAssets)
        XCTAssertTrue(fallback.needsManualWebExtract)
        XCTAssertTrue(fallback.cleanedHTML.contains("原网页"))
    }

    func testCookieDomainMatching() {
        XCTAssertTrue(SiteCookieManager.domainMatches(cookieDomain: ".zhihu.com", requestHost: "zhuanlan.zhihu.com"))
        XCTAssertTrue(SiteCookieManager.domainMatches(cookieDomain: "zhihu.com", requestHost: "www.zhihu.com"))
        XCTAssertTrue(SiteCookieManager.domainMatches(cookieDomain: "mp.weixin.qq.com", requestHost: "mp.weixin.qq.com"))
        XCTAssertFalse(SiteCookieManager.domainMatches(cookieDomain: "zhihu.com", requestHost: "notzhihu.com"))
    }

    func testLiquidGlassPreferencesRoundtripAndLegacySettingsDecode() throws {
        var settings = AppSettings(vaultPath: "/tmp/readbox-test")
        settings.liquidGlass = LiquidGlassPreferences(
            appearance: .dark,
            materialStyle: .clear,
            ambientTheme: .aurora,
            glassTintOpacity: 0.14,
            ambientIntensity: 1.2,
            rimHighlightOpacity: 0.8,
            cardTranslucent: false
        )

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertEqual(decoded.liquidGlass, settings.liquidGlass)

        // Legacy settings JSON without liquidGlass key should decode with default values
        let legacyJSON = #"{"vaultPath":"/tmp/legacy","activeProviderId":"deepseek"}"#.data(using: .utf8)!
        let legacyDecoded = try JSONDecoder().decode(AppSettings.self, from: legacyJSON)
        XCTAssertEqual(legacyDecoded.liquidGlass, LiquidGlassPreferences.standard)
    }

    @MainActor
    func testGlobalSearchAcrossFoldersClipsHighlightsAndArchive() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReadBoxGlobalSearchTest-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let state = AppState(vaultPath: tempDir.path, persistSettings: false)
        state.createFolder(name: "电影美学", emoji: "🎬")

        let activeHighlight = HighlightItem(
            clipId: "clip-movie-1",
            quote: "电影的世界，好像在渐渐消失。",
            note: "关于胶片时代电影的感叹",
            color: .blue
        )
        let activeClip = ClipItem(
            id: "clip-movie-1",
            relativeDir: state.vault.makeRelativeClipDir(title: "梦回 1994", id: "clip-movie-1"),
            title: "梦回 1994",
            excerpt: "电影的世界，好像在渐渐消失。",
            domain: "douban.com",
            tags: ["电影", "影评"],
            isArchived: false,
            highlights: [activeHighlight]
        )
        let archivedClip = ClipItem(
            id: "clip-movie-archived",
            relativeDir: state.vault.makeRelativeClipDir(title: "归档电影笔记", id: "clip-movie-archived"),
            title: "归档电影笔记",
            excerpt: "这是一篇已经归档的经典电影拉片记录。",
            domain: "readbox.local",
            tags: ["归档"],
            isArchived: true
        )

        try state.vault.saveClip(
            activeClip,
            articleHTML: "<p>电影的世界，好像在渐渐消失。1994年是影史奇迹之年。</p>",
            articleMarkdown: "电影的世界，好像在渐渐消失。1994年是影史奇迹之年。",
            snapshotHTML: "<p>快照</p>",
            noteMarkdown: "重温 1994 电影"
        )
        try state.vault.saveClip(
            archivedClip,
            articleHTML: "<p>这是一篇已经归档的经典电影拉片记录。</p>",
            articleMarkdown: "这是一篇已经归档的经典电影拉片记录。",
            snapshotHTML: "<p>快照</p>",
            noteMarkdown: ""
        )
        state.reloadVaultData()

        let snap = state.runGlobalSearch(query: "电影")
        XCTAssertTrue(snap.matchingFolders.contains(where: { $0.name == "电影美学" }))
        XCTAssertTrue(snap.matchingTags.contains(where: { $0.tag.name == "电影" }))
        XCTAssertTrue(snap.activeClipHits.contains(where: { $0.clip.id == "clip-movie-1" }))
        XCTAssertFalse(snap.activeClipHits.contains(where: { $0.clip.id == "clip-movie-archived" }))
        XCTAssertTrue(snap.archivedClipHits.contains(where: { $0.clip.id == "clip-movie-archived" }))
        XCTAssertTrue(snap.highlightHits.contains(where: { $0.highlight.id == activeHighlight.id }))

        let fullTextSnap = state.runGlobalSearch(query: "影史奇迹")
        XCTAssertTrue(fullTextSnap.fullTextClipHits.contains(where: { $0.clip.id == "clip-movie-1" }))
    }

    func testFloatingCaptureSettingsRoundtripAndHotKeyFormatter() throws {
        var settings = AppSettings(vaultPath: "/tmp/readbox-test")
        settings.floatingCapture = FloatingCaptureSettings(
            alwaysVisible: true,
            globalHotKeyEnabled: true,
            hotKeyCode: 15, // R
            hotKeyModifiers: 2560, // ⌥⇧
            autoHideAfterSave: false,
            savedOriginX: 320.5,
            savedOriginY: 640.0
        )

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertEqual(decoded.floatingCapture, settings.floatingCapture)

        // Legacy settings JSON without floatingCapture should decode with defaults
        let legacyJSON = #"{"vaultPath":"/tmp/legacy","activeProviderId":"deepseek"}"#.data(using: .utf8)!
        let legacyDecoded = try JSONDecoder().decode(AppSettings.self, from: legacyJSON)
        XCTAssertEqual(legacyDecoded.floatingCapture, FloatingCaptureSettings.standard)

        // HotKey formatting and validation
        XCTAssertEqual(
            GlobalHotKeyFormatter.displayString(
                keyCode: FloatingCaptureSettings.defaultHotKeyCode,
                carbonModifiers: FloatingCaptureSettings.defaultHotKeyModifiers
            ),
            "⌥⇧C"
        )
        XCTAssertTrue(GlobalHotKeyFormatter.isValidHotKey(keyCode: 8, carbonModifiers: 2560))
        XCTAssertFalse(GlobalHotKeyFormatter.isValidHotKey(keyCode: 8, carbonModifiers: 0))
        XCTAssertFalse(GlobalHotKeyFormatter.isValidHotKey(keyCode: 53, carbonModifiers: 2560))
    }

    func testFloatingURLParserExtractsFromShareTextAndBareDomains() {
        let shareText = "推荐一篇好文章：深入解析 Liquid Glass https://mp.weixin.qq.com/s/abc123 值得一读"
        XCTAssertEqual(
            FloatingURLParser.extractURLs(from: shareText),
            ["https://mp.weixin.qq.com/s/abc123"]
        )

        let multiLine = """
        https://www.zhihu.com/question/123
        https://example.com/post
        """
        XCTAssertEqual(
            FloatingURLParser.extractURLs(from: multiLine),
            ["https://www.zhihu.com/question/123", "https://example.com/post"]
        )

        XCTAssertEqual(
            FloatingURLParser.extractURLs(from: "mp.weixin.qq.com/s/xyz"),
            ["https://mp.weixin.qq.com/s/xyz"]
        )

        XCTAssertTrue(FloatingURLParser.extractURLs(from: "普通一段中文文字没有链接").isEmpty)
    }

    func testMCPServerAuthTokenAndFullReadWriteDeleteFlow() async throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReadBoxMCPTest-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let vault = VaultManager(vaultPath: tmpDir.path)
        var currentExpectedToken = AppSettings.generateMCPAccessKey()
        XCTAssertTrue(currentExpectedToken.hasPrefix("rb_mcp_"))

        // 1. Wrong token must be rejected on tools/call
        let badHandler = ReadBoxMCPHandler(
            vault: vault,
            providedToken: "rb_mcp_wrong_token",
            expectedTokenProvider: { currentExpectedToken },
            notifyVaultChange: false
        )
        let deniedResp = await badHandler.handleMessage([
            "jsonrpc": "2.0",
            "id": 1,
            "method": "tools/call",
            "params": ["name": "list_clips", "arguments": [:]]
        ])
        let deniedResult = deniedResp?["result"] as? [String: Any]
        XCTAssertEqual(deniedResult?["isError"] as? Bool, true)

        // 2. Valid token passes initialize, tools/list, and full CRUD
        let handler = ReadBoxMCPHandler(
            vault: vault,
            providedToken: currentExpectedToken,
            expectedTokenProvider: { currentExpectedToken },
            notifyVaultChange: false
        )

        let initResp = await handler.handleMessage([
            "jsonrpc": "2.0",
            "id": 2,
            "method": "initialize",
            "params": ["protocolVersion": "2024-11-05"]
        ])
        let initResult = initResp?["result"] as? [String: Any]
        XCTAssertEqual((initResult?["serverInfo"] as? [String: Any])?["name"] as? String, "readbox")

        let listToolsResp = await handler.handleMessage([
            "jsonrpc": "2.0",
            "id": 3,
            "method": "tools/list"
        ])
        let tools = ((listToolsResp?["result"] as? [String: Any])?["tools"] as? [[String: Any]]) ?? []
        XCTAssertEqual(tools.count, 19)

        // Helper to invoke a tool and parse JSON text payload
        func callTool(_ name: String, args: [String: Any]) async throws -> (isError: Bool, json: [String: Any]) {
            let resp = await handler.handleMessage([
                "jsonrpc": "2.0",
                "id": UUID().uuidString,
                "method": "tools/call",
                "params": ["name": name, "arguments": args]
            ])
            let result = try XCTUnwrap(resp?["result"] as? [String: Any])
            let isErr = (result["isError"] as? Bool) ?? false
            let content = (result["content"] as? [[String: Any]])?.first?["text"] as? String ?? "{}"
            let parsed = (try? JSONSerialization.jsonObject(with: Data(content.utf8)) as? [String: Any]) ?? [:]
            return (isErr, parsed)
        }

        // Save clip from Markdown
        let saved = try await callTool("save_clip_markdown", args: [
            "title": "MCP 外部 Agent 协作架构",
            "markdown": "# MCP 协作\n\n让外部 **AI Agent** 直接读写 ReadBox 本地知识库。",
            "url": "https://example.com/mcp-arch",
            "tags": ["MCP", "AI"]
        ])
        XCTAssertFalse(saved.isError)
        let clipId = try XCTUnwrap(saved.json["clip_id"] as? String)

        // Search via FTS5
        let searched = try await callTool("search_clips", args: ["query": "ReadBox"])
        XCTAssertFalse(searched.isError)
        XCTAssertGreaterThanOrEqual((searched.json["count"] as? Int) ?? 0, 1)

        // Write AI Insight
        let insightRes = try await callTool("set_clip_insight", args: [
            "clip_id": clipId,
            "summary": "本文介绍了通过 stdio MCP 让外部 Agent 替代内置 AI 读写 ReadBox 的方案。",
            "takeaways": ["零第三方依赖", "支持刷新访问密钥"],
            "key_questions": ["如何保证实时界面同步？"],
            "suggested_tags": ["效率"]
        ])
        XCTAssertFalse(insightRes.isError)

        // Add -> Update -> Delete Highlight
        let hlAdded = try await callTool("add_highlight", args: [
            "clip_id": clipId,
            "quote": "让外部 AI Agent 直接读写 ReadBox 本地知识库。",
            "note": "核心定位",
            "color": "purple"
        ])
        XCTAssertFalse(hlAdded.isError)
        let hlId = try XCTUnwrap((hlAdded.json["highlight"] as? [String: Any])?["id"] as? String)

        let hlUpdated = try await callTool("update_highlight", args: [
            "clip_id": clipId,
            "highlight_id": hlId,
            "note": "已更新的批注",
            "color": "green"
        ])
        XCTAssertFalse(hlUpdated.isError)

        // Write & Append Clip Note
        let note1 = try await callTool("update_clip_note", args: [
            "clip_id": clipId,
            "markdown": "## 初步想法\n很有价值。",
            "mode": "replace"
        ])
        XCTAssertFalse(note1.isError)
        let note2 = try await callTool("update_clip_note", args: [
            "clip_id": clipId,
            "markdown": "## 行动项\n- [ ] 接入 Claude Code",
            "mode": "append"
        ])
        XCTAssertFalse(note2.isError)

        // Verify get_clip reflects insight + highlight + appended note
        let fetched = try await callTool("get_clip", args: ["clip_id": clipId])
        XCTAssertFalse(fetched.isError)
        XCTAssertEqual((fetched.json["ai_insight"] as? [String: Any])?["summary"] as? String,
                       "本文介绍了通过 stdio MCP 让外部 Agent 替代内置 AI 读写 ReadBox 的方案。")
        let noteText = fetched.json["note_markdown"] as? String ?? ""
        XCTAssertTrue(noteText.contains("初步想法") && noteText.contains("接入 Claude Code"))
        let hls = fetched.json["highlights"] as? [[String: Any]] ?? []
        XCTAssertEqual(hls.count, 1)
        XCTAssertEqual(hls.first?["note"] as? String, "已更新的批注")

        // Delete highlight
        let hlDeleted = try await callTool("delete_highlight", args: ["clip_id": clipId, "highlight_id": hlId])
        XCTAssertFalse(hlDeleted.isError)

        // Knowledge Doc create -> delete
        let docSaved = try await callTool("save_knowledge_doc", args: [
            "title": "MCP 专题沉淀",
            "content": "整合外部 Agent 分析结果。",
            "tags": ["MCP"],
            "source_clip_ids": [clipId]
        ])
        XCTAssertFalse(docSaved.isError)
        let docId = try XCTUnwrap(docSaved.json["doc_id"] as? String)

        let docDeleted = try await callTool("delete_knowledge_doc", args: ["doc_id": docId])
        XCTAssertFalse(docDeleted.isError)

        // Delete clip
        let clipDeleted = try await callTool("delete_clip", args: ["clip_id": clipId])
        XCTAssertFalse(clipDeleted.isError)

        // 3. Refreshing expected key immediately invalidates existing handler token
        currentExpectedToken = AppSettings.generateMCPAccessKey()
        let afterRefresh = try await callTool("list_clips", args: [:])
        XCTAssertTrue(afterRefresh.isError)
    }
}
