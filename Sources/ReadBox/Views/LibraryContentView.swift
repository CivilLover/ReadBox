import SwiftUI
import AppKit

public struct LibraryContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var hoveredClipId: String? = nil

    private var destinationTitle: String {
        switch appState.destination {
        case .inbox: return "收集箱"
        case .all: return "全部收藏"
        case .unread: return "未读文章"
        case .starred: return "星标精选"
        case .archived: return "已归档"
        case .folder(let fid):
            if let f = appState.folders.first(where: { $0.id == fid }) {
                return "\(f.emoji) \(f.name)"
            }
            return "收藏夹"
        case .tag(let tag): return "#\(tag)"
        case .knowledgeBase: return "知识沉淀"
        case .annotations: return "全部标注"
        }
    }

    private let gridColumns = [
        GridItem(.adaptive(minimum: 270, maximum: 380), spacing: 14)
    ]

    public var body: some View {
        ZStack(alignment: .bottom) {
            LiquidGlassCanvasBackground()

            VStack(spacing: 0) {
                topHeaderBar

                if let detected = appState.clipboardMonitor.detectedURL {
                    clipboardBanner(urlString: detected)
                }

                filterBar

                if appState.filteredClips.isEmpty {
                    emptyStateView
                } else {
                    ScrollView {
                        if appState.viewMode == .cards {
                            LazyVGrid(columns: gridColumns, spacing: 14) {
                                ForEach(appState.filteredClips) { clip in
                                    let dragIds = dragIdsForClip(clip)
                                    ClipCardView(
                                        clip: clip,
                                        isSelected: appState.selectedClipIds.contains(clip.id),
                                        isMultiSelect: appState.isMultiSelectMode,
                                        isHovered: hoveredClipId == clip.id,
                                        folderName: appState.folderName(for: clip.folderId),
                                        coverURL: appState.vault.coverImageURL(for: clip)
                                    )
                                    .onHover { hovering in
                                        hoveredClipId = hovering ? clip.id : (hoveredClipId == clip.id ? nil : hoveredClipId)
                                    }
                                    .onTapGesture {
                                        handleClipTap(clip)
                                    }
                                    .draggable(dragIds.joined(separator: ",")) {
                                        dragPreviewBadge(title: clip.title, count: dragIds.count)
                                    }
                                    .contextMenu {
                                        clipContextMenu(clip)
                                    }
                                }
                            }
                            .padding(20)
                            .padding(.bottom, appState.isMultiSelectMode ? 84 : 20)
                        } else {
                            LazyVStack(spacing: 8) {
                                ForEach(appState.filteredClips) { clip in
                                    let dragIds = dragIdsForClip(clip)
                                    ClipListRowView(
                                        clip: clip,
                                        isSelected: appState.selectedClipIds.contains(clip.id),
                                        isMultiSelect: appState.isMultiSelectMode,
                                        folderName: appState.folderName(for: clip.folderId)
                                    )
                                    .onTapGesture { handleClipTap(clip) }
                                    .draggable(dragIds.joined(separator: ",")) {
                                        dragPreviewBadge(title: clip.title, count: dragIds.count)
                                    }
                                    .contextMenu { clipContextMenu(clip) }
                                }
                            }
                            .padding(16)
                            .padding(.bottom, appState.isMultiSelectMode ? 84 : 20)
                        }
                    }
                }
            }

            // Floating Liquid Glass Batch Action Bar
            if appState.isMultiSelectMode && !appState.selectedClipIds.isEmpty {
                batchActionBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, 18)
            }
        }
    }

    private func dragIdsForClip(_ clip: ClipItem) -> [String] {
        if appState.isMultiSelectMode && appState.selectedClipIds.contains(clip.id) && appState.selectedClipIds.count > 1 {
            return Array(appState.selectedClipIds)
        }
        return [clip.id]
    }

    private func dragPreviewBadge(title: String, count: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: count > 1 ? "doc.on.doc.fill" : "doc.text.fill")
                .foregroundStyle(.blue)
            Text(title)
                .font(.system(size: 12.5, weight: .semibold))
                .lineLimit(1)
                .frame(maxWidth: 200, alignment: .leading)
            if count > 1 {
                Text("\(count)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color.blue)
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .readBoxGlassSurface(in: RoundedRectangle(cornerRadius: 12))
    }

    private var topHeaderBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Text(destinationTitle)
                    .font(.system(size: 22, weight: .bold))
                Text("\(appState.filteredClips.count)")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .readBoxGlassSurface(in: Capsule())
            }

            Spacer()

            // Liquid Glass Spotlight Search Pill
            Button {
                appState.showQuickSearchOverlay = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12))
                    Text("快速查找")
                        .font(.system(size: 12.5))
                    Spacer()
                    Text("⌘K")
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .frame(width: 215)
                .readBoxGlassSurface(in: Capsule(), interactive: true)
            }
            .buttonStyle(.plain)

            // Prominent Liquid Glass Quick Add Button
            Button {
                appState.quickAddPrefillURL = ""
                appState.showQuickAddSheet = true
            } label: {
                Label("收藏", systemImage: "plus")
                    .font(.system(size: 12.5, weight: .semibold))
            }
            .readBoxGlassButton(prominent: true, tint: .blue)

            // Liquid Glass AI Library Drawer Toggle
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    appState.showGlobalAIDrawer.toggle()
                }
            } label: {
                Label("AI 问全库", systemImage: "sparkles")
                    .font(.system(size: 12.5, weight: .medium))
            }
            .readBoxGlassButton(prominent: appState.showGlobalAIDrawer, tint: .purple)
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private func clipboardBanner(urlString: String) -> some View {
        let isWeChat = urlString.contains("mp.weixin.qq.com")
        return HStack(spacing: 10) {
            Image(systemName: isWeChat ? "message.fill" : "link.badge.plus")
                .foregroundStyle(isWeChat ? .green : .blue)
            VStack(alignment: .leading, spacing: 1) {
                Text(isWeChat ? "检测到剪贴板中的微信公众号文章" : "检测到剪贴板中的新链接")
                    .font(.system(size: 12, weight: .semibold))
                Text(urlString)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Button("一键收藏") {
                let target = urlString
                appState.clipboardMonitor.dismissCurrent()
                Task { await appState.addClipFromURL(target) }
            }
            .readBoxGlassButton(prominent: true, tint: .blue)
            .controlSize(.small)

            Button {
                appState.clipboardMonitor.dismissCurrent()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .readBoxGlassSurface(in: RoundedRectangle(cornerRadius: 14), tint: .blue.opacity(0.18))
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }

    private var filterBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 10) {
                Menu {
                    ForEach(LibrarySortOrder.allCases, id: \.self) { order in
                        Button {
                            appState.sortOrder = order
                        } label: {
                            HStack {
                                Text(order.rawValue)
                                if appState.sortOrder == order { Image(systemName: "checkmark") }
                            }
                        }
                    }
                } label: {
                    Label(appState.sortOrder.rawValue, systemImage: "arrow.up.arrow.down")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                Divider().frame(height: 12)

                Menu {
                    Button("不限来源") { appState.sourceFilter = nil }
                    Divider()
                    ForEach(ClipSourceType.allCases, id: \.self) { type in
                        Button(type.displayName) { appState.sourceFilter = type }
                    }
                } label: {
                    Label(appState.sourceFilter?.displayName ?? "不限来源", systemImage: "line.3.horizontal.decrease")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .readBoxGlassSurface(in: Capsule())

            Text("提示：直接拖拽卡片到左侧收藏夹即可快速归类")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .lineLimit(1)

            Spacer()

            if appState.isClipping {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("正在抓取解析文章与图片…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .readBoxGlassSurface(in: Capsule())
            }

            Button {
                if appState.isMultiSelectMode {
                    appState.isMultiSelectMode = false
                    appState.selectedClipIds.removeAll()
                } else {
                    appState.isMultiSelectMode = true
                }
            } label: {
                Label(appState.isMultiSelectMode ? "退出多选" : "多选 / AI 沉淀", systemImage: appState.isMultiSelectMode ? "checkmark.circle.fill" : "checklist")
                    .font(.system(size: 12, weight: .medium))
            }
            .readBoxGlassButton(prominent: appState.isMultiSelectMode, tint: .purple)
            .controlSize(.small)

            Picker("", selection: $appState.viewMode) {
                Image(systemName: "square.grid.2x2").tag(LibraryViewMode.cards)
                Image(systemName: "list.bullet").tag(LibraryViewMode.list)
            }
            .pickerStyle(.segmented)
            .frame(width: 72)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 10)
    }

    private var emptyStateView: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "tray")
                .font(.system(size: 42))
                .foregroundStyle(.tertiary)
            Text("这里还没有收藏内容")
                .font(.headline)
            Text("点击左上角「+」或按 ⌘N 粘贴微信公众号 / 知乎 / 任意网页链接，开启你的 AI 阅读与知识沉淀。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            Button {
                appState.showQuickAddSheet = true
            } label: {
                Label("立即收藏第一篇文章", systemImage: "plus")
            }
            .readBoxGlassButton(prominent: true, tint: .blue)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var batchActionBar: some View {
        HStack(spacing: 12) {
            Text("已选 \(appState.selectedClipIds.count) 篇")
                .font(.system(size: 13, weight: .semibold))

            Divider().frame(height: 18)

            Button {
                appState.synthesisTargetClipIds = Array(appState.selectedClipIds)
                appState.showSynthesisSheet = true
            } label: {
                Label("AI 归纳沉淀为知识库", systemImage: "sparkles")
            }
            .readBoxGlassButton(prominent: true, tint: .purple)

            Menu("移入收藏夹") {
                Button("收集箱（无收藏夹）") {
                    appState.moveClips(ids: Array(appState.selectedClipIds), toFolderId: nil)
                    appState.selectedClipIds.removeAll()
                }
                Divider()
                ForEach(appState.folders) { folder in
                    Button("\(folder.emoji) \(folder.name)") {
                        appState.moveClips(ids: Array(appState.selectedClipIds), toFolderId: folder.id)
                        appState.selectedClipIds.removeAll()
                    }
                }
            }
            .menuStyle(.borderedButton)

            Button("归档") {
                appState.archiveClips(ids: Array(appState.selectedClipIds))
                appState.selectedClipIds.removeAll()
            }
            .readBoxGlassButton()

            Button("取消") {
                appState.selectedClipIds.removeAll()
                appState.isMultiSelectMode = false
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .readBoxGlassSurface(in: Capsule())
        .shadow(color: .black.opacity(0.22), radius: 22, y: 8)
    }

    private func handleClipTap(_ clip: ClipItem) {
        if appState.isMultiSelectMode {
            if appState.selectedClipIds.contains(clip.id) {
                appState.selectedClipIds.remove(clip.id)
            } else {
                appState.selectedClipIds.insert(clip.id)
            }
        } else {
            appState.activeClipId = clip.id
            if !clip.isRead {
                var readClip = clip
                readClip.isRead = true
                appState.updateClip(readClip)
            }
        }
    }

    @ViewBuilder
    private func clipContextMenu(_ clip: ClipItem) -> some View {
        Button("打开阅读") { appState.activeClipId = clip.id }
        Button(clip.isStarred ? "取消星标" : "加星标") { appState.toggleStar(clip) }
        Button(clip.isRead ? "标记为未读" : "标记为已读") { appState.toggleRead(clip) }
        Divider()
        Menu("移动到收藏夹") {
            Button("收集箱") { appState.moveClip(clip, toFolderId: nil) }
            ForEach(appState.folders) { folder in
                Button("\(folder.emoji) \(folder.name)") {
                    appState.moveClip(clip, toFolderId: folder.id)
                }
            }
        }
        Button("✨ AI 沉淀为知识库文档") {
            appState.synthesisTargetClipIds = [clip.id]
            appState.showSynthesisSheet = true
        }
        Button("导出 Markdown 到本地 / iCloud…") {
            appState.exportClipToUserFolder(clip)
        }
        if !clip.url.isEmpty, let url = URL(string: clip.url) {
            Button("在浏览器中打开原文") { NSWorkspace.shared.open(url) }
        }
        Divider()
        Button(clip.isArchived ? "取消归档" : "归档") { appState.toggleArchive(clip) }
        Button("删除", role: .destructive) { appState.deleteClip(clip) }
    }
}

/// Liquid Glass Detail Card (Cubox layout + frosted glass translucency + subtle specular rim light).
public struct ClipCardView: View {
    let clip: ClipItem
    let isSelected: Bool
    let isMultiSelect: Bool
    let isHovered: Bool
    let folderName: String?
    let coverURL: URL?

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M/d"
        return f
    }()

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .top, spacing: 4) {
                        if isMultiSelect {
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(isSelected ? .blue : .secondary)
                                .font(.system(size: 15))
                        }
                        Text(clip.title)
                            .font(.system(size: 14, weight: .semibold))
                            .lineLimit(2)
                            .foregroundStyle(.primary)
                        Spacer(minLength: 0)
                        if clip.isStarred {
                            Image(systemName: "star.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.orange)
                        }
                    }

                    Text(clip.excerpt.isEmpty ? "暂无摘要预览" : clip.excerpt)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                if let coverURL, let nsImage = NSImage(contentsOf: coverURL) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 68, height: 68)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }

            if !clip.tags.isEmpty {
                HStack(spacing: 5) {
                    ForEach(clip.tags.prefix(3), id: \.self) { tag in
                        Text(tag)
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(.primary.opacity(0.07))
                            .clipShape(Capsule())
                    }
                    if clip.tags.count > 3 {
                        Text("+\(clip.tags.count - 3)")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                Image(systemName: clip.sourceType.systemImage)
                    .font(.system(size: 10.5))
                    .foregroundStyle(clip.sourceType == .wechat ? .green : .secondary)

                Text(clip.domain.isEmpty ? clip.sourceType.displayName : clip.domain)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let folderName {
                    Text("·").foregroundStyle(.tertiary)
                    Text(folderName)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Text("·").foregroundStyle(.tertiary)

                Text(Self.dateFmt.string(from: clip.createdAt))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)

                Spacer()

                if !clip.highlights.isEmpty {
                    Text("\(clip.highlights.count)")
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundStyle(Color(red: 0.45, green: 0.30, blue: 0.0))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1.5)
                        .background(Color.yellow.opacity(0.72))
                        .clipShape(Capsule())
                }

                if !clip.isRead {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 6, height: 6)
                }
            }
        }
        .padding(14)
        .frame(height: 160)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    isSelected
                    ? AnyShapeStyle(Color.accentColor)
                    : AnyShapeStyle(LinearGradient(
                        colors: [.white.opacity(isHovered ? 0.38 : 0.2), .white.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )),
                    lineWidth: isSelected ? 2 : 1
                )
        )
        .shadow(color: .black.opacity(isHovered ? 0.14 : 0.05), radius: isHovered ? 12 : 4, y: isHovered ? 4 : 2)
        .scaleEffect(isHovered ? 1.008 : 1.0)
        .animation(.easeOut(duration: 0.16), value: isHovered)
    }
}

public struct ClipListRowView: View {
    let clip: ClipItem
    let isSelected: Bool
    let isMultiSelect: Bool
    let folderName: String?

    public var body: some View {
        HStack(spacing: 10) {
            if isMultiSelect {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? .blue : .secondary)
            }
            Image(systemName: clip.sourceType.systemImage)
                .foregroundStyle(clip.sourceType == .wechat ? .green : .secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(clip.title)
                    .font(.system(size: 13.5, weight: .medium))
                    .lineLimit(1)
                Text(clip.excerpt)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if let folderName {
                Text(folderName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(.primary.opacity(0.06))
                    .clipShape(Capsule())
            }
            if !clip.highlights.isEmpty {
                Text("\(clip.highlights.count) 标注")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
            if clip.isStarred {
                Image(systemName: "star.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(isSelected ? AnyShapeStyle(Color.accentColor.opacity(0.14)) : AnyShapeStyle(.ultraThinMaterial))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.14), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
