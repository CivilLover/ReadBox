import SwiftUI

/// Cubox-style centered Spotlight Search Overlay (`⌘K` / `⌘F`) powered by SQLite FTS5.
public struct QuickSearchOverlay: View {
    @EnvironmentObject var appState: AppState
    @State private var query: String = ""
    @State private var filterKind: SearchHit.Kind? = nil
    @State private var hits: [SearchHit] = []
    @FocusState private var isFocused: Bool

    public var body: some View {
        ZStack {
            Color.black.opacity(0.32)
                .ignoresSafeArea()
                .onTapGesture { appState.showQuickSearchOverlay = false }

            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                    TextField("搜索标题、全文正文、高亮标注或知识沉淀…", text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 15))
                        .focused($isFocused)
                        .onChange(of: query) { _, _ in runSearch() }

                    if !query.isEmpty {
                        Button {
                            query = ""
                            hits = []
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }

                    Button("ESC") {
                        appState.showQuickSearchOverlay = false
                    }
                    .font(.caption2)
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
                .padding(14)

                // Scope tabs
                HStack(spacing: 8) {
                    scopePill(nil, label: "全部结果")
                    scopePill(.clip, label: "全文搜索")
                    scopePill(.highlight, label: "标注搜索")
                    scopePill(.knowledge, label: "知识库搜索")
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 10)

                Divider()

                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    VStack(spacing: 6) {
                        Text("输入关键词实时检索本地全文索引（SQLite FTS5）")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("已索引 \(appState.clips.count) 篇收藏 · \(appState.allHighlights.count) 条标注 · \(appState.knowledgeDocs.count) 篇知识文档")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 160)
                } else if hits.isEmpty {
                    VStack(spacing: 6) {
                        Text("未找到与「\(query)」匹配的内容")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 160)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(hits) { hit in
                                Button {
                                    openHit(hit)
                                } label: {
                                    HStack(alignment: .top, spacing: 10) {
                                        Image(systemName: iconForKind(hit.kind))
                                            .foregroundStyle(colorForKind(hit.kind))
                                            .frame(width: 20)
                                            .padding(.top, 2)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(hit.title)
                                                .font(.system(size: 13.5, weight: .semibold))
                                                .foregroundStyle(.primary)
                                                .lineLimit(1)
                                            Text(hit.snippet)
                                                .font(.system(size: 12))
                                                .foregroundStyle(.secondary)
                                                .lineLimit(2)
                                        }
                                        Spacer()
                                        if !hit.domainOrTag.isEmpty {
                                            Text(hit.domainOrTag)
                                                .font(.caption2)
                                                .foregroundStyle(.tertiary)
                                                .lineLimit(1)
                                        }
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 9)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .background(Color.primary.opacity(0.03))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                        .padding(10)
                    }
                    .frame(maxHeight: 360)
                }
            }
            .frame(width: 580)
            .readBoxGlassSurface(in: RoundedRectangle(cornerRadius: 20))
            .shadow(color: .black.opacity(0.32), radius: 34, y: 14)
        }
        .onAppear { isFocused = true }
        .onExitCommand { appState.showQuickSearchOverlay = false }
    }

    private func scopePill(_ kind: SearchHit.Kind?, label: String) -> some View {
        let active = filterKind == kind
        return Button(label) {
            filterKind = kind
            runSearch()
        }
        .font(.system(size: 11.5, weight: active ? .semibold : .regular))
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(active ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.05))
        .foregroundStyle(active ? Color.accentColor : Color.secondary)
        .clipShape(Capsule())
        .buttonStyle(.plain)
    }

    private func runSearch() {
        hits = appState.vault.searchDB.search(query: query, kindFilter: filterKind)
    }

    private func iconForKind(_ kind: SearchHit.Kind) -> String {
        switch kind {
        case .clip: return "doc.text.fill"
        case .highlight: return "highlighter"
        case .knowledge: return "sparkles.rectangle.stack.fill"
        }
    }

    private func colorForKind(_ kind: SearchHit.Kind) -> Color {
        switch kind {
        case .clip: return .blue
        case .highlight: return .orange
        case .knowledge: return .purple
        }
    }

    private func openHit(_ hit: SearchHit) {
        appState.showQuickSearchOverlay = false
        switch hit.kind {
        case .clip, .highlight:
            appState.activeClipId = hit.targetId
        case .knowledge:
            appState.activeClipId = nil
            appState.destination = .knowledgeBase
            appState.activeKnowledgeDocId = hit.targetId
        }
    }
}

/// Quick Add Sheet (`⌘N`): Clip single/batch URLs (WeChat / webpages) or add a quick note snippet.
public struct QuickAddSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    enum Mode: String, CaseIterable {
        case url = "收藏网址 / 公众号"
        case note = "快速摘录 / 速记"
    }

    @State private var mode: Mode = .url
    @State private var urlInput: String = ""
    @State private var noteTitle: String = ""
    @State private var noteBody: String = ""
    @State private var selectedFolderId: String? = nil
    @State private var tagsInput: String = ""
    @State private var showSiteLoginSheet: Bool = false

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("添加到 ReadBox")
                    .font(.headline)
                Spacer()
                Picker("", selection: $mode) {
                    ForEach(Mode.allCases, id: \.self) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 240)
            }

            if mode == .url {
                VStack(alignment: .leading, spacing: 6) {
                    Text("粘贴微信公众号文章或任意网页链接（支持多行批量粘贴）：")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $urlInput)
                        .font(.system(size: 13, design: .monospaced))
                        .frame(height: 92)
                        .padding(6)
                        .background(Color(nsColor: .textBackgroundColor))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.12), lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            } else {
                TextField("标题（可选）", text: $noteTitle)
                    .textFieldStyle(.roundedBorder)
                TextEditor(text: $noteBody)
                    .font(.system(size: 13))
                    .frame(height: 120)
                    .padding(6)
                    .background(Color(nsColor: .textBackgroundColor))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.12), lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            HStack(spacing: 12) {
                Picker("收藏夹", selection: $selectedFolderId) {
                    Text("收集箱（默认）").tag(Optional<String>.none)
                    ForEach(appState.folders) { f in
                        Text("\(f.emoji) \(f.name)").tag(Optional(f.id))
                    }
                }
                .frame(width: 200)

                TextField("标签（逗号分隔，如 AI, 思考）", text: $tagsInput)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                if mode == .url {
                    Button {
                        showSiteLoginSheet = true
                    } label: {
                        Label("需登录的站点？先登录 Cookie", systemImage: "person.badge.key")
                            .font(.caption)
                    }
                    .buttonStyle(.link)
                }
                Spacer()
                Button("取消") { dismiss() }
                Button(mode == .url ? "开始剪藏" : "保存速记") {
                    submit()
                }
                .buttonStyle(.borderedProminent)
                .disabled(mode == .url ? urlInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty : noteBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 520)
        .sheet(isPresented: $showSiteLoginSheet) {
            let firstURL = urlInput.components(separatedBy: .newlines).first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            SiteLoginBrowserSheet(initialURLString: firstURL.isEmpty ? "https://www.zhihu.com/signin" : firstURL)
        }
        .onAppear {
            if !appState.quickAddPrefillURL.isEmpty {
                urlInput = appState.quickAddPrefillURL
            }
        }
    }

    private func submit() {
        let tags = tagsInput
            .components(separatedBy: CharacterSet(charactersIn: ",， "))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if mode == .url {
            let urls = urlInput
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            dismiss()
            Task {
                for u in urls {
                    await appState.addClipFromURL(u, folderId: selectedFolderId, tags: tags)
                }
            }
        } else {
            appState.addQuickTextClip(title: noteTitle, body: noteBody, folderId: selectedFolderId, tags: tags)
            dismiss()
        }
    }
}

/// AI Knowledge Base Synthesis Sheet: reads selected clips + highlights + notes,
/// streams a structured Markdown synthesis, and saves directly into `<Vault>/knowledge/*.md`.
public struct KnowledgeSynthesisSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var selectedIds: Set<String> = []
    @State private var docTitle: String = ""
    @State private var tagsText: String = "知识沉淀"
    @State private var selectedTemplateId: String = ""
    @State private var userGoal: String = ""
    @State private var generatedMarkdown: String = ""
    @State private var reasoningText: String = ""
    @State private var isGenerating: Bool = false
    @State private var errorMessage: String? = nil
    @State private var streamTask: Task<Void, Never>? = nil

    // AI Prompt Template Generator popover state
    @State private var showAITemplatePopover: Bool = false
    @State private var aiTemplateBrief: String = ""
    @State private var isDraftingTemplate: Bool = false
    @State private var draftTemplateName: String = ""
    @State private var draftTemplateEmoji: String = "✨"
    @State private var draftTemplatePrompt: String = ""
    @State private var templateGenError: String? = nil
    @State private var setDraftAsDefault: Bool = false

    private var selectedTemplate: SynthesisPromptTemplate? {
        appState.settings.synthesisTemplates.first(where: { $0.id == selectedTemplateId })
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("AI 阅读归纳 · 沉淀为知识库文档", systemImage: "sparkles.rectangle.stack.fill")
                    .font(.headline)
                    .foregroundStyle(.purple)
                Spacer()
                Text("\(appState.settings.activeProvider.name) · \(appState.settings.activeModelName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(16)

            Divider()

            HSplitView {
                // Left: Choose source clips & synthesis goal
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("1. 选择参与归纳的收藏（已选 \(selectedIds.count) 篇）")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Spacer()
                        Button("全选最近 8 篇") {
                            selectedIds = Set(appState.clips.filter { !$0.isArchived }.prefix(8).map(\.id))
                        }
                        .font(.caption)
                        .buttonStyle(.link)
                    }

                    List {
                        ForEach(appState.clips.filter { !$0.isArchived }) { clip in
                            HStack(spacing: 8) {
                                Image(systemName: selectedIds.contains(clip.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedIds.contains(clip.id) ? .purple : .secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(clip.title)
                                        .font(.system(size: 12.5, weight: .medium))
                                        .lineLimit(1)
                                    Text("\(clip.domain) · \(clip.highlights.count) 标注")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if selectedIds.contains(clip.id) { selectedIds.remove(clip.id) }
                                else { selectedIds.insert(clip.id) }
                            }
                        }
                    }
                    .listStyle(.bordered)
                    .frame(minHeight: 160)

                    HStack {
                        Text("2. 分析提示词模板")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Spacer()
                        Button {
                            templateGenError = nil
                            showAITemplatePopover = true
                        } label: {
                            Label("AI 写新模板", systemImage: "wand.and.stars")
                                .font(.caption)
                        }
                        .buttonStyle(.link)
                        .popover(isPresented: $showAITemplatePopover) {
                            aiTemplateCreatorPopover
                        }
                    }

                    // Template picker + set-as-default controls
                    HStack(spacing: 6) {
                        Picker("", selection: $selectedTemplateId) {
                            ForEach(appState.settings.synthesisTemplates) { tpl in
                                let suffix = tpl.id == appState.settings.defaultSynthesisTemplateId ? "（默认）" : ""
                                Text("\(tpl.emoji) \(tpl.name)\(suffix)").tag(tpl.id)
                            }
                        }
                        .labelsHidden()
                        .onChange(of: selectedTemplateId) { _, newId in
                            if let tpl = appState.settings.synthesisTemplates.first(where: { $0.id == newId }) {
                                userGoal = tpl.prompt
                            }
                        }

                        if selectedTemplateId != appState.settings.defaultSynthesisTemplateId {
                            Button("设为默认") {
                                appState.settings.defaultSynthesisTemplateId = selectedTemplateId
                                appState.saveSettings()
                                appState.showToast("已设为默认分析模板")
                            }
                            .controlSize(.small)
                        }

                        if let tpl = selectedTemplate, !tpl.isBuiltIn {
                            Button(role: .destructive) {
                                deleteCustomTemplate(tpl)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.caption)
                            }
                            .buttonStyle(.borderless)
                            .help("删除此自定义模板")
                        }
                    }

                    TextEditor(text: $userGoal)
                        .font(.system(size: 12.5))
                        .frame(height: 86)
                        .padding(4)
                        .background(Color(nsColor: .textBackgroundColor))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.1), lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    HStack {
                        if isGenerating {
                            Button("停止生成", role: .destructive) {
                                streamTask?.cancel()
                                isGenerating = false
                            }
                        } else {
                            Button {
                                startSynthesis()
                            } label: {
                                Label("开始 AI 归纳", systemImage: "sparkles")
                                    .frame(maxWidth: .infinity)
                            }
                            .readBoxGlassButton(prominent: true, tint: .blue)
                            .disabled(selectedIds.isEmpty)
                        }
                    }
                }
                .padding(14)
                .frame(minWidth: 300, idealWidth: 330)

                // Right: Live Preview & Save to Knowledge Base
                VStack(alignment: .leading, spacing: 10) {
                    TextField("知识文档标题（归档文件名）", text: $docTitle)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 14, weight: .semibold))

                    TextField("标签（逗号分隔）", text: $tagsText)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)

                    if let err = errorMessage {
                        Text("⚠️ \(err)")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    if !reasoningText.isEmpty {
                        DisclosureGroup("DeepSeek 思考过程") {
                            ScrollView {
                                Text(reasoningText)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(maxHeight: 90)
                        }
                        .font(.caption)
                    }

                    ScrollView {
                        if generatedMarkdown.isEmpty {
                            VStack(spacing: 8) {
                                Spacer(minLength: 80)
                                Image(systemName: "doc.text.magnifyingglass")
                                    .font(.system(size: 32))
                                    .foregroundStyle(.tertiary)
                                Text("点击左侧「开始 AI 归纳」，AI 将阅读选中文章的正文、高亮和你的笔记，生成可沉淀的知识文档。")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                                    .frame(maxWidth: 300)
                            }
                            .frame(maxWidth: .infinity)
                        } else {
                            Text(LocalizedStringKey(generatedMarkdown))
                                .font(.system(size: 13))
                                .lineSpacing(4)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                        }
                    }
                    .background(Color(nsColor: .textBackgroundColor))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.1), lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    HStack {
                        Spacer()
                        Button("关闭") {
                            streamTask?.cancel()
                            dismiss()
                        }
                        Button("保存到知识沉淀库（.md）") {
                            saveResult()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(generatedMarkdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isGenerating)
                    }
                }
                .padding(14)
                .frame(minWidth: 380)
            }
        }
        .frame(width: 860, height: 610)
        .onAppear {
            selectedIds = Set(appState.synthesisTargetClipIds)
            let def = appState.settings.defaultSynthesisTemplate
            selectedTemplateId = def.id
            userGoal = def.prompt
            if docTitle.isEmpty {
                let df = DateFormatter()
                df.dateFormat = "yyyy-MM-dd"
                docTitle = "知识沉淀-\(df.string(from: Date()))"
            }
        }
    }

    private var aiTemplateCreatorPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("让 AI 帮你写分析提示词模板", systemImage: "wand.and.stars")
                .font(.headline)

            Text("用一句话描述你想怎么分析文章（例如：「分析 AI 产品商业模式与护城河」或「拆解技术方案性能瓶颈与成本」）：")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                TextField("输入你的分析需求…", text: $aiTemplateBrief)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { draftTemplateWithAI() }

                Button {
                    draftTemplateWithAI()
                } label: {
                    if isDraftingTemplate {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("AI 生成")
                    }
                }
                .readBoxGlassButton(prominent: true, tint: .blue)
                .disabled(aiTemplateBrief.trimmingCharacters(in: .whitespaces).isEmpty || isDraftingTemplate)
            }

            if let err = templateGenError {
                Text("⚠️ \(err)")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Divider()

            HStack(spacing: 8) {
                TextField("Emoji", text: $draftTemplateEmoji)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 48)
                TextField("模板名称（如：产品商业拆解）", text: $draftTemplateName)
                    .textFieldStyle(.roundedBorder)
            }

            TextEditor(text: $draftTemplatePrompt)
                .font(.system(size: 12.5))
                .frame(height: 110)
                .padding(4)
                .background(Color(nsColor: .textBackgroundColor))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.12), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            Toggle("保存后同时设为默认模板", isOn: $setDraftAsDefault)
                .font(.caption)

            HStack {
                Spacer()
                Button("取消") { showAITemplatePopover = false }
                Button("保存到模板库") {
                    saveDraftTemplate()
                }
                .readBoxGlassButton(prominent: true, tint: .blue)
                .disabled(draftTemplateName.trimmingCharacters(in: .whitespaces).isEmpty || draftTemplatePrompt.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 420)
    }

    private func draftTemplateWithAI() {
        let brief = aiTemplateBrief.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !brief.isEmpty else { return }
        isDraftingTemplate = true
        templateGenError = nil
        let provider = appState.settings.activeProvider
        let model = appState.settings.activeModelName
        let apiKey = KeychainService.shared.loadAPIKey(forProviderId: provider.id)

        Task {
            do {
                let tpl = try await appState.aiService.generatePromptTemplate(
                    requirement: brief,
                    provider: provider,
                    model: model,
                    apiKey: apiKey
                )
                draftTemplateName = tpl.name
                draftTemplateEmoji = tpl.emoji
                draftTemplatePrompt = tpl.prompt
            } catch {
                templateGenError = error.localizedDescription
            }
            isDraftingTemplate = false
        }
    }

    private func saveDraftTemplate() {
        let tpl = SynthesisPromptTemplate(
            name: draftTemplateName.trimmingCharacters(in: .whitespacesAndNewlines),
            emoji: draftTemplateEmoji.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "✨" : draftTemplateEmoji.trimmingCharacters(in: .whitespacesAndNewlines),
            prompt: draftTemplatePrompt.trimmingCharacters(in: .whitespacesAndNewlines),
            isBuiltIn: false
        )
        appState.settings.synthesisTemplates.append(tpl)
        if setDraftAsDefault {
            appState.settings.defaultSynthesisTemplateId = tpl.id
        }
        appState.saveSettings()
        selectedTemplateId = tpl.id
        userGoal = tpl.prompt
        aiTemplateBrief = ""
        draftTemplateName = ""
        draftTemplatePrompt = ""
        setDraftAsDefault = false
        showAITemplatePopover = false
        appState.showToast("已保存新模板：\(tpl.emoji) \(tpl.name)")
    }

    private func deleteCustomTemplate(_ tpl: SynthesisPromptTemplate) {
        appState.settings.synthesisTemplates.removeAll { $0.id == tpl.id }
        if appState.settings.defaultSynthesisTemplateId == tpl.id {
            appState.settings.defaultSynthesisTemplateId = SynthesisPromptTemplate.builtInPresets[0].id
        }
        appState.saveSettings()
        let fallback = appState.settings.defaultSynthesisTemplate
        selectedTemplateId = fallback.id
        userGoal = fallback.prompt
    }

    private func startSynthesis() {
        let targetClips = appState.clips.filter { selectedIds.contains($0.id) }
        guard !targetClips.isEmpty else { return }

        generatedMarkdown = ""
        reasoningText = ""
        errorMessage = nil
        isGenerating = true

        let provider = appState.settings.activeProvider
        let model = appState.settings.activeModelName
        let apiKey = KeychainService.shared.loadAPIKey(forProviderId: provider.id)

        // Assemble multi-article context cleanly
        let perClipBudget = max(1200, 20000 / max(1, targetClips.count))
        let material = targetClips.enumerated().map { idx, clip in
            let body = String(appState.vault.loadArticleMarkdown(for: clip).prefix(perClipBudget))
            let note = appState.vault.loadClipNote(for: clip)
            let hl = clip.highlights.map { "- \($0.quote)" }.joined(separator: "\n")
            return """
            ### [来源\(idx + 1)] 《\(clip.title)》
            - 网址：\(clip.url)
            - 作者/站点：\(clip.author) (\(clip.domain))
            - 用户高亮：\(hl.isEmpty ? "无" : "\n" + hl)
            - 用户笔记：\(note.isEmpty ? "无" : "\n" + note)
            - 正文节选：
            \(body)
            """
        }.joined(separator: "\n\n---\n\n")

        let userPrompt = """
        我的整理目标：\(userGoal)

        以下是参与归纳的 \(targetClips.count) 篇收藏资料：

        \(material)
        """

        streamTask = Task {
            do {
                let stream = appState.aiService.streamChat(
                    provider: provider,
                    model: model,
                    apiKey: apiKey,
                    systemPrompt: AIService.buildKnowledgeSynthesisSystemPrompt(),
                    messages: [ChatMessage(role: .user, content: userPrompt)]
                )
                for try await chunk in stream {
                    if Task.isCancelled { break }
                    generatedMarkdown += chunk.contentDelta
                    reasoningText += chunk.reasoningDelta
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isGenerating = false
        }
    }

    private func saveResult() {
        let sourceClips = appState.clips.filter { selectedIds.contains($0.id) }
        let tags = tagsText
            .components(separatedBy: CharacterSet(charactersIn: ",， "))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let finalTitle = docTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "AI 知识沉淀" : docTitle
        let doc = appState.saveMarkdownAsKnowledgeDoc(
            title: finalTitle,
            markdown: generatedMarkdown,
            tags: tags,
            sourceClips: sourceClips
        )
        appState.activeClipId = nil
        appState.destination = .knowledgeBase
        appState.activeKnowledgeDocId = doc.id
        appState.isMultiSelectMode = false
        appState.selectedClipIds.removeAll()
        dismiss()
    }
}
