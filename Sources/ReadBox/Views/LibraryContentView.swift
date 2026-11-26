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
            VStack(spacing: 0) {
                // Top Header Bar (Cubox style)
                topHeaderBar

                // Optional Clipboard Detection Banner
                if let detected = appState.clipboardMonitor.detectedURL {
                    clipboardBanner(urlString: detected)
                }

                // Filter & View Switcher Bar
                filterBar

                Divider()

                // Main Grid / List Content
                if appState.filteredClips.isEmpty {
                    emptyStateView
                } else {
                    ScrollView {
                        if appState.viewMode == .cards {
                            LazyVGrid(columns: gridColumns, spacing: 14) {
                                ForEach(appState.filteredClips) { clip in
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
                                    .contextMenu {
                                        clipContextMenu(clip)
                                    }
                                }
                            }
                            .padding(20)
                            .padding(.bottom, appState.isMultiSelectMode ? 76 : 16)
                        } else {
                            LazyVStack(spacing: 6) {
                                ForEach(appState.filteredClips) { clip in
                                    ClipListRowView(
                                        clip: clip,
                                        isSelected: appState.selectedClipIds.contains(clip.id),
                                        isMultiSelect: appState.isMultiSelectMode,
                                        folderName: appState.folderName(for: clip.folderId)
                                    )
                                    .onTapGesture { handleClipTap(clip) }
                                    .contextMenu { clipContextMenu(clip) }
                                }
                            }
                            .padding(16)
                            .padding(.bottom, appState.isMultiSelectMode ? 76 : 16)
                        }
                    }
                }
            }

            // Floating Batch Action Bar during multi-select
            if appState.isMultiSelectMode && !appState.selectedClipIds.isEmpty {
                batchActionBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, 18)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var topHeaderBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(destinationTitle)
                        .font(.system(size: 20, weight: .bold))
                    Text("\(appState.filteredClips.count)")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.12))
                        .clipShape(Capsule())
                }
            }

            Spacer()

            // Spotlight Quick Search trigger
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
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(width: 210)
                .background(Color(nsColor: .controlBackgroundColor))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.08), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)

            // Quick Add Clip Button
            Button {
                appState.quickAddPrefillURL = ""
                appState.showQuickAddSheet = true
            } label: {
                Label("收藏", systemImage: "plus")
                    .font(.system(size: 12.5, weight: .medium))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)

            // Global AI Side Panel Toggle
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    appState.showGlobalAIDrawer.toggle()
                }
            } label: {
                Label("AI 问全库", systemImage: "sparkles")
                    .font(.system(size: 12.5, weight: .medium))
            }
            .buttonStyle(.bordered)
            .tint(appState.showGlobalAIDrawer ? .purple : .secondary)
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
            .buttonStyle(.borderedProminent)
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
        .background(Color.accentColor.opacity(0.08))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.accentColor.opacity(0.2), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }

    private var filterBar: some View {
        HStack(spacing: 12) {
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

            Spacer()

            if appState.isClipping {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("正在抓取解析文章与图片…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // AI Knowledge Synthesis shortcut
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
            .buttonStyle(.bordered)
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
            Text("点击右上角「+ 收藏」或按 ⌘N 粘贴微信公众号 / 网页链接，开启你的 AI 阅读与知识沉淀。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            Button {
                appState.showQuickAddSheet = true
            } label: {
                Label("立即收藏第一篇文章", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
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
            .buttonStyle(.borderedProminent)
            .tint(.purple)

            Menu("移入收藏夹") {
                Button("收集箱（无收藏夹）") {
                    for id in appState.selectedClipIds {
                        if let c = appState.clips.first(where: { $0.id == id }) {
                            appState.moveClip(c, toFolderId: nil)
                        }
                    }
                    appState.selectedClipIds.removeAll()
                }
                Divider()
                ForEach(appState.folders) { folder in
                    Button("\(folder.emoji) \(folder.name)") {
                        for id in appState.selectedClipIds {
                            if let c = appState.clips.first(where: { $0.id == id }) {
                                appState.moveClip(c, toFolderId: folder.id)
                            }
                        }
                        appState.selectedClipIds.removeAll()
                    }
                }
            }
            .menuStyle(.borderedButton)

            Button("归档") {
                for id in appState.selectedClipIds {
                    if let c = appState.clips.first(where: { $0.id == id }) {
                        appState.toggleArchive(c)
                    }
                }
                appState.selectedClipIds.removeAll()
            }
            .buttonStyle(.bordered)

            Button("取消") {
                appState.selectedClipIds.removeAll()
                appState.isMultiSelectMode = false
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.1), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.16), radius: 18, y: 6)
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

/// Cubox-style Detail Card (2-line title, 2-line excerpt, square rounded thumbnail, tag pills, metadata footer).
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
                        .clipShape(RoundedRectangle(cornerRadius: 8))
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
                            .background(Color.primary.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 5))
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
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text(folderName)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Text("·")
                    .foregroundStyle(.tertiary)

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
                        .background(Color.yellow.opacity(0.65))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }

                if !clip.isRead {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 6, height: 6)
                }
            }
        }
        .padding(14)
        .frame(height: 158)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    isSelected ? Color.accentColor : (isHovered ? Color.primary.opacity(0.18) : Color.primary.opacity(0.07)),
                    lineWidth: isSelected ? 2 : 1
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(isHovered ? 0.08 : 0.03), radius: isHovered ? 8 : 3, y: 2)
        .animation(.easeOut(duration: 0.14), value: isHovered)
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
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
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
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color(nsColor: .controlBackgroundColor))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.primary.opacity(0.06), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 9))
    }
}
