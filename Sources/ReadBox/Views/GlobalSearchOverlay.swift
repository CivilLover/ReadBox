import SwiftUI
import AppKit

/// Cubox-inspired Global Search & AI Search Overlay (`⌘K` / `⌘F` or clicking the toolbar 🔍 next to `+`).
/// Supports:
/// - Instant search across Folders, Tags, Saved Clips ("我的收藏"), and Knowledge Docs
/// - Deep Search ("深度搜索"): Full-Text Search ("全文搜索"), Annotations Search ("标注搜索"), Archive Search ("从归档中搜索")
/// - Inline AI Search / Ask ("提问 ReadBox AI") with RAG source citations & handoff to the Global AI Drawer
public struct GlobalSearchOverlay: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.colorScheme) private var colorScheme

    @State private var query: String = ""
    @State private var mode: GlobalSearchMode = .overview
    @State private var snapshot: GlobalSearchSnapshot = .empty
    @State private var selectedRowIndex: Int = 0
    @State private var allResultsFilter: AllResultsCategory = .all

    // Inline AI Search state
    @State private var aiQuestion: String = ""
    @State private var aiAnswer: String = ""
    @State private var aiReasoning: String = ""
    @State private var aiCitedClips: [ClipItem] = []
    @State private var aiCitedDocs: [KnowledgeDoc] = []
    @State private var isAISearching: Bool = false
    @State private var aiError: String? = nil
    @State private var isReasoningExpanded: Bool = false
    @State private var aiStreamTask: Task<Void, Never>? = nil

    @FocusState private var isInputFocused: Bool

    private enum AllResultsCategory: String, CaseIterable {
        case all = "全部"
        case collections = "收藏夹/标签"
        case clips = "我的收藏"
        case highlights = "标注"
        case knowledge = "知识库"
        case archived = "已归档"
    }

    private enum OverviewRowAction: Equatable {
        case searchAllResults
        case askAI
        case openFolder(String)
        case openTag(String)
        case openClip(String)
        case openKnowledge(String)
        case deepFullText
        case deepAnnotations
        case deepArchived
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Ordered keyboard-navigable rows in `.overview` mode when query is non-empty.
    private var overviewActions: [OverviewRowAction] {
        guard !trimmedQuery.isEmpty else {
            return [.askAI, .deepFullText, .deepAnnotations, .deepArchived]
        }
        var actions: [OverviewRowAction] = [.searchAllResults, .askAI]
        for folder in snapshot.matchingFolders.prefix(3) {
            actions.append(.openFolder(folder.id))
        }
        for item in snapshot.matchingTags.prefix(3) {
            actions.append(.openTag(item.tag.name))
        }
        for hit in snapshot.activeClipHits.prefix(4) {
            actions.append(.openClip(hit.clip.id))
        }
        for hit in snapshot.knowledgeHits.prefix(2) {
            actions.append(.openKnowledge(hit.doc.id))
        }
        actions.append(.deepFullText)
        actions.append(.deepAnnotations)
        actions.append(.deepArchived)
        return actions
    }

    public var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(colorScheme == .dark ? 0.45 : 0.28)
                .ignoresSafeArea()
                .onTapGesture { dismissOverlay() }

            VStack(spacing: 0) {
                searchInputHeader
                    .padding(.horizontal, 14)
                    .padding(.top, 14)
                    .padding(.bottom, 10)

                switch mode {
                case .overview:
                    overviewContent
                case .allResults:
                    allResultsContent
                case .fullText:
                    fullTextResultsContent
                case .annotations:
                    annotationsResultsContent
                case .archived:
                    archivedResultsContent
                case .aiAsk:
                    aiAskContent
                }
            }
            .frame(width: 560)
            .readBoxGlassSurface(in: RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.primary.opacity(colorScheme == .dark ? 0.14 : 0.1), lineWidth: 1)
                    .allowsHitTesting(false)
            )
            .shadow(color: .black.opacity(0.36), radius: 36, y: 16)
            .padding(.top, 46)
        }
        .onAppear {
            mode = appState.quickSearchInitialMode
            selectedRowIndex = 0
            isInputFocused = true
        }
        .onDisappear {
            aiStreamTask?.cancel()
        }
        .onKeyPress(.downArrow) {
            guard mode == .overview else { return .ignored }
            let count = overviewActions.count
            if count > 0 {
                selectedRowIndex = (selectedRowIndex + 1) % count
            }
            return .handled
        }
        .onKeyPress(.upArrow) {
            guard mode == .overview else { return .ignored }
            let count = overviewActions.count
            if count > 0 {
                selectedRowIndex = (selectedRowIndex - 1 + count) % count
            }
            return .handled
        }
        .onKeyPress(.escape) {
            handleEscape()
            return .handled
        }
    }

    // MARK: - Top Pill Search Bar

    private var searchInputHeader: some View {
        HStack(spacing: 8) {
            if mode != .overview {
                Button {
                    returnToOverview()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 10.5, weight: .bold))
                        Text(modeBadgeTitle)
                            .font(.system(size: 11.5, weight: .semibold))
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(modeBadgeColor.opacity(0.18))
                    .foregroundStyle(modeBadgeColor)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("返回全局搜索 (ESC)")
            }

            TextField(searchPlaceholder, text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 14.5))
                .focused($isInputFocused)
                .onChange(of: query) { _, _ in
                    runLiveSearch()
                }
                .onSubmit {
                    handleSubmit()
                }

            if !query.isEmpty {
                Button {
                    query = ""
                    snapshot = .empty
                    selectedRowIndex = 0
                    if mode == .aiAsk {
                        aiStreamTask?.cancel()
                        isAISearching = false
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("清空输入")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(
            Capsule()
                .fill(Color.primary.opacity(colorScheme == .dark ? 0.11 : 0.06))
        )
        .overlay(
            Capsule()
                .stroke(
                    isInputFocused
                        ? Color.primary.opacity(colorScheme == .dark ? 0.55 : 0.34)
                        : Color.primary.opacity(0.14),
                    lineWidth: isInputFocused ? 1.8 : 1
                )
        )
    }

    private var searchPlaceholder: String {
        switch mode {
        case .overview: return "搜索收藏、收藏夹、标签、标注，或直接向 ReadBox AI 提问…"
        case .allResults: return "在所有结果中筛选…"
        case .fullText: return "全文搜索文章正文与笔记…"
        case .annotations: return "搜索高亮引文与批注…"
        case .archived: return "从已归档收藏中搜索…"
        case .aiAsk: return "继续向 ReadBox AI 提问并回车…"
        }
    }

    private var modeBadgeTitle: String {
        switch mode {
        case .overview: return ""
        case .allResults: return "所有结果"
        case .fullText: return "全文搜索"
        case .annotations: return "标注搜索"
        case .archived: return "归档搜索"
        case .aiAsk: return "ReadBox AI"
        }
    }

    private var modeBadgeColor: Color {
        switch mode {
        case .aiAsk: return Color(red: 0.45, green: 0.46, blue: 0.96)
        case .annotations: return .orange
        case .archived: return .secondary
        default: return .accentColor
        }
    }

    // MARK: - Overview Mode (Cubox Layout)

    private var overviewContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                if !trimmedQuery.isEmpty {
                    // 1. Primary Action: 搜索所有结果
                    overviewActionRow(
                        action: .searchAllResults,
                        isPrimarySearch: true
                    ) {
                        HStack(spacing: 10) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color(red: 0.43, green: 0.56, blue: 0.98))
                                .frame(width: 20)
                            Text("搜索所有结果")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Color(red: 0.43, green: 0.56, blue: 0.98))
                            if snapshot.totalResultCount > 0 {
                                Text("\(snapshot.totalResultCount)")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1.5)
                                    .background(Color.primary.opacity(0.08))
                                    .clipShape(Capsule())
                            }
                            Spacer()
                            Image(systemName: "return")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }

                    // 2. AI Action: 提问 ReadBox AI
                    overviewActionRow(action: .askAI) {
                        HStack(spacing: 10) {
                            aiSparkleIcon
                                .frame(width: 20)
                            Text("提问 ReadBox AI")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.primary)
                            Spacer()
                            Text("AI 搜索")
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(Color(red: 0.49, green: 0.53, blue: 0.98))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Color(red: 0.45, green: 0.48, blue: 0.96).opacity(0.14))
                                .clipShape(Capsule())
                        }
                    }

                    // 3. Matching Folders & Tags (收藏夹与标签)
                    if !snapshot.matchingFolders.isEmpty || !snapshot.matchingTags.isEmpty {
                        sectionHeader("收藏夹与标签")

                        ForEach(snapshot.matchingFolders.prefix(3)) { folder in
                            overviewActionRow(action: .openFolder(folder.id)) {
                                HStack(spacing: 10) {
                                    Text(folder.emoji)
                                        .font(.system(size: 14))
                                        .frame(width: 20)
                                    Text(highlightedText(folder.name, keyword: trimmedQuery))
                                        .font(.system(size: 13.5, weight: .medium))
                                        .lineLimit(1)
                                    Spacer()
                                    Text("收藏夹 · \(appState.countForDestination(.folder(folder.id))) 篇")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }

                        ForEach(snapshot.matchingTags.prefix(3), id: \.tag.id) { item in
                            overviewActionRow(action: .openTag(item.tag.name)) {
                                HStack(spacing: 10) {
                                    Text("#")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 20)
                                    Text(highlightedText(item.tag.name, keyword: trimmedQuery))
                                        .font(.system(size: 13.5, weight: .medium))
                                        .lineLimit(1)
                                    Spacer()
                                    Text("标签 · \(item.count) 篇")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    // 4. Saved Collections (我的收藏)
                    sectionHeader("我的收藏")

                    if snapshot.activeClipHits.isEmpty && snapshot.knowledgeHits.isEmpty {
                        Text("暂无直接匹配的收藏，试试「提问 ReadBox AI」或下方深度搜索")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                    } else {
                        ForEach(snapshot.activeClipHits.prefix(4)) { hit in
                            overviewActionRow(action: .openClip(hit.clip.id)) {
                                clipResultRowContent(clip: hit.clip, snippet: hit.snippet, keyword: trimmedQuery)
                            }
                        }

                        ForEach(snapshot.knowledgeHits.prefix(2)) { hit in
                            overviewActionRow(action: .openKnowledge(hit.doc.id)) {
                                knowledgeResultRowContent(doc: hit.doc, snippet: hit.snippet, keyword: trimmedQuery)
                            }
                        }
                    }

                    // 5. Deep Search (深度搜索) — exact 3 rows from reference design
                    sectionHeader("深度搜索")
                    deepSearchRows(showCounts: true)
                } else {
                    // Empty Query State: Quick AI Ask + Folders + Recent Clips + Deep Search
                    overviewActionRow(action: .askAI) {
                        HStack(spacing: 10) {
                            aiSparkleIcon
                                .frame(width: 20)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("提问 ReadBox AI")
                                    .font(.system(size: 13.5, weight: .semibold))
                                Text("输入任意问题，结合你的 \(appState.clips.count) 篇收藏与 \(appState.knowledgeDocs.count) 篇知识文档解答")
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Image(systemName: "arrow.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }

                    if !appState.folders.isEmpty {
                        sectionHeader("快捷进入收藏夹")
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(appState.sortedFolders(parentId: nil).prefix(8)) { folder in
                                    Button {
                                        openFolder(folder.id)
                                    } label: {
                                        HStack(spacing: 5) {
                                            Text(folder.emoji)
                                                .font(.system(size: 12))
                                            Text(folder.name)
                                                .font(.system(size: 12, weight: .medium))
                                            Text("\(appState.countForDestination(.folder(folder.id)))")
                                                .font(.system(size: 10.5))
                                                .foregroundStyle(.secondary)
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(Color.primary.opacity(0.06))
                                        .clipShape(Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                        }
                    }

                    let recentClips = appState.clips.filter { !$0.isArchived }.prefix(4)
                    if !recentClips.isEmpty {
                        sectionHeader("最近收藏")
                        ForEach(recentClips) { clip in
                            Button {
                                openClip(clip.id)
                            } label: {
                                clipResultRowContent(clip: clip, snippet: clip.excerpt, keyword: "")
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 7)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .background(Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }

                    sectionHeader("深度搜索")
                    deepSearchRows(showCounts: false)
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 12)
        }
        .frame(maxHeight: 460)
    }

    @ViewBuilder
    private func deepSearchRows(showCounts: Bool) -> some View {
        overviewActionRow(action: .deepFullText) {
            HStack(spacing: 10) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                Text("全文搜索")
                    .font(.system(size: 14, weight: .medium))
                Spacer()
                if showCounts && !snapshot.fullTextClipHits.isEmpty {
                    countBadge(snapshot.fullTextClipHits.count)
                }
            }
        }

        overviewActionRow(action: .deepAnnotations) {
            HStack(spacing: 10) {
                Image(systemName: "highlighter")
                    .font(.system(size: 13.5))
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                Text("标注搜索")
                    .font(.system(size: 14, weight: .medium))
                Spacer()
                if showCounts && !snapshot.highlightHits.isEmpty {
                    countBadge(snapshot.highlightHits.count)
                }
            }
        }

        overviewActionRow(action: .deepArchived) {
            HStack(spacing: 10) {
                Image(systemName: "archivebox")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                Text("从归档中搜索")
                    .font(.system(size: 14, weight: .medium))
                Spacer()
                if showCounts && !snapshot.archivedClipHits.isEmpty {
                    countBadge(snapshot.archivedClipHits.count)
                }
            }
        }
    }

    private func overviewActionRow<Label: View>(
        action: OverviewRowAction,
        isPrimarySearch: Bool = false,
        @ViewBuilder label: () -> Label
    ) -> some View {
        let rowIndex = overviewActions.firstIndex(of: action)
        let isSelected = rowIndex != nil && rowIndex == selectedRowIndex
        return Button {
            execute(action)
        } label: {
            label()
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(
                            isSelected
                                ? (isPrimarySearch
                                    ? Color(red: 0.30, green: 0.40, blue: 0.85).opacity(colorScheme == .dark ? 0.28 : 0.16)
                                    : Color.accentColor.opacity(colorScheme == .dark ? 0.22 : 0.12))
                                : Color.clear
                        )
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering, let idx = rowIndex {
                selectedRowIndex = idx
            }
        }
    }

    // MARK: - Expanded All Results Mode

    private var allResultsContent: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    categoryTab(.all, count: snapshot.totalResultCount)
                    categoryTab(.collections, count: snapshot.matchingFolders.count + snapshot.matchingTags.count)
                    categoryTab(.clips, count: snapshot.activeClipHits.count)
                    categoryTab(.highlights, count: snapshot.highlightHits.count)
                    categoryTab(.knowledge, count: snapshot.knowledgeHits.count)
                    categoryTab(.archived, count: snapshot.archivedClipHits.count)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
            }

            Divider()

            if trimmedQuery.isEmpty {
                emptySearchPrompt("输入关键词，搜索收藏夹、文章全文、标注、知识库与归档内容")
            } else if snapshot.totalResultCount == 0 {
                emptySearchNoMatchView
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        if (allResultsFilter == .all || allResultsFilter == .collections),
                           (!snapshot.matchingFolders.isEmpty || !snapshot.matchingTags.isEmpty) {
                            sectionHeader("收藏夹与标签")
                            ForEach(snapshot.matchingFolders) { folder in
                                resultCardButton {
                                    openFolder(folder.id)
                                } content: {
                                    HStack(spacing: 10) {
                                        Text(folder.emoji).frame(width: 20)
                                        Text(highlightedText(folder.name, keyword: trimmedQuery))
                                            .font(.system(size: 13.5, weight: .semibold))
                                        Spacer()
                                        Text("\(appState.countForDestination(.folder(folder.id))) 篇")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            ForEach(snapshot.matchingTags, id: \.tag.id) { item in
                                resultCardButton {
                                    openTag(item.tag.name)
                                } content: {
                                    HStack(spacing: 10) {
                                        Text("#").fontWeight(.bold).foregroundStyle(.secondary).frame(width: 20)
                                        Text(highlightedText(item.tag.name, keyword: trimmedQuery))
                                            .font(.system(size: 13.5, weight: .semibold))
                                        Spacer()
                                        Text("\(item.count) 篇")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }

                        if (allResultsFilter == .all || allResultsFilter == .clips), !snapshot.activeClipHits.isEmpty {
                            sectionHeader("我的收藏 (\(snapshot.activeClipHits.count))")
                            ForEach(snapshot.activeClipHits) { hit in
                                resultCardButton {
                                    openClip(hit.clip.id)
                                } content: {
                                    clipResultRowContent(clip: hit.clip, snippet: hit.snippet, keyword: trimmedQuery)
                                }
                            }
                        }

                        if (allResultsFilter == .all || allResultsFilter == .highlights), !snapshot.highlightHits.isEmpty {
                            sectionHeader("标注 (\(snapshot.highlightHits.count))")
                            ForEach(snapshot.highlightHits) { hit in
                                resultCardButton {
                                    openHighlight(hit)
                                } content: {
                                    highlightResultRowContent(hit: hit, keyword: trimmedQuery)
                                }
                            }
                        }

                        if (allResultsFilter == .all || allResultsFilter == .knowledge), !snapshot.knowledgeHits.isEmpty {
                            sectionHeader("知识沉淀 (\(snapshot.knowledgeHits.count))")
                            ForEach(snapshot.knowledgeHits) { hit in
                                resultCardButton {
                                    openKnowledgeDoc(hit.doc.id)
                                } content: {
                                    knowledgeResultRowContent(doc: hit.doc, snippet: hit.snippet, keyword: trimmedQuery)
                                }
                            }
                        }

                        if (allResultsFilter == .all || allResultsFilter == .archived), !snapshot.archivedClipHits.isEmpty {
                            sectionHeader("已归档 (\(snapshot.archivedClipHits.count))")
                            ForEach(snapshot.archivedClipHits) { hit in
                                resultCardButton {
                                    openClip(hit.clip.id)
                                } content: {
                                    clipResultRowContent(clip: hit.clip, snippet: hit.snippet, keyword: trimmedQuery, isArchived: true)
                                }
                            }
                        }
                    }
                    .padding(12)
                }
                .frame(maxHeight: 420)
            }
        }
    }

    private func categoryTab(_ cat: AllResultsCategory, count: Int) -> some View {
        let active = allResultsFilter == cat
        return Button {
            allResultsFilter = cat
        } label: {
            HStack(spacing: 4) {
                Text(cat.rawValue)
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 10.5, weight: .semibold))
                        .opacity(0.75)
                }
            }
            .font(.system(size: 11.5, weight: active ? .semibold : .regular))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(active ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.06))
            .foregroundStyle(active ? Color.accentColor : Color.secondary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Deep Search: Full Text

    private var fullTextResultsContent: some View {
        VStack(spacing: 0) {
            Divider()
            if trimmedQuery.isEmpty {
                emptySearchPrompt("输入关键词，深度检索全部文章正文、离线快照与侧边笔记（SQLite FTS5）")
            } else if snapshot.fullTextClipHits.isEmpty && snapshot.knowledgeHits.isEmpty {
                emptySearchNoMatchView
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        if !snapshot.fullTextClipHits.isEmpty {
                            sectionHeader("文章全文命中 (\(snapshot.fullTextClipHits.count))")
                            ForEach(snapshot.fullTextClipHits) { hit in
                                resultCardButton {
                                    openClip(hit.clip.id)
                                } content: {
                                    clipResultRowContent(clip: hit.clip, snippet: hit.snippet, keyword: trimmedQuery)
                                }
                            }
                        }
                        if !snapshot.knowledgeHits.isEmpty {
                            sectionHeader("知识文档命中 (\(snapshot.knowledgeHits.count))")
                            ForEach(snapshot.knowledgeHits) { hit in
                                resultCardButton {
                                    openKnowledgeDoc(hit.doc.id)
                                } content: {
                                    knowledgeResultRowContent(doc: hit.doc, snippet: hit.snippet, keyword: trimmedQuery)
                                }
                            }
                        }
                    }
                    .padding(12)
                }
                .frame(maxHeight: 420)
            }
        }
    }

    // MARK: - Deep Search: Annotations

    private var annotationsResultsContent: some View {
        let items: [GlobalSearchHighlightHit] = trimmedQuery.isEmpty
            ? appState.allHighlights.prefix(30).map { GlobalSearchHighlightHit(clip: $0.clip, highlight: $0.highlight) }
            : snapshot.highlightHits

        return VStack(spacing: 0) {
            Divider()
            if items.isEmpty {
                emptySearchPrompt(trimmedQuery.isEmpty ? "暂无高亮标注" : "未找到包含「\(trimmedQuery)」的高亮或批注")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        sectionHeader(trimmedQuery.isEmpty ? "最近高亮标注 (\(items.count))" : "标注命中 (\(items.count))")
                        ForEach(items) { hit in
                            resultCardButton {
                                openHighlight(hit)
                            } content: {
                                highlightResultRowContent(hit: hit, keyword: trimmedQuery)
                            }
                        }
                    }
                    .padding(12)
                }
                .frame(maxHeight: 420)
            }
        }
    }

    // MARK: - Deep Search: Archived

    private var archivedResultsContent: some View {
        let items: [GlobalSearchClipHit] = trimmedQuery.isEmpty
            ? appState.clips.filter(\.isArchived).prefix(30).map {
                GlobalSearchClipHit(clip: $0, snippet: $0.excerpt, isFullTextMatch: false)
            }
            : snapshot.archivedClipHits

        return VStack(spacing: 0) {
            Divider()
            if items.isEmpty {
                emptySearchPrompt(trimmedQuery.isEmpty ? "归档箱中暂无收藏" : "已归档收藏中未找到与「\(trimmedQuery)」匹配的内容")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        sectionHeader(trimmedQuery.isEmpty ? "全部已归档 (\(items.count))" : "归档命中 (\(items.count))")
                        ForEach(items) { hit in
                            resultCardButton {
                                openClip(hit.clip.id)
                            } content: {
                                clipResultRowContent(clip: hit.clip, snippet: hit.snippet, keyword: trimmedQuery, isArchived: true)
                            }
                        }
                    }
                    .padding(12)
                }
                .frame(maxHeight: 420)
            }
        }
    }

    // MARK: - Inline ReadBox AI Search / Ask Mode

    private var aiAskContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // Header showing provider + active question
                    HStack(spacing: 8) {
                        aiSparkleIcon
                        Text(aiQuestion.isEmpty ? "向 ReadBox AI 提问" : aiQuestion)
                            .font(.system(size: 13.5, weight: .semibold))
                            .lineLimit(2)
                        Spacer()
                        Text("\(appState.settings.activeProvider.name) · \(appState.settings.activeModelName)")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                    }

                    if aiQuestion.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("在上方输入框输入你想问的问题并按回车，ReadBox AI 会自动检索你的本地收藏、高亮与知识沉淀并给出带来源引用的回答。")
                                .font(.system(size: 12.5))
                                .foregroundStyle(.secondary)
                                .lineSpacing(3)

                            let quickExamples = [
                                "总结我最近收藏中最核心的观点",
                                "查找我收藏里关于 AI 的关键启发",
                                "帮我梳理目前收藏夹的主题脉络"
                            ]
                            HStack(spacing: 6) {
                                ForEach(quickExamples, id: \.self) { ex in
                                    Button(ex) {
                                        query = ex
                                        startAISearch(question: ex)
                                    }
                                    .font(.system(size: 11.5))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color(red: 0.45, green: 0.48, blue: 0.96).opacity(0.14))
                                    .foregroundStyle(Color(red: 0.45, green: 0.50, blue: 0.98))
                                    .clipShape(Capsule())
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    } else {
                        // Reasoning disclosure (DeepSeek R1 etc.)
                        if !aiReasoning.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Button {
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        isReasoningExpanded.toggle()
                                    }
                                } label: {
                                    HStack(spacing: 5) {
                                        Image(systemName: "brain.head.profile")
                                        Text(isReasoningExpanded ? "收起深度思考过程" : "查看深度思考过程")
                                        Image(systemName: isReasoningExpanded ? "chevron.up" : "chevron.down")
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)

                                if isReasoningExpanded {
                                    Text(aiReasoning)
                                        .font(.system(size: 11.5))
                                        .foregroundStyle(.secondary)
                                        .padding(8)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(Color.primary.opacity(0.05))
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                            }
                        }

                        // Answer Body / Loading / Error
                        if let err = aiError {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("⚠️ \(err)")
                                    .font(.system(size: 12.5))
                                    .foregroundStyle(.orange)
                                HStack(spacing: 8) {
                                    Button("打开设置配置 AI 服务商 (⌘,)") {
                                        dismissOverlay()
                                        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                                    }
                                    .controlSize(.small)
                                    .buttonStyle(.borderedProminent)

                                    Button("重试") {
                                        startAISearch(question: aiQuestion)
                                    }
                                    .controlSize(.small)
                                }
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.orange.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        } else if aiAnswer.isEmpty && isAISearching {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text("正在检索本地收藏并生成 AI 回答…")
                                    .font(.system(size: 12.5))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 10)
                        } else {
                            Text(LocalizedStringKey(aiAnswer))
                                .font(.system(size: 13))
                                .lineSpacing(4)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(Color.primary.opacity(0.04))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }

                        // Cited Sources
                        if !aiCitedClips.isEmpty || !aiCitedDocs.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("参考来源（点击直达）")
                                    .font(.system(size: 11.5, weight: .semibold))
                                    .foregroundStyle(.secondary)

                                ForEach(aiCitedClips.prefix(5)) { clip in
                                    Button {
                                        openClip(clip.id)
                                    } label: {
                                        HStack(spacing: 8) {
                                            Image(systemName: clip.sourceType.systemImage)
                                                .font(.system(size: 11))
                                                .foregroundStyle(clip.sourceType == .wechat ? .green : .blue)
                                                .frame(width: 16)
                                            Text(clip.title)
                                                .font(.system(size: 12, weight: .medium))
                                                .lineLimit(1)
                                            Spacer()
                                            Text(clip.domain.isEmpty ? clip.sourceType.displayName : clip.domain)
                                                .font(.caption2)
                                                .foregroundStyle(.tertiary)
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(Color.primary.opacity(0.04))
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                    }
                                    .buttonStyle(.plain)
                                }

                                ForEach(aiCitedDocs.prefix(3)) { doc in
                                    Button {
                                        openKnowledgeDoc(doc.id)
                                    } label: {
                                        HStack(spacing: 8) {
                                            Image(systemName: "sparkles.rectangle.stack.fill")
                                                .font(.system(size: 11))
                                                .foregroundStyle(.purple)
                                                .frame(width: 16)
                                            Text(doc.title)
                                                .font(.system(size: 12, weight: .medium))
                                                .lineLimit(1)
                                            Spacer()
                                            Text("知识库")
                                                .font(.caption2)
                                                .foregroundStyle(.purple)
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(Color.purple.opacity(0.07))
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                .padding(14)
            }
            .frame(maxHeight: 380)

            // Bottom Action Bar for AI Answer
            if !aiQuestion.isEmpty {
                Divider()
                HStack(spacing: 10) {
                    if isAISearching {
                        Button("停止生成", role: .destructive) {
                            aiStreamTask?.cancel()
                            isAISearching = false
                        }
                        .controlSize(.small)
                    } else if !aiAnswer.isEmpty {
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(aiAnswer, forType: .string)
                            appState.showToast("已复制 ReadBox AI 回答")
                        } label: {
                            Label("复制", systemImage: "doc.on.doc")
                        }
                        .controlSize(.small)

                        Button {
                            let doc = appState.saveMarkdownAsKnowledgeDoc(
                                title: "AI 搜索 · \(String(aiQuestion.prefix(24)))",
                                markdown: "## 问题\n\n\(aiQuestion)\n\n## ReadBox AI 回答\n\n\(aiAnswer)",
                                tags: ["AI搜索"],
                                sourceClips: aiCitedClips
                            )
                            dismissOverlay()
                            appState.activeClipId = nil
                            appState.destination = .knowledgeBase
                            appState.activeKnowledgeDocId = doc.id
                        } label: {
                            Label("存入知识库", systemImage: "sparkles.rectangle.stack")
                        }
                        .controlSize(.small)
                    }

                    Spacer()

                    Button {
                        appState.handoffAISearchToGlobalDrawer(
                            question: aiQuestion,
                            answer: aiAnswer,
                            reasoning: aiReasoning,
                            citedTitles: aiCitedClips.map(\.title)
                        )
                    } label: {
                        Label("在右侧 AI 栏继续对话", systemImage: "sidebar.right")
                    }
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.42, green: 0.45, blue: 0.94))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        }
    }

    // MARK: - Shared Row Components

    private var aiSparkleIcon: some View {
        Image(systemName: "sparkle")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(
                LinearGradient(
                    colors: [Color(red: 0.45, green: 0.62, blue: 1.0), Color(red: 0.56, green: 0.42, blue: 0.98)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 2)
    }

    private func countBadge(_ count: Int) -> some View {
        Text("\(count)")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 1.5)
            .background(Color.primary.opacity(0.07))
            .clipShape(Capsule())
    }

    private func clipResultRowContent(clip: ClipItem, snippet: String, keyword: String, isArchived: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: clip.sourceType == .note ? "doc.text" : (clip.sourceType == .wechat ? "message" : "doc.text"))
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(width: 20)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(highlightedText(clip.title, keyword: keyword))
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if isArchived {
                        Text("已归档")
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.primary.opacity(0.08))
                            .clipShape(Capsule())
                    }
                }

                let preview = snippet.isEmpty ? clip.excerpt : snippet
                if !preview.isEmpty {
                    Text(highlightedText("“\(preview)”", keyword: keyword))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 6)

            if let folderName = appState.folderName(for: clip.folderId) {
                Text(folderName)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            } else if !clip.domain.isEmpty {
                Text(clip.domain)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
    }

    private func knowledgeResultRowContent(doc: KnowledgeDoc, snippet: String, keyword: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "sparkles.rectangle.stack")
                .font(.system(size: 13.5))
                .foregroundStyle(.purple)
                .frame(width: 20)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(highlightedText(doc.title, keyword: keyword))
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if !snippet.isEmpty {
                    Text(highlightedText(snippet, keyword: keyword))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 6)

            Text("知识库")
                .font(.caption2)
                .foregroundStyle(.purple)
        }
    }

    private func highlightResultRowContent(hit: GlobalSearchHighlightHit, keyword: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(hit.highlight.color.swiftUIColor)
                .frame(width: 3.5)
                .padding(.vertical, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(highlightedText(hit.highlight.quote, keyword: keyword))
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                if !hit.highlight.note.isEmpty {
                    Text(highlightedText("批注：\(hit.highlight.note)", keyword: keyword))
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Text(hit.clip.title)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer()
        }
    }

    private func resultCardButton<Content: View>(action: @escaping () -> Void, @ViewBuilder content: () -> Content) -> some View {
        Button(action: action) {
            content()
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func emptySearchPrompt(_ message: String) -> some View {
        VStack(spacing: 8) {
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
        }
        .frame(maxWidth: .infinity, minHeight: 150)
        .padding(16)
    }

    private var emptySearchNoMatchView: some View {
        VStack(spacing: 12) {
            Text("未找到与「\(trimmedQuery)」匹配的本地内容")
                .font(.system(size: 13.5))
                .foregroundStyle(.secondary)
            Button {
                startAISearch(question: trimmedQuery)
            } label: {
                HStack(spacing: 6) {
                    aiSparkleIcon
                    Text("改用 ReadBox AI 提问「\(trimmedQuery)」")
                        .font(.system(size: 12.5, weight: .semibold))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Color(red: 0.45, green: 0.48, blue: 0.96).opacity(0.16))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, minHeight: 160)
        .padding(16)
    }

    // MARK: - Keyword Highlight Helper

    private func highlightedText(_ source: String, keyword: String) -> AttributedString {
        var attributed = AttributedString(source)
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return attributed }

        let highlightColor = Color(red: 0.36, green: 0.56, blue: 1.0)
        var searchRange = attributed.startIndex..<attributed.endIndex
        while let found = attributed[searchRange].range(of: trimmed, options: .caseInsensitive) {
            attributed[found].foregroundColor = highlightColor
            attributed[found].font = .system(size: 13, weight: .semibold)
            searchRange = found.upperBound..<attributed.endIndex
        }
        return attributed
    }

    // MARK: - Actions & Navigation

    private func runLiveSearch() {
        snapshot = appState.runGlobalSearch(query: query)
        selectedRowIndex = 0
    }

    private func handleSubmit() {
        switch mode {
        case .overview:
            let actions = overviewActions
            if !actions.isEmpty {
                let idx = min(max(0, selectedRowIndex), actions.count - 1)
                execute(actions[idx])
            }
        case .aiAsk:
            if !trimmedQuery.isEmpty {
                startAISearch(question: trimmedQuery)
            }
        case .allResults, .fullText, .annotations, .archived:
            runLiveSearch()
        }
    }

    private func execute(_ action: OverviewRowAction) {
        switch action {
        case .searchAllResults:
            allResultsFilter = .all
            mode = .allResults
        case .askAI:
            mode = .aiAsk
            if !trimmedQuery.isEmpty {
                startAISearch(question: trimmedQuery)
            }
        case .openFolder(let id):
            openFolder(id)
        case .openTag(let name):
            openTag(name)
        case .openClip(let id):
            openClip(id)
        case .openKnowledge(let id):
            openKnowledgeDoc(id)
        case .deepFullText:
            mode = .fullText
        case .deepAnnotations:
            mode = .annotations
        case .deepArchived:
            mode = .archived
        }
    }

    private func startAISearch(question rawQuestion: String) {
        let q = rawQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }

        aiStreamTask?.cancel()
        mode = .aiAsk
        aiQuestion = q
        aiAnswer = ""
        aiReasoning = ""
        aiError = nil
        isReasoningExpanded = false
        isAISearching = true

        let context = appState.buildGlobalAISearchContext(for: q)
        aiCitedClips = context.citedClips
        aiCitedDocs = context.citedDocs

        let provider = appState.settings.activeProvider
        let model = appState.settings.activeModelName
        let apiKey = KeychainService.shared.loadAPIKey(forProviderId: provider.id)

        aiStreamTask = Task {
            do {
                let stream = appState.aiService.streamChat(
                    provider: provider,
                    model: model,
                    apiKey: apiKey,
                    systemPrompt: context.systemPrompt,
                    messages: [ChatMessage(role: .user, content: q)]
                )
                for try await chunk in stream {
                    if Task.isCancelled { break }
                    aiAnswer += chunk.contentDelta
                    aiReasoning += chunk.reasoningDelta
                }
            } catch {
                if !Task.isCancelled {
                    aiError = error.localizedDescription
                }
            }
            isAISearching = false
        }
    }

    private func returnToOverview() {
        aiStreamTask?.cancel()
        isAISearching = false
        mode = .overview
        selectedRowIndex = 0
        isInputFocused = true
    }

    private func handleEscape() {
        if mode != .overview {
            returnToOverview()
        } else {
            dismissOverlay()
        }
    }

    private func dismissOverlay() {
        aiStreamTask?.cancel()
        appState.showQuickSearchOverlay = false
    }

    private func openFolder(_ folderId: String) {
        dismissOverlay()
        appState.activeClipId = nil
        appState.destination = .folder(folderId)
    }

    private func openTag(_ tagName: String) {
        dismissOverlay()
        appState.activeClipId = nil
        appState.destination = .tag(tagName)
    }

    private func openClip(_ clipId: String) {
        dismissOverlay()
        appState.activeClipId = clipId
    }

    private func openHighlight(_ hit: GlobalSearchHighlightHit) {
        dismissOverlay()
        appState.activeClipId = hit.clip.id
        appState.pendingScrollToHighlightId = hit.highlight.id
    }

    private func openKnowledgeDoc(_ docId: String) {
        dismissOverlay()
        appState.activeClipId = nil
        appState.destination = .knowledgeBase
        appState.activeKnowledgeDocId = docId
    }
}
