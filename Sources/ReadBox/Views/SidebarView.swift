import SwiftUI

public struct SidebarView: View {
    @EnvironmentObject var appState: AppState
    @State private var showNewFolderPopover = false
    @State private var newFolderName = ""
    @State private var newFolderEmoji = "📁"
    @State private var newFolderParentId: String? = nil

    @State private var showNewTagPopover = false
    @State private var newTagName = ""
    @State private var renamingTag: TagItem? = nil
    @State private var renameTagDraft = ""

    @State private var expandedFolderIds: Set<String> = ["folder-tech"]
    @State private var dropTargetedDestination: SidebarDestination? = nil

    private let emojiChoices = ["📁", "💻", "🤖", "💡", "📚", "🎨", "📈", "🧠", "🛠️", "🌱", "🔖", "⚡️"]

    public var body: some View {
        VStack(spacing: 0) {
            List(selection: Binding(
                get: { appState.destination },
                set: { newDest in
                    appState.destination = newDest
                    appState.activeClipId = nil
                }
            )) {
                Section("阅读空间") {
                    droppableNavRow(.inbox, title: "收集箱", icon: "tray.fill", tint: .blue) { ids in
                        appState.moveClips(ids: ids, toFolderId: nil)
                    }
                    navRow(.all, title: "全部收藏", icon: "square.grid.2x2.fill", tint: .secondary)
                    navRow(.unread, title: "未读", icon: "circle.inset.filled", tint: .orange)
                    droppableNavRow(.starred, title: "星标", icon: "star.fill", tint: .yellow) { ids in
                        appState.starClips(ids: ids)
                    }
                    navRow(.knowledgeBase, title: "知识沉淀", icon: "sparkles.rectangle.stack.fill", tint: .purple)
                    navRow(.annotations, title: "全部标注", icon: "highlighter", tint: .mint)
                    droppableNavRow(.archived, title: "已归档", icon: "archivebox.fill", tint: .gray) { ids in
                        appState.archiveClips(ids: ids)
                    }
                }

                // Folders section with Sort Menu + New Folder ⊕ (Cubox style)
                Section {
                    let topFolders = appState.sortedFolders(parentId: nil)
                    ForEach(topFolders) { folder in
                        folderTreeRow(folder, depth: 0)
                    }
                } header: {
                    HStack(spacing: 6) {
                        Text("收藏夹")
                        Spacer()

                        Menu {
                            Text("收藏夹排序")
                            Divider()
                            ForEach(SidebarSortOrder.allCases, id: \.self) { order in
                                Button {
                                    appState.settings.folderSortOrder = order
                                    appState.saveSettings()
                                } label: {
                                    HStack {
                                        Text(order.displayName)
                                        if appState.settings.folderSortOrder == order {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            Image(systemName: "arrow.up.arrow.down")
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .fixedSize()
                        .help("收藏夹排序")

                        Button {
                            newFolderParentId = nil
                            newFolderName = ""
                            newFolderEmoji = "📁"
                            showNewFolderPopover = true
                        } label: {
                            Image(systemName: "plus.circle")
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("新建收藏夹")
                    }
                }

                // Tags section with Sort Menu + New Tag ⊕ + ⊘ 无标签 + Drag-to-Tag
                Section {
                    navRow(.untagged, title: "无标签", icon: "nosign", tint: .secondary)

                    ForEach(appState.allTagsWithCount, id: \.tag.id) { item in
                        tagRow(item.tag, count: item.count)
                    }
                } header: {
                    HStack(spacing: 6) {
                        Text("标签")
                        Spacer()

                        Menu {
                            Text("标签排序")
                            Divider()
                            ForEach(SidebarSortOrder.allCases, id: \.self) { order in
                                Button {
                                    appState.settings.tagSortOrder = order
                                    appState.saveSettings()
                                } label: {
                                    HStack {
                                        Text(order.displayName)
                                        if appState.settings.tagSortOrder == order {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            Image(systemName: "arrow.up.arrow.down")
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .fixedSize()
                        .help("标签排序")

                        Button {
                            newTagName = ""
                            showNewTagPopover = true
                        } label: {
                            Image(systemName: "plus.circle")
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("新建标签")
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)

            // Floating Liquid Glass Vault Status Pill at Sidebar Footer
            HStack(spacing: 8) {
                Image(systemName: appState.vault.isUsingiCloudDrive ? "icloud.fill" : "folder.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(appState.vault.isUsingiCloudDrive ? .blue : .secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(appState.vault.isUsingiCloudDrive ? "iCloud Drive 同步" : "本地知识库")
                        .font(.system(size: 11, weight: .semibold))
                    Text(appState.settings.activeProvider.name + " · " + appState.settings.activeModelName)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                SettingsLink {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("偏好设置 (⌘,)")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .readBoxGlassSurface(in: RoundedRectangle(cornerRadius: 12), interactive: false)
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    appState.quickAddPrefillURL = ""
                    appState.showQuickAddSheet = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold))
                }
                .help("快速添加链接 (⌘N)")

                Button {
                    appState.openGlobalSearch()
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 13.5, weight: .semibold))
                }
                .help("全局搜索 / 提问 ReadBox AI (⌘K)")
            }
        }
        .popover(isPresented: $showNewFolderPopover) {
            VStack(alignment: .leading, spacing: 12) {
                Text(newFolderParentId == nil ? "新建收藏夹" : "新建子收藏夹")
                    .font(.headline)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(emojiChoices, id: \.self) { emoji in
                            Button {
                                newFolderEmoji = emoji
                            } label: {
                                Text(emoji)
                                    .font(.system(size: 16))
                                    .padding(5)
                                    .background(newFolderEmoji == emoji ? Color.accentColor.opacity(0.2) : Color.clear)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                TextField("收藏夹名称", text: $newFolderName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { commitNewFolder() }

                HStack {
                    Spacer()
                    Button("取消") { showNewFolderPopover = false }
                    Button("创建") { commitNewFolder() }
                        .readBoxGlassButton(prominent: true)
                        .disabled(newFolderName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(14)
            .frame(width: 260)
        }
        .popover(isPresented: $showNewTagPopover) {
            VStack(alignment: .leading, spacing: 12) {
                Text("新建标签")
                    .font(.headline)
                TextField("输入标签名称（如 AI、产品思考）", text: $newTagName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { commitNewTag() }
                HStack {
                    Spacer()
                    Button("取消") { showNewTagPopover = false }
                    Button("创建") { commitNewTag() }
                        .readBoxGlassButton(prominent: true)
                        .disabled(newTagName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(14)
            .frame(width: 250)
        }
        .sheet(item: $renamingTag) { tag in
            VStack(alignment: .leading, spacing: 12) {
                Text("重命名标签 #\(tag.name)")
                    .font(.headline)
                TextField("新标签名称", text: $renameTagDraft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { commitRenameTag(tag) }
                HStack {
                    Spacer()
                    Button("取消") { renamingTag = nil }
                    Button("保存") { commitRenameTag(tag) }
                        .readBoxGlassButton(prominent: true)
                        .disabled(renameTagDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(18)
            .frame(width: 280)
        }
    }

    private func commitNewFolder() {
        appState.createFolder(name: newFolderName, emoji: newFolderEmoji, parentId: newFolderParentId)
        if let pid = newFolderParentId {
            expandedFolderIds.insert(pid)
        }
        showNewFolderPopover = false
    }

    private func commitNewTag() {
        appState.createTag(name: newTagName)
        showNewTagPopover = false
    }

    private func commitRenameTag(_ tag: TagItem) {
        appState.renameTag(tag, to: renameTagDraft)
        renamingTag = nil
    }

    private func parseDroppedClipIds(_ items: [String]) -> [String] {
        items
            .flatMap { $0.components(separatedBy: ",") }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    @ViewBuilder
    private func navRow(_ dest: SidebarDestination, title: String, icon: String, tint: Color) -> some View {
        let count = appState.countForDestination(dest)
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .frame(width: 18)
            Text(title)
            Spacer()
            if count > 0 {
                Text("\(count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .tag(dest)
    }

    @ViewBuilder
    private func droppableNavRow(_ dest: SidebarDestination, title: String, icon: String, tint: Color, onDrop: @escaping ([String]) -> Void) -> some View {
        let isTargeted = dropTargetedDestination == dest
        navRow(dest, title: title, icon: icon, tint: tint)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isTargeted ? Color.accentColor.opacity(0.24) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isTargeted ? Color.accentColor : Color.clear, lineWidth: 1.5)
            )
            .dropDestination(for: String.self) { items, _ in
                let ids = parseDroppedClipIds(items)
                guard !ids.isEmpty else { return false }
                onDrop(ids)
                return true
            } isTargeted: { targeting in
                withAnimation(.easeOut(duration: 0.12)) {
                    if targeting { dropTargetedDestination = dest }
                    else if dropTargetedDestination == dest { dropTargetedDestination = nil }
                }
            }
    }

    @ViewBuilder
    private func tagRow(_ tag: TagItem, count: Int) -> some View {
        let dest = SidebarDestination.tag(tag.name)
        let isTargeted = dropTargetedDestination == dest
        HStack(spacing: 8) {
            Text("#")
                .foregroundStyle(.secondary)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 16)
            Text(tag.name)
                .lineLimit(1)
            Spacer()
            if count > 0 {
                Text("\(count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isTargeted ? Color.accentColor.opacity(0.26) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isTargeted ? Color.accentColor : Color.clear, lineWidth: 1.5)
        )
        .tag(dest)
        .dropDestination(for: String.self) { items, _ in
            let ids = parseDroppedClipIds(items)
            guard !ids.isEmpty else { return false }
            appState.addTag(tag.name, toClipIds: ids)
            return true
        } isTargeted: { targeting in
            withAnimation(.easeOut(duration: 0.12)) {
                if targeting { dropTargetedDestination = dest }
                else if dropTargetedDestination == dest { dropTargetedDestination = nil }
            }
        }
        .contextMenu {
            Button("重命名标签…") {
                renameTagDraft = tag.name
                renamingTag = tag
            }
            Button("✨ AI 归纳此标签文章沉淀为知识库") {
                let ids = appState.clips.filter { !$0.isArchived && $0.tags.contains(tag.name) }.map(\.id)
                appState.synthesisTargetClipIds = ids
                appState.showSynthesisSheet = true
            }
            Divider()
            Button("删除标签", role: .destructive) {
                appState.deleteTag(tag)
            }
        }
    }

    private func folderTreeRow(_ folder: FolderItem, depth: Int) -> AnyView {
        let children = appState.sortedFolders(parentId: folder.id)
        let isExpanded = expandedFolderIds.contains(folder.id)
        let count = appState.countForDestination(.folder(folder.id))
        let dest = SidebarDestination.folder(folder.id)
        let isTargeted = dropTargetedDestination == dest

        return AnyView(
            Group {
                HStack(spacing: 6) {
                    if !children.isEmpty {
                        Button {
                            if isExpanded { expandedFolderIds.remove(folder.id) }
                            else { expandedFolderIds.insert(folder.id) }
                        } label: {
                            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.secondary)
                                .frame(width: 12)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Spacer().frame(width: 12)
                    }

                    Text(folder.emoji)
                        .font(.system(size: 13))
                    Text(folder.name)
                        .lineLimit(1)
                    Spacer()
                    if count > 0 {
                        Text("\(count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .padding(.leading, CGFloat(depth * 14))
                .padding(.vertical, 3)
                .padding(.horizontal, 4)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isTargeted ? Color.accentColor.opacity(0.28) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isTargeted ? Color.accentColor : Color.clear, lineWidth: 1.5)
                )
                .tag(dest)
                .dropDestination(for: String.self) { items, _ in
                    let ids = parseDroppedClipIds(items)
                    guard !ids.isEmpty else { return false }
                    appState.moveClips(ids: ids, toFolderId: folder.id)
                    return true
                } isTargeted: { targeting in
                    withAnimation(.easeOut(duration: 0.12)) {
                        if targeting { dropTargetedDestination = dest }
                        else if dropTargetedDestination == dest { dropTargetedDestination = nil }
                    }
                }
                .contextMenu {
                    Button("新建子收藏夹…") {
                        newFolderParentId = folder.id
                        newFolderName = ""
                        newFolderEmoji = "📂"
                        showNewFolderPopover = true
                    }
                    Button("✨ AI 归纳此收藏夹沉淀为知识库") {
                        let ids = appState.clips.filter { $0.folderId == folder.id && !$0.isArchived }.map(\.id)
                        appState.synthesisTargetClipIds = ids
                        appState.showSynthesisSheet = true
                    }
                    Divider()
                    Button("删除收藏夹", role: .destructive) {
                        appState.deleteFolder(folder)
                    }
                }

                if isExpanded {
                    ForEach(children) { child in
                        folderTreeRow(child, depth: depth + 1)
                    }
                }
            }
        )
    }
}
