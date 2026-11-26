import SwiftUI
import AppKit

public enum ReaderContentMode: String, CaseIterable {
    case article = "文章"
    case webpage = "原网页"
    case snapshot = "快照"
}

/// Immersive Cubox-inspired Reader + Chrome-side-panel-style Right Workspace (AI Assistant / WYSIWYG Markdown Notes / Highlights).
public struct ReaderWorkspaceView: View {
    @EnvironmentObject var appState: AppState
    let clip: ClipItem

    @State private var contentMode: ReaderContentMode = .article
    @State private var showTypographyPopover = false
    @State private var noteMarkdown: String = ""
    @State private var loadedNoteClipId: String = ""
    @State private var showTagEditor = false
    @State private var newTagInput = ""
    @State private var webExtractTrigger: Int = 0
    @State private var articleReloadToken: Int = 0

    public var body: some View {
        VStack(spacing: 0) {
            readerTopToolbar
            Divider()

            HSplitView {
                // Left/Main Reading Pane
                ZStack {
                    switch contentMode {
                    case .article:
                        ReaderWebView(
                            clip: clip,
                            articleHTML: appState.vault.loadArticleHTML(for: clip),
                            clipDirectoryURL: appState.vault.clipDirectoryURL(for: clip),
                            preferences: appState.settings.reader,
                            scrollToHighlightId: appState.pendingScrollToHighlightId,
                            onAddHighlight: { quote, color in
                                appState.addHighlight(to: clip.id, quote: quote, color: color)
                            },
                            onRemoveHighlight: { hlId in
                                appState.removeHighlight(id: hlId, from: clip.id)
                            },
                            onQuoteToNote: { quote in
                                let mdQuote = "> \(quote)"
                                appState.pendingNoteAppendMarkdown = mdQuote
                                appState.isRightPanelOpen = true
                                appState.rightPanelTab = .note
                                appState.showToast("已引用到侧边笔记")
                            },
                            onAskAI: { quote in
                                appState.pendingAIQuoteQuestion = "请结合文章上下文，详细解读并分析这段话：\n\n> \(quote)"
                                appState.isRightPanelOpen = true
                                appState.rightPanelTab = .ai
                            },
                            onClearScrollTarget: {
                                appState.pendingScrollToHighlightId = nil
                            }
                        )
                        .id("reader-\(clip.id)-\(articleReloadToken)")
                    case .webpage:
                        if let url = URL(string: clip.url), !clip.url.isEmpty {
                            ZStack(alignment: .bottomTrailing) {
                                SimpleWebView(
                                    url: url,
                                    htmlString: nil,
                                    baseURL: nil,
                                    extractTrigger: webExtractTrigger,
                                    onExtractedHTML: { html in
                                        Task {
                                            let ok = await appState.reextractClip(clip, fromRenderedHTML: html)
                                            if ok {
                                                articleReloadToken += 1
                                                contentMode = .article
                                            }
                                        }
                                    }
                                )

                                Button {
                                    webExtractTrigger += 1
                                } label: {
                                    Label(appState.isClipping ? "正在提取正文…" : "提取当前页正文（保存离线版）", systemImage: "sparkles")
                                        .font(.system(size: 12.5, weight: .semibold))
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                }
                                .readBoxGlassButton(prominent: true, tint: .blue)
                                .disabled(appState.isClipping)
                                .padding(18)
                            }
                        } else {
                            ContentUnavailableView("本地速记无原始网址", systemImage: "doc.text")
                        }
                    case .snapshot:
                        SimpleWebView(
                            url: nil,
                            htmlString: appState.vault.loadSnapshotHTML(for: clip),
                            baseURL: appState.vault.clipDirectoryURL(for: clip)
                        )
                    }
                }
                .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)

                // Right Chrome-Side-Panel-Style Drawer (AI / WYSIWYG Note / Highlights)
                if appState.isRightPanelOpen {
                    rightInspectorPanel
                        .frame(minWidth: 340, idealWidth: 410, maxWidth: 560, maxHeight: .infinity)
                }
            }
        }
        .onAppear { syncNoteForCurrentClip() }
        .onChange(of: clip.id) { _, _ in syncNoteForCurrentClip() }
    }

    private func syncNoteForCurrentClip() {
        if loadedNoteClipId != clip.id {
            loadedNoteClipId = clip.id
            noteMarkdown = appState.vault.loadClipNote(for: clip)
        }
    }

    private var readerTopToolbar: some View {
        HStack(spacing: 10) {
            Button {
                appState.activeClipId = nil
            } label: {
                Label("返回", systemImage: "chevron.left")
                    .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Spacer()

            // Cubox Signature Pill Mode Switcher: 文章 | 原网页 | 快照
            Picker("", selection: $contentMode) {
                ForEach(ReaderContentMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 220)

            Spacer()

            // Typography Aa Popover
            Button {
                showTypographyPopover.toggle()
            } label: {
                Image(systemName: "textformat.size")
                    .font(.system(size: 13.5))
            }
            .buttonStyle(.borderless)
            .help("阅读排版设置")
            .popover(isPresented: $showTypographyPopover) {
                typographyPopover
            }

            // Star
            Button {
                appState.toggleStar(clip)
            } label: {
                Image(systemName: clip.isStarred ? "star.fill" : "star")
                    .foregroundStyle(clip.isStarred ? .orange : .secondary)
            }
            .buttonStyle(.borderless)
            .help("星标")

            // Folder Assignment Menu
            Menu {
                Button("收集箱（无收藏夹）") { appState.moveClip(clip, toFolderId: nil) }
                Divider()
                ForEach(appState.folders) { folder in
                    Button {
                        appState.moveClip(clip, toFolderId: folder.id)
                    } label: {
                        HStack {
                            Text("\(folder.emoji) \(folder.name)")
                            if clip.folderId == folder.id { Image(systemName: "checkmark") }
                        }
                    }
                }
            } label: {
                Image(systemName: "folder")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("移动到收藏夹")

            // Tag Editor Popover
            Button {
                showTagEditor.toggle()
            } label: {
                Image(systemName: "tag")
            }
            .buttonStyle(.borderless)
            .help("管理标签")
            .popover(isPresented: $showTagEditor) {
                tagPopover
            }

            // More Actions (Export / Synthesize / Open in Browser)
            Menu {
                Button("✨ 沉淀本文为知识库文档") {
                    appState.synthesisTargetClipIds = [clip.id]
                    appState.showSynthesisSheet = true
                }
                Button("导出为 Markdown（含标注与笔记）…") {
                    appState.exportClipToUserFolder(clip)
                }
                if !clip.url.isEmpty, let url = URL(string: clip.url) {
                    Button("在默认浏览器打开原文") { NSWorkspace.shared.open(url) }
                }
                Divider()
                Button(clip.isArchived ? "取消归档" : "归档") { appState.toggleArchive(clip) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Divider().frame(height: 16)

            // Right Side Panel Toggle (⌘L)
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    appState.isRightPanelOpen.toggle()
                }
            } label: {
                Image(systemName: "sidebar.right")
                    .foregroundStyle(appState.isRightPanelOpen ? Color.accentColor : .secondary)
            }
            .buttonStyle(.borderless)
            .help("展开/收起右侧 AI 与笔记栏 (⌘L)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(.ultraThinMaterial)
    }

    private var rightInspectorPanel: some View {
        VStack(spacing: 0) {
            // Segmented Liquid Glass Tab Bar: AI 助手 | 笔记 | 标注
            HStack(spacing: 6) {
                panelTabButton(.ai, icon: "sparkles", label: "AI 助手")
                panelTabButton(.note, icon: "square.and.pencil", label: "笔记")
                panelTabButton(.highlights, icon: "highlighter", label: "标注\(clip.highlights.isEmpty ? "" : " \(clip.highlights.count)")")
            }
            .padding(6)
            .readBoxGlassSurface(in: Capsule())
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            Divider()

            switch appState.rightPanelTab {
            case .ai:
                AISidebarView(contextClip: clip)
            case .note:
                VStack(spacing: 0) {
                    HStack {
                        Text("单栏所见即所得 Markdown 笔记")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("自动保存至 note.md")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Color.primary.opacity(0.02))

                    Divider()

                    WYSIWYGEditorView(
                        documentId: "clip-note:\(clip.id)",
                        markdown: noteMarkdown,
                        pendingAppend: appState.pendingNoteAppendMarkdown,
                        onMarkdownChange: { updatedMD in
                            noteMarkdown = updatedMD
                            appState.vault.saveClipNote(updatedMD, for: clip)
                        },
                        onConsumeAppend: {
                            appState.pendingNoteAppendMarkdown = nil
                        }
                    )
                }
            case .highlights:
                highlightsInspectorList
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func panelTabButton(_ tab: RightPanelTab, icon: String, label: String) -> some View {
        let isActive = appState.rightPanelTab == tab
        return Button {
            appState.rightPanelTab = tab
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11.5))
                Text(label)
                    .font(.system(size: 12, weight: isActive ? .semibold : .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(isActive ? Color(nsColor: .windowBackgroundColor) : Color.clear)
            .foregroundStyle(isActive ? (tab == .ai ? Color.purple : Color.primary) : Color.secondary)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .shadow(color: isActive ? .black.opacity(0.06) : .clear, radius: 2, y: 1)
        }
        .buttonStyle(.plain)
    }

    private var highlightsInspectorList: some View {
        Group {
            if clip.highlights.isEmpty {
                VStack(spacing: 10) {
                    Spacer()
                    Image(systemName: "highlighter")
                        .font(.system(size: 28))
                        .foregroundStyle(.tertiary)
                    Text("选中文章任意段落即可高亮标注")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(clip.highlights) { hl in
                            HighlightCardRow(
                                highlight: hl,
                                onJump: {
                                    contentMode = .article
                                    appState.pendingScrollToHighlightId = hl.id
                                },
                                onQuoteToNote: {
                                    appState.pendingNoteAppendMarkdown = "> \(hl.quote)"
                                    appState.rightPanelTab = .note
                                },
                                onAskAI: {
                                    appState.pendingAIQuoteQuestion = "请解读这段高亮内容：\n\n> \(hl.quote)"
                                    appState.rightPanelTab = .ai
                                },
                                onUpdateNote: { newNote in
                                    appState.updateHighlightNote(id: hl.id, clipId: clip.id, note: newNote)
                                },
                                onDelete: {
                                    appState.removeHighlight(id: hl.id, from: clip.id)
                                }
                            )
                        }
                    }
                    .padding(12)
                }
            }
        }
    }

    private var typographyPopover: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("阅读样式")
                .font(.headline)

            // Theme picker
            Picker("主题", selection: Binding(
                get: { appState.settings.reader.theme },
                set: { appState.settings.reader.theme = $0; appState.saveSettings() }
            )) {
                ForEach(ReaderTheme.allCases, id: \.self) { t in
                    Text(t.displayName).tag(t)
                }
            }
            .pickerStyle(.segmented)

            // Font size
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("字号")
                    Spacer()
                    Text("\(Int(appState.settings.reader.fontSize)) px").foregroundStyle(.secondary)
                }
                .font(.caption)
                Slider(value: Binding(
                    get: { appState.settings.reader.fontSize },
                    set: { appState.settings.reader.fontSize = $0; appState.saveSettings() }
                ), in: 14...24, step: 1)
            }

            // Line height
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("行距")
                    Spacer()
                    Text(String(format: "%.1f", appState.settings.reader.lineHeight)).foregroundStyle(.secondary)
                }
                .font(.caption)
                Slider(value: Binding(
                    get: { appState.settings.reader.lineHeight },
                    set: { appState.settings.reader.lineHeight = $0; appState.saveSettings() }
                ), in: 1.4...2.2, step: 0.1)
            }

            // Width
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("页宽")
                    Spacer()
                    Text("\(Int(appState.settings.reader.contentWidth)) px").foregroundStyle(.secondary)
                }
                .font(.caption)
                Slider(value: Binding(
                    get: { appState.settings.reader.contentWidth },
                    set: { appState.settings.reader.contentWidth = $0; appState.saveSettings() }
                ), in: 560...920, step: 20)
            }

            // Font Family
            Picker("字体", selection: Binding(
                get: { appState.settings.reader.fontFamily },
                set: { appState.settings.reader.fontFamily = $0; appState.saveSettings() }
            )) {
                Text("系统默认 (苹方)").tag("-apple-system, 'PingFang SC', 'Helvetica Neue', sans-serif")
                Text("优雅衬线 (宋体 / Charter)").tag("'Songti SC', Charter, Georgia, serif")
                Text("等宽代码体").tag("ui-monospace, 'SF Mono', Menlo, monospace")
            }
        }
        .padding(16)
        .frame(width: 280)
    }

    private var tagPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("文章标签").font(.headline)
            HStack {
                TextField("输入新标签并回车", text: $newTagInput)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { addTag() }
                Button("添加") { addTag() }
                    .disabled(newTagInput.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if !clip.tags.isEmpty {
                FlowTagView(tags: clip.tags) { removed in
                    var copy = clip
                    copy.tags.removeAll { $0 == removed }
                    appState.updateClip(copy)
                }
            }
        }
        .padding(14)
        .frame(width: 260)
    }

    private func addTag() {
        let t = newTagInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        var copy = clip
        if !copy.tags.contains(t) {
            copy.tags.append(t)
            appState.updateClip(copy)
        }
        newTagInput = ""
    }
}

public struct HighlightCardRow: View {
    let highlight: HighlightItem
    let onJump: () -> Void
    let onQuoteToNote: () -> Void
    let onAskAI: () -> Void
    let onUpdateNote: (String) -> Void
    let onDelete: () -> Void

    @State private var isEditingNote = false
    @State private var noteDraft = ""

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(highlight.color.swiftUIColor)
                    .frame(width: 4)
                Text(highlight.quote)
                    .font(.system(size: 13))
                    .lineSpacing(3)
                    .textSelection(.enabled)
            }
            .contentShape(Rectangle())
            .onTapGesture { onJump() }

            if isEditingNote {
                HStack {
                    TextField("写下你的批注…", text: $noteDraft)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                        .onSubmit {
                            onUpdateNote(noteDraft)
                            isEditingNote = false
                        }
                    Button("保存") {
                        onUpdateNote(noteDraft)
                        isEditingNote = false
                    }
                    .controlSize(.small)
                }
            } else if !highlight.note.isEmpty {
                Text(highlight.note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 14)
            }

            HStack(spacing: 12) {
                Button("批注") {
                    noteDraft = highlight.note
                    isEditingNote.toggle()
                }
                Button("入笔记") { onQuoteToNote() }
                Button("✨ 问AI") { onAskAI() }
                    .foregroundStyle(.purple)
                Spacer()
                Button(role: .destructive) { onDelete() } label: {
                    Image(systemName: "trash")
                }
            }
            .font(.caption)
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.07), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

public struct FlowTagView: View {
    let tags: [String]
    let onRemove: (String) -> Void

    public var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 6)], alignment: .leading, spacing: 6) {
            ForEach(tags, id: \.self) { tag in
                HStack(spacing: 4) {
                    Text("#\(tag)")
                        .font(.caption)
                        .lineLimit(1)
                    Button {
                        onRemove(tag)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.accentColor.opacity(0.12))
                .clipShape(Capsule())
            }
        }
    }
}
