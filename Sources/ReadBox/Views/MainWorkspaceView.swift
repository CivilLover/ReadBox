import SwiftUI

/// Root Workspace combining Cubox-style Sidebar + Library/Reader/KnowledgeBase + optional Global AI Side Drawer + Toast & Search overlays.
public struct MainWorkspaceView: View {
    @EnvironmentObject var appState: AppState

    public var body: some View {
        ZStack {
            NavigationSplitView {
                SidebarView()
                    .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 280)
            } detail: {
                if let activeClip = appState.activeClip {
                    ReaderWorkspaceView(clip: activeClip)
                } else {
                    HSplitView {
                        Group {
                            switch appState.destination {
                            case .knowledgeBase:
                                KnowledgeBaseView()
                            case .annotations:
                                AnnotationsView()
                            default:
                                LibraryContentView()
                            }
                        }
                        .frame(minWidth: 520, maxWidth: .infinity, maxHeight: .infinity)

                        if appState.showGlobalAIDrawer {
                            VStack(spacing: 0) {
                                HStack {
                                    Label("AI 侧边栏（全库对话）", systemImage: "sparkles")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(.purple)
                                    Spacer()
                                    Button {
                                        appState.showGlobalAIDrawer = false
                                    } label: {
                                        Image(systemName: "xmark")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                Divider()
                                AISidebarView(contextClip: nil)
                            }
                            .frame(minWidth: 340, idealWidth: 390, maxWidth: 500, maxHeight: .infinity)
                            .background(.ultraThinMaterial)
                        }
                    }
                }
            }
            .readBoxSeamlessToolbar()

            // Cubox-style Global Search & AI Search Overlay
            if appState.showQuickSearchOverlay {
                GlobalSearchOverlay()
                    .transition(.opacity)
            }

            // Bottom-Right Subtle Liquid Glass Toast Banner
            if let toast = appState.toastMessage {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Text(toast)
                            .font(.system(size: 12.5, weight: .medium))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 9)
                            .readBoxGlassSurface(in: Capsule())
                            .shadow(color: .black.opacity(0.2), radius: 14, y: 5)
                            .padding(20)
                    }
                }
                .allowsHitTesting(false)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .sheet(isPresented: $appState.showQuickAddSheet) {
            QuickAddSheet()
                .environmentObject(appState)
        }
        .sheet(isPresented: $appState.showSynthesisSheet) {
            KnowledgeSynthesisSheet()
                .environmentObject(appState)
        }
        .frame(minWidth: 980, minHeight: 640)
        .environment(\.readBoxGlassPreferences, appState.settings.liquidGlass)
        .preferredColorScheme(appState.settings.liquidGlass.appearance.colorScheme)
    }
}

/// Lightweight macOS Menu Bar Quick-Save Helper (inspired by Cubox Mac Helper).
public struct MenuBarQuickSaveView: View {
    @EnvironmentObject var appState: AppState
    @State private var urlText: String = ""
    @State private var selectedFolderId: String? = nil

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("ReadBox 快速收藏", systemImage: "books.vertical.fill")
                    .font(.headline)
                Spacer()
                if appState.isClipping {
                    ProgressView().controlSize(.small)
                }
            }

            TextField("粘贴微信公众号或网页链接…", text: $urlText)
                .textFieldStyle(.roundedBorder)
                .onSubmit { triggerSave() }

            HStack {
                Picker("放入", selection: $selectedFolderId) {
                    Text("收集箱").tag(Optional<String>.none)
                    ForEach(appState.folders) { f in
                        Text("\(f.emoji) \(f.name)").tag(Optional(f.id))
                    }
                }
                .labelsHidden()

                Spacer()

                Button("粘贴剪贴板") {
                    if let pb = NSPasteboard.general.string(forType: .string) {
                        urlText = pb.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
                .controlSize(.small)

                Button("收藏") { triggerSave() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            Divider()

            HStack {
                Text("共 \(appState.clips.count) 篇收藏 · \(appState.knowledgeDocs.count) 篇沉淀")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    appState.toggleFloatingClipPanel()
                } label: {
                    Text(appState.isFloatingClipVisible ? "隐藏悬浮窗" : "悬浮窗 (\(appState.floatingHotKeyDisplayString))")
                }
                .font(.caption)
                .buttonStyle(.link)

                Button("打开主窗口") {
                    NSApp.activate(ignoringOtherApps: true)
                    if let win = NSApp.windows.first(where: { $0.canBecomeMain }) {
                        win.makeKeyAndOrderFront(nil)
                    }
                }
                .font(.caption)
                .buttonStyle(.link)
            }
        }
        .padding(14)
        .frame(width: 340)
        .onAppear {
            if let detected = appState.clipboardMonitor.detectedURL, urlText.isEmpty {
                urlText = detected
            }
        }
    }

    private func triggerSave() {
        let target = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else { return }
        urlText = ""
        appState.clipboardMonitor.dismissCurrent()
        Task { await appState.addClipFromURL(target, folderId: selectedFolderId) }
    }
}
