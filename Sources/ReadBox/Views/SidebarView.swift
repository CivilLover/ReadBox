import SwiftUI

public struct SidebarView: View {
    @EnvironmentObject var appState: AppState
    @State private var showNewFolderPopover = false
    @State private var newFolderName = ""
    @State private var newFolderEmoji = "📁"
    @State private var newFolderParentId: String? = nil
    @State private var expandedFolderIds: Set<String> = ["folder-tech"]

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
                    navRow(.inbox, title: "收集箱", icon: "tray.fill", tint: .blue)
                    navRow(.all, title: "全部收藏", icon: "square.grid.2x2.fill", tint: .secondary)
                    navRow(.unread, title: "未读", icon: "circle.inset.filled", tint: .orange)
                    navRow(.starred, title: "星标", icon: "star.fill", tint: .yellow)
                    navRow(.knowledgeBase, title: "知识沉淀", icon: "sparkles.rectangle.stack.fill", tint: .purple)
                    navRow(.annotations, title: "全部标注", icon: "highlighter", tint: .mint)
                    navRow(.archived, title: "已归档", icon: "archivebox.fill", tint: .gray)
                }

                Section {
                    let topFolders = appState.folders.filter { $0.parentId == nil }
                    ForEach(topFolders) { folder in
                        folderTreeRow(folder, depth: 0)
                    }
                } header: {
                    HStack {
                        Text("收藏夹")
                        Spacer()
                        Button {
                            newFolderParentId = nil
                            newFolderName = ""
                            newFolderEmoji = "📁"
                            showNewFolderPopover = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .buttonStyle(.plain)
                        .help("新建收藏夹")
                    }
                }

                if !appState.allTagsWithCount.isEmpty {
                    Section("标签") {
                        ForEach(appState.allTagsWithCount, id: \.tag) { item in
                            HStack(spacing: 8) {
                                Text("#")
                                    .foregroundStyle(.secondary)
                                    .font(.system(size: 13, weight: .semibold))
                                Text(item.tag)
                                    .lineLimit(1)
                                Spacer()
                                Text("\(item.count)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .tag(SidebarDestination.tag(item.tag))
                        }
                    }
                }
            }
            .listStyle(.sidebar)

            Divider()

            // Vault status + Settings footer
            HStack(spacing: 8) {
                Image(systemName: appState.vault.isUsingiCloudDrive ? "icloud.fill" : "folder.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(appState.vault.isUsingiCloudDrive ? .blue : .secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(appState.vault.isUsingiCloudDrive ? "iCloud Drive 同步中" : "本地知识库")
                        .font(.system(size: 11, weight: .medium))
                    Text(appState.settings.activeProvider.name + " · " + appState.settings.activeModelName)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                SettingsLink {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("偏好设置 (⌘,)")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
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
                        .buttonStyle(.borderedProminent)
                        .disabled(newFolderName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(14)
            .frame(width: 260)
        }
    }

    private func commitNewFolder() {
        appState.createFolder(name: newFolderName, emoji: newFolderEmoji, parentId: newFolderParentId)
        if let pid = newFolderParentId {
            expandedFolderIds.insert(pid)
        }
        showNewFolderPopover = false
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

    private func folderTreeRow(_ folder: FolderItem, depth: Int) -> AnyView {
        let children = appState.folders.filter { $0.parentId == folder.id }
        let isExpanded = expandedFolderIds.contains(folder.id)
        let count = appState.countForDestination(.folder(folder.id))

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
                .tag(SidebarDestination.folder(folder.id))
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
