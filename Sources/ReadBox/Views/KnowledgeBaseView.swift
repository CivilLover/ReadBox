import SwiftUI
import AppKit

/// Distilled Knowledge Base workspace: browse `.md` knowledge docs on the left,
/// edit with the single-pane WYSIWYG Markdown editor on the right, and export to iCloud/local folders anytime.
public struct KnowledgeBaseView: View {
    @EnvironmentObject var appState: AppState
    @State private var editableTitle: String = ""
    @State private var loadedDocId: String = ""
    @State private var newTagInput: String = ""
    @AppStorage("readbox.knowledgeListWidth") private var docListWidth: Double = 270

    public var body: some View {
        ResizableLeadingSplitView(
            leadingWidth: $docListWidth,
            minLeadingWidth: 210,
            maxLeadingWidth: 340,
            minTrailingWidth: 300
        ) {
            // Left Document List
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("知识沉淀库")
                            .font(.system(size: 16, weight: .bold))
                        Text("纯 Markdown · 兼容 iCloud 与 Obsidian")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        _ = appState.createBlankKnowledgeDoc()
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .buttonStyle(.borderless)
                    .help("新建空白知识文档")

                    Button {
                        appState.synthesisTargetClipIds = appState.clips.filter { !$0.isArchived }.prefix(6).map(\.id)
                        appState.showSynthesisSheet = true
                    } label: {
                        Image(systemName: "sparkles")
                            .foregroundStyle(.purple)
                    }
                    .buttonStyle(.borderless)
                    .help("让 AI 从收藏归纳新知识文档")
                }
                .padding(14)

                Divider()

                if appState.knowledgeDocs.isEmpty {
                    VStack(spacing: 10) {
                        Spacer()
                        Image(systemName: "sparkles.rectangle.stack")
                            .font(.system(size: 32))
                            .foregroundStyle(.tertiary)
                        Text("暂无知识沉淀")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Button("✨ 让 AI 整理收藏生成第一篇") {
                            appState.synthesisTargetClipIds = appState.clips.filter { !$0.isArchived }.prefix(6).map(\.id)
                            appState.showSynthesisSheet = true
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.purple)
                        .controlSize(.small)
                        Spacer()
                    }
                } else {
                    List(selection: $appState.activeKnowledgeDocId) {
                        ForEach(appState.knowledgeDocs) { doc in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(doc.title)
                                    .font(.system(size: 13.5, weight: .semibold))
                                    .lineLimit(1)
                                Text(doc.content.replacingOccurrences(of: "\n", with: " "))
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                HStack(spacing: 6) {
                                    if let model = doc.generatedByModel, !model.isEmpty {
                                        Label(model, systemImage: "sparkles")
                                            .font(.system(size: 10))
                                            .foregroundStyle(.purple)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    Text(doc.updatedAt, style: .date)
                                        .font(.system(size: 10))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .padding(.vertical, 4)
                            .tag(doc.id)
                            .contextMenu {
                                Button("导出到 iCloud / 本地目录…") {
                                    appState.exportKnowledgeDocToUserFolder(doc)
                                }
                                Button("在 Finder 中显示 .md 文件") {
                                    NSWorkspace.shared.activateFileViewerSelecting([appState.vault.knowledgeFileURL(for: doc)])
                                }
                                Divider()
                                Button("删除", role: .destructive) {
                                    appState.deleteKnowledgeDoc(doc)
                                }
                            }
                        }
                    }
                    .listStyle(.inset)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } trailing: {
            // Right Full-Width Single-Pane WYSIWYG Editor
            if let doc = appState.activeKnowledgeDoc {
                VStack(spacing: 0) {
                    // Editor Toolbar
                    HStack(spacing: 10) {
                        TextField("文档标题", text: $editableTitle)
                            .textFieldStyle(.plain)
                            .font(.system(size: 18, weight: .bold))
                            .onChange(of: editableTitle) { _, newVal in
                                guard loadedDocId == doc.id, newVal != doc.title else { return }
                                var copy = doc
                                copy.title = newVal
                                appState.saveKnowledgeDoc(copy)
                            }

                        Spacer()

                        Button {
                            appState.exportKnowledgeDocToUserFolder(doc)
                        } label: {
                            Label("导出到目录 / iCloud", systemImage: "square.and.arrow.up")
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([appState.vault.knowledgeFileURL(for: doc)])
                        } label: {
                            Image(systemName: "folder")
                        }
                        .buttonStyle(.borderless)
                        .help("在 Finder 中显示此 Markdown 文件")
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
                    .padding(.bottom, 8)

                    // Tags & Source Links Metadata Bar
                    HStack(spacing: 8) {
                        ForEach(doc.tags, id: \.self) { tag in
                            HStack(spacing: 3) {
                                Text("#\(tag)")
                                Button {
                                    var copy = doc
                                    copy.tags.removeAll { $0 == tag }
                                    appState.saveKnowledgeDoc(copy)
                                } label: {
                                    Image(systemName: "xmark").font(.system(size: 8))
                                }
                                .buttonStyle(.plain)
                            }
                            .font(.caption)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Color.purple.opacity(0.1))
                            .clipShape(Capsule())
                        }

                        TextField("+ 标签", text: $newTagInput)
                            .textFieldStyle(.plain)
                            .font(.caption)
                            .frame(width: 72)
                            .onSubmit {
                                let t = newTagInput.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !t.isEmpty else { return }
                                var copy = doc
                                if !copy.tags.contains(t) {
                                    copy.tags.append(t)
                                    appState.saveKnowledgeDoc(copy)
                                }
                                newTagInput = ""
                            }

                        Spacer()

                        if !doc.sourceClipIds.isEmpty {
                            Text("参考来源：\(doc.sourceClipIds.count) 篇收藏")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 10)

                    Divider()

                    WYSIWYGEditorView(
                        documentId: "knowledge:\(doc.id)",
                        markdown: doc.content,
                        pendingAppend: nil,
                        onMarkdownChange: { newMD in
                            var copy = doc
                            copy.content = newMD
                            appState.saveKnowledgeDoc(copy)
                        },
                        onConsumeAppend: {}
                    )
                }
                .onAppear { syncTitle(doc) }
                .onChange(of: doc.id) { _, _ in syncTitle(doc) }
            } else {
                ContentUnavailableView(
                    "选择或新建一篇知识沉淀",
                    systemImage: "doc.richtext",
                    description: Text("单栏所见即所得 Markdown 编辑，自动保存为透明 .md 文件")
                )
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func syncTitle(_ doc: KnowledgeDoc) {
        loadedDocId = doc.id
        editableTitle = doc.title
    }
}

/// Cubox-style 2-column All Annotations view (`All Annotations` with colored vertical bars).
public struct AnnotationsView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedColorFilter: HighlightColor? = nil

    private var filteredAnnotations: [(clip: ClipItem, highlight: HighlightItem)] {
        if let color = selectedColorFilter {
            return appState.allHighlights.filter { $0.highlight.color == color }
        }
        return appState.allHighlights
    }

    private let columns = [
        GridItem(.adaptive(minimum: 300, maximum: 460), spacing: 14)
    ]

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("全部标注")
                    .font(.system(size: 20, weight: .bold))
                Text("\(filteredAnnotations.count)")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(Capsule())

                Spacer()

                // 5-Color Filter Pills
                HStack(spacing: 6) {
                    Button("全部") { selectedColorFilter = nil }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(selectedColorFilter == nil ? .accentColor : .secondary)

                    ForEach(HighlightColor.allCases, id: \.self) { color in
                        Button {
                            selectedColorFilter = (selectedColorFilter == color) ? nil : color
                        } label: {
                            Circle()
                                .fill(color.swiftUIColor)
                                .frame(width: 14, height: 14)
                                .overlay(
                                    Circle().stroke(Color.primary, lineWidth: selectedColorFilter == color ? 2 : 0)
                                )
                        }
                        .buttonStyle(.plain)
                        .help(color.displayName)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            if filteredAnnotations.isEmpty {
                ContentUnavailableView(
                    "暂无高亮标注",
                    systemImage: "highlighter",
                    description: Text("阅读任意收藏文章时，选中文字即可添加多色高亮标注。")
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(filteredAnnotations, id: \.highlight.id) { pair in
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(alignment: .top, spacing: 10) {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(pair.highlight.color.swiftUIColor)
                                        .frame(width: 4)
                                    Text(pair.highlight.quote)
                                        .font(.system(size: 13.5))
                                        .lineSpacing(4)
                                        .lineLimit(6)
                                }

                                if !pair.highlight.note.isEmpty {
                                    Text(pair.highlight.note)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .padding(.leading, 14)
                                }

                                Divider()

                                HStack {
                                    Image(systemName: pair.clip.sourceType.systemImage)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(pair.clip.title)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                    Spacer()
                                    Text("跳转原文 →")
                                        .font(.caption2)
                                        .foregroundStyle(.blue)
                                }
                            }
                            .padding(14)
                            .readBoxGlassCard(cornerRadius: 12, isSelected: false, isHovered: false)
                            .onTapGesture {
                                appState.activeClipId = pair.clip.id
                                appState.pendingScrollToHighlightId = pair.highlight.id
                            }
                        }
                    }
                    .padding(20)
                }
            }
        }
        .background(LiquidGlassCanvasBackground())
    }
}
