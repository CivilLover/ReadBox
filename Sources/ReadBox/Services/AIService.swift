import Foundation

public struct AIStreamChunk: Sendable {
    public var contentDelta: String
    public var reasoningDelta: String
}

public enum AIServiceError: LocalizedError {
    case missingAPIKey(String)
    case invalidBaseURL(String)
    case httpError(Int, String)
    case decodingError(String)

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey(let provider):
            return "尚未配置 \(provider) 的 API Key，请按 ⌘, 打开「设置 → AI 服务商」填入 API Key。"
        case .invalidBaseURL(let url):
            return "无效的 API 地址：\(url)"
        case .httpError(let code, let detail):
            return "AI 接口返回错误 (\(code))：\(detail)"
        case .decodingError(let msg):
            return "解析 AI 响应失败：\(msg)"
        }
    }
}

/// Native Swift SSE Streaming AI Client supporting DeepSeek (including deepseek-reasoner thinking tokens),
/// OpenAI-compatible relays, Ollama, and Anthropic Claude.
public final class AIService: Sendable {
    public init() {}

    public func streamChat(
        provider: AIProviderProfile,
        model: String,
        apiKey: String,
        systemPrompt: String,
        messages: [ChatMessage]
    ) -> AsyncThrowingStream<AIStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    if provider.requiresAPIKey && apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        throw AIServiceError.missingAPIKey(provider.name)
                    }

                    switch provider.apiFormat {
                    case .openAICompatible:
                        try await self.streamOpenAICompatible(
                            provider: provider,
                            model: model,
                            apiKey: apiKey,
                            systemPrompt: systemPrompt,
                            messages: messages,
                            continuation: continuation
                        )
                    case .anthropic:
                        try await self.streamAnthropic(
                            provider: provider,
                            model: model,
                            apiKey: apiKey,
                            systemPrompt: systemPrompt,
                            messages: messages,
                            continuation: continuation
                        )
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    /// Non-streaming convenience helper for structured tasks (like single-article AI Insight & Inbox auto-tagging).
    public func completeOnce(
        provider: AIProviderProfile,
        model: String,
        apiKey: String,
        systemPrompt: String,
        userPrompt: String
    ) async throws -> String {
        var full = ""
        let stream = streamChat(
            provider: provider,
            model: model,
            apiKey: apiKey,
            systemPrompt: systemPrompt,
            messages: [ChatMessage(role: .user, content: userPrompt)]
        )
        for try await chunk in stream {
            full += chunk.contentDelta
        }
        return full
    }

    public func testConnection(provider: AIProviderProfile, model: String, apiKey: String) async throws -> String {
        let reply = try await completeOnce(
            provider: provider,
            model: model,
            apiKey: apiKey,
            systemPrompt: "你是连接测试助手，请仅回复：连接成功",
            userPrompt: "请回复连接成功"
        )
        return reply.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - OpenAI Compatible (DeepSeek / OpenAI / Ollama / Relays)

    private func streamOpenAICompatible(
        provider: AIProviderProfile,
        model: String,
        apiKey: String,
        systemPrompt: String,
        messages: [ChatMessage],
        continuation: AsyncThrowingStream<AIStreamChunk, Error>.Continuation
    ) async throws {
        let trimmedBase = provider.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let endpointString = trimmedBase.hasSuffix("/chat/completions") ? trimmedBase : "\(trimmedBase)/chat/completions"
        guard let url = URL(string: endpointString) else {
            throw AIServiceError.invalidBaseURL(endpointString)
        }

        var payloadMessages: [[String: String]] = []
        if !systemPrompt.isEmpty {
            payloadMessages.append(["role": "system", "content": systemPrompt])
        }
        for msg in messages where msg.role != .system {
            payloadMessages.append(["role": msg.role.rawValue, "content": msg.content])
        }

        var body: [String: Any] = [
            "model": model,
            "messages": payloadMessages,
            "stream": true
        ]
        if !model.lowercased().contains("reasoner") && !model.lowercased().hasPrefix("o1") && !model.lowercased().hasPrefix("o3") {
            body["temperature"] = provider.temperature
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 120
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty {
            req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: req)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            var errorBody = ""
            for try await line in bytes.lines {
                errorBody += line
                if errorBody.count > 400 { break }
            }
            throw AIServiceError.httpError(http.statusCode, errorBody)
        }

        for try await line in bytes.lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("data:") else { continue }
            let jsonStr = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            if jsonStr == "[DONE]" { break }
            guard let data = jsonStr.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = obj["choices"] as? [[String: Any]],
                  let delta = choices.first?["delta"] as? [String: Any] else {
                continue
            }

            let contentDelta = delta["content"] as? String ?? ""
            let reasoningDelta = delta["reasoning_content"] as? String ?? ""
            if !contentDelta.isEmpty || !reasoningDelta.isEmpty {
                continuation.yield(AIStreamChunk(contentDelta: contentDelta, reasoningDelta: reasoningDelta))
            }
        }
    }

    // MARK: - Anthropic Messages API

    private func streamAnthropic(
        provider: AIProviderProfile,
        model: String,
        apiKey: String,
        systemPrompt: String,
        messages: [ChatMessage],
        continuation: AsyncThrowingStream<AIStreamChunk, Error>.Continuation
    ) async throws {
        let trimmedBase = provider.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let endpointString = trimmedBase.hasSuffix("/messages") ? trimmedBase : "\(trimmedBase)/messages"
        guard let url = URL(string: endpointString) else {
            throw AIServiceError.invalidBaseURL(endpointString)
        }

        let payloadMessages: [[String: String]] = messages
            .filter { $0.role != .system }
            .map { ["role": $0.role.rawValue, "content": $0.content] }

        var body: [String: Any] = [
            "model": model,
            "max_tokens": 4096,
            "messages": payloadMessages,
            "stream": true
        ]
        if !systemPrompt.isEmpty {
            body["system"] = systemPrompt
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 120
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: req)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            var errorBody = ""
            for try await line in bytes.lines {
                errorBody += line
                if errorBody.count > 400 { break }
            }
            throw AIServiceError.httpError(http.statusCode, errorBody)
        }

        for try await line in bytes.lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("data:") else { continue }
            let jsonStr = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            guard let data = jsonStr.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = obj["type"] as? String else { continue }

            if type == "content_block_delta", let delta = obj["delta"] as? [String: Any] {
                if let text = delta["text"] as? String, !text.isEmpty {
                    continuation.yield(AIStreamChunk(contentDelta: text, reasoningDelta: ""))
                } else if let thinking = delta["thinking"] as? String, !thinking.isEmpty {
                    continuation.yield(AIStreamChunk(contentDelta: "", reasoningDelta: thinking))
                }
            }
        }
    }

    // MARK: - Domain Prompts (Article Insight, Library Q&A, Knowledge Distillation)

    public static func buildInsightPrompts(clip: ClipItem, articleMarkdown: String, existingFolders: [String]) -> (system: String, user: String) {
        let truncated = String(articleMarkdown.prefix(14000))
        let folderList = existingFolders.isEmpty ? "无" : existingFolders.joined(separator: "、")
        let system = """
        你是 ReadBox 的专业个人阅读与知识管理助手。请严格输出合法的 JSON（不要包含 Markdown 代码块围栏），字段如下：
        {
          "summary": "2-4 句话精炼核心摘要",
          "takeaways": ["核心观点1", "核心观点2", "核心观点3"],
          "keyQuestions": ["读者最关心的关键问题1及简答", "关键问题2及简答"],
          "suggestedTags": ["标签1", "标签2", "标签3"],
          "suggestedFolder": "从现有收藏夹中选一个最匹配的，若都不合适则返回 null"
        }
        """
        let user = """
        文章标题：\(clip.title)
        来源：\(clip.author) (\(clip.domain))
        现有收藏夹：\(folderList)

        正文内容：
        \(truncated)
        """
        return (system, user)
    }

    public static func parseInsightJSON(_ raw: String) -> AIInsight {
        var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let start = cleaned.firstIndex(of: "{"), let end = cleaned.lastIndex(of: "}") {
            cleaned = String(cleaned[start...end])
        }
        if let data = cleaned.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let summary = obj["summary"] as? String ?? cleaned
            let takeaways = obj["takeaways"] as? [String] ?? []
            let questions = obj["keyQuestions"] as? [String] ?? []
            let tags = obj["suggestedTags"] as? [String] ?? []
            let folder = obj["suggestedFolder"] as? String
            return AIInsight(
                summary: summary,
                takeaways: takeaways,
                keyQuestions: questions,
                suggestedTags: tags,
                suggestedFolder: folder
            )
        }
        return AIInsight(summary: cleaned)
    }

    public static func buildKnowledgeSynthesisSystemPrompt() -> String {
        """
        你是用户的个人知识库架构师（Knowledge Synthesizer）。
        你的任务是深度阅读用户收藏的多篇文章、高亮摘录与个人批注，去伪存真、交叉对比，沉淀为一篇**高度结构化、可直接归档到个人知识库（兼容 Obsidian）的 Markdown 文档**。

        要求：
        1. 输出纯 Markdown 正文（不需要 YAML Frontmatter，系统会自动补全），逻辑清晰、层次分明。
        2. 善用二级/三级标题、要点列表、对比表格与引用块。
        3. 涉及具体观点或数据时，用 `[来源1]`、`[来源2]` 标明出处，并在文末整理「参考资料」列表。
        4. 不要机械复述每篇文章，要按「主题脉络 / 共识与分歧 / 可复用的方法论与启发」重组知识。
        """
    }
}
