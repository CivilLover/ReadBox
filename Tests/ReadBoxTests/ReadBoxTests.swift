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
}
