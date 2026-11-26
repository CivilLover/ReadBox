import SwiftUI
import AppKit

/// Chrome-side-panel-style AI Assistant supporting DeepSeek (with R1 reasoning disclosure),
/// single-article Insight, context-aware Q&A, whole-library Q&A, and one-click Knowledge Distillation.
public struct AISidebarView: View {
    @EnvironmentObject var appState: AppState
    public let contextClip: ClipItem? // nil = Global Library Chat mode

    @State private var inputText: String = ""
    @State private var isInsightExpanded: Bool = true
    @State private var expandedReasoningIds: Set<String> = []

    private var sessionKey: String {
        contextClip?.id ?? "global"
    }

    private var messages: [ChatMessage] {
        appState.chatHistories[sessionKey] ?? []
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Active model header + quick actions
            headerStrip
            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        // Single-Article AI Quick Insight Card (Cubox style)
                        if let clip = contextClip {
                            insightCard(for: clip)
                        } else {
                            globalWelcomeCard
                        }

                        // Conversation messages
                        ForEach(messages) { msg in
                            chatBubble(msg)
                                .id(msg.id)
                        }
                    }
                    .padding(14)
                }
                .onChange(of: messages.last?.content) { _, _ in
                    if let lastId = messages.last?.id {
                        proxy.scrollTo(lastId, anchor: .bottom)
                    }
                }
            }

            Divider()

            // Quick Prompt Chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    let prompts = contextClip != nil
                        ? appState.settings.customQuickPrompts
                        : [
                            "总结我最近收藏的核心主题",
                            "找出关于 AI 或效率的关键观点",
                            "对比我收藏文章中的不同看法",
                            "帮我规划一份本周阅读重点清单"
                        ]
                    ForEach(prompts, id: \.self) { prompt in
                        Button {
                            sendPrompt(prompt)
                        } label: {
                            Text(prompt)
                                .font(.system(size: 11.5))
                                .lineLimit(1)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.purple.opacity(0.09))
                                .foregroundStyle(.purple)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(appState.isAIStreaming)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
            }
            .frame(maxWidth: .infinity)
            .clipped()

            // Input Box
            HStack(alignment: .bottom, spacing: 8) {
                TextField(
                    contextClip != nil ? "就本文向 \(appState.settings.activeProvider.name) 提问…" : "向整个收藏库提问…",
                    text: $inputText,
                    axis: .vertical
                )
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .font(.system(size: 13))
                .padding(8)
                .frame(minWidth: 0, maxWidth: .infinity)
                .background(Color(nsColor: .controlBackgroundColor))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.1), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .onSubmit {
                    if !NSEvent.modifierFlags.contains(.shift) {
                        sendPrompt(inputText)
                    }
                }

                if appState.isAIStreaming {
                    Button {
                        appState.stopAIStreaming()
                    } label: {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .fixedSize()
                    .help("停止生成")
                } else {
                    Button {
                        sendPrompt(inputText)
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.secondary.opacity(0.4) : Color.purple)
                    }
                    .buttonStyle(.plain)
                    .fixedSize()
                    .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(10)
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        .onChange(of: appState.pendingAIQuoteQuestion) { _, newQ in
            if let q = newQ, !q.isEmpty {
                appState.pendingAIQuoteQuestion = nil
                sendPrompt(q)
            }
        }
        .onAppear {
            if let q = appState.pendingAIQuoteQuestion, !q.isEmpty {
                appState.pendingAIQuoteQuestion = nil
                sendPrompt(q)
            }
        }
    }

    private var headerStrip: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(appState.settings.providers) { provider in
                    Menu(provider.name) {
                        ForEach(provider.availableModels, id: \.self) { model in
                            Button {
                                appState.settings.activeProviderId = provider.id
                                appState.settings.activeModelName = model
                                appState.saveSettings()
                            } label: {
                                HStack {
                                    Text(model)
                                    if appState.settings.activeProviderId == provider.id && appState.settings.activeModelName == model {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(.purple)
                    Text("\(appState.settings.activeProvider.name) · \(appState.settings.activeModelName)")
                        .font(.system(size: 11.5, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .menuStyle(.borderlessButton)
            .frame(minWidth: 0, alignment: .leading)

            Spacer(minLength: 6)

            if !messages.isEmpty {
                Button {
                    appState.clearChatHistory(for: sessionKey)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .fixedSize()
                .help("清空当前对话")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var globalWelcomeCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("全库 AI 知识助手", systemImage: "books.vertical.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.purple)
                Spacer()
                Button("✨ 专题沉淀") {
                    appState.synthesisTargetClipIds = appState.filteredClips.prefix(8).map(\.id)
                    appState.showSynthesisSheet = true
                }
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
                .tint(.purple)
            }
            Text("当前已索引 \(appState.clips.count) 篇收藏与 \(appState.knowledgeDocs.count) 篇知识文档。你可以直接向我提问、跨文章对比观点，或点击右上角把多篇收藏归纳沉淀为结构化知识库。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineSpacing(3)
        }
        .padding(12)
        .background(Color.purple.opacity(0.06))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.purple.opacity(0.16), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func insightCard(for clip: ClipItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label("AI 快读解读", systemImage: "sparkles")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.purple)
                    .lineLimit(1)
                Spacer(minLength: 6)
                if appState.isGeneratingInsight {
                    ProgressView().controlSize(.small)
                } else {
                    Button(clip.aiInsight == nil ? "一键解读" : "重新解读") {
                        Task { await appState.generateInsight(for: clip) }
                    }
                    .controlSize(.small)
                    .buttonStyle(.bordered)
                    .fixedSize()
                }
                if clip.aiInsight != nil {
                    Button {
                        withAnimation { isInsightExpanded.toggle() }
                    } label: {
                        Image(systemName: isInsightExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .fixedSize()
                }
            }

            if let insight = clip.aiInsight, isInsightExpanded {
                Text(insight.summary)
                    .font(.system(size: 12.5))
                    .lineSpacing(3)
                    .textSelection(.enabled)

                if !insight.takeaways.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("核心要点")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                        ForEach(insight.takeaways, id: \.self) { point in
                            HStack(alignment: .top, spacing: 6) {
                                Text("•").foregroundStyle(.purple)
                                Text(point).font(.system(size: 12))
                            }
                        }
                    }
                }

                if !insight.keyQuestions.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("关键问题")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                        ForEach(insight.keyQuestions, id: \.self) { q in
                            Text("Q: \(q)")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if !insight.suggestedTags.isEmpty {
                    HStack(spacing: 6) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 5) {
                                ForEach(insight.suggestedTags, id: \.self) { tag in
                                    Text("#\(tag)")
                                        .font(.caption2)
                                        .lineLimit(1)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.purple.opacity(0.1))
                                        .clipShape(Capsule())
                                }
                            }
                        }
                        .frame(minWidth: 0, maxWidth: .infinity)

                        Button("采纳标签") {
                            var updated = clip
                            for t in insight.suggestedTags where !updated.tags.contains(t) {
                                updated.tags.append(t)
                            }
                            if let suggestedFolder = insight.suggestedFolder,
                               let folder = appState.folders.first(where: { $0.name == suggestedFolder }) {
                                updated.folderId = folder.id
                            }
                            appState.updateClip(updated)
                            appState.showToast("已采纳 AI 建议的标签与分类")
                        }
                        .font(.caption)
                        .buttonStyle(.link)
                        .fixedSize()
                    }
                }
            } else if clip.aiInsight == nil {
                Text("点击「一键解读」，让 \(appState.settings.activeProvider.name) 快速提炼摘要、核心论点与推荐标签。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(Color.purple.opacity(0.05))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.purple.opacity(0.16), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func chatBubble(_ msg: ChatMessage) -> some View {
        let isUser = msg.role == .user
        VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
            if !isUser && !msg.reasoningContent.isEmpty {
                let isExpanded = expandedReasoningIds.contains(msg.id)
                VStack(alignment: .leading, spacing: 4) {
                    Button {
                        if isExpanded { expandedReasoningIds.remove(msg.id) }
                        else { expandedReasoningIds.insert(msg.id) }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "brain.head.profile")
                            Text(isExpanded ? "收起深度思考过程" : "查看深度思考过程 (DeepSeek R1)")
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)

                    if isExpanded {
                        Text(msg.reasoningContent)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .padding(8)
                            .background(Color.primary.opacity(0.04))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .textSelection(.enabled)
                    }
                }
            }

            if isUser {
                Text(msg.content)
                    .font(.system(size: 13))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .textSelection(.enabled)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    if msg.content.isEmpty && appState.isAIStreaming {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("思考中…").font(.caption).foregroundStyle(.secondary)
                        }
                    } else {
                        Text(LocalizedStringKey(msg.content))
                            .font(.system(size: 13))
                            .lineSpacing(4)
                            .textSelection(.enabled)
                    }

                    if !msg.content.isEmpty && !appState.isAIStreaming {
                        HStack(spacing: 12) {
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(msg.content, forType: .string)
                                appState.showToast("已复制 AI 回复")
                            } label: {
                                Label("复制", systemImage: "doc.on.doc")
                            }

                            if contextClip != nil {
                                Button {
                                    appState.pendingNoteAppendMarkdown = msg.content
                                    appState.rightPanelTab = .note
                                    appState.showToast("已追加到侧边笔记")
                                } label: {
                                    Label("追加到笔记", systemImage: "square.and.pencil")
                                }
                            }

                            Button {
                                let title = contextClip.map { "\($0.title) · AI 沉淀" } ?? "AI 知识沉淀"
                                let sources = contextClip.map { [$0] } ?? []
                                let doc = appState.saveMarkdownAsKnowledgeDoc(
                                    title: title,
                                    markdown: msg.content,
                                    tags: ["AI沉淀"],
                                    sourceClips: sources
                                )
                                appState.activeKnowledgeDocId = doc.id
                            } label: {
                                Label("存入知识库", systemImage: "sparkles.rectangle.stack")
                            }
                            .foregroundStyle(.purple)
                        }
                        .font(.caption)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                }
                .padding(11)
                .background(Color(nsColor: .controlBackgroundColor))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.07), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
    }

    private func sendPrompt(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        inputText = ""
        appState.sendAIChatMessage(prompt: trimmed, contextClip: contextClip)
    }
}
