import SwiftUI
import AppKit

@main
struct ReadBoxApp: App {
    @StateObject private var appState = AppState()

    init() {
        // Ensure standard macOS regular GUI app behavior when run from CLI or .app bundle
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        WindowGroup("ReadBox") {
            MainWorkspaceView()
                .environmentObject(appState)
                .onOpenURL { url in
                    appState.handleIncomingURL(url)
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .defaultSize(width: 1240, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("收藏新网页 / 公众号…") {
                    appState.quickAddPrefillURL = ""
                    appState.showQuickAddSheet = true
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("新建知识沉淀文档") {
                    _ = appState.createBlankKnowledgeDoc()
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            }

            CommandMenu("工作台") {
                Button("快速查找 / 全文搜索") {
                    appState.showQuickSearchOverlay.toggle()
                }
                .keyboardShortcut("k", modifiers: .command)

                Button("聚焦查找") {
                    appState.showQuickSearchOverlay = true
                }
                .keyboardShortcut("f", modifiers: .command)

                Divider()

                Button("切换右侧 AI / 笔记侧边栏") {
                    withAnimation {
                        if appState.activeClipId != nil {
                            appState.isRightPanelOpen.toggle()
                        } else {
                            appState.showGlobalAIDrawer.toggle()
                        }
                    }
                }
                .keyboardShortcut("l", modifiers: .command)

                Button("AI 归纳沉淀为知识库…") {
                    appState.synthesisTargetClipIds = appState.clips.filter { !$0.isArchived }.prefix(6).map(\.id)
                    appState.showSynthesisSheet = true
                }
                .keyboardShortcut("g", modifiers: [.command, .shift])

                Divider()

                Button("刷新并重建全文索引") {
                    appState.reloadVaultData()
                    appState.showToast("已刷新知识库")
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }

        // Native macOS Menu Bar Helper
        MenuBarExtra("ReadBox", systemImage: "books.vertical.fill") {
            MenuBarQuickSaveView()
                .environmentObject(appState)
        }
        .menuBarExtraStyle(.window)

        // Native macOS Preferences Window (⌘,)
        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}
