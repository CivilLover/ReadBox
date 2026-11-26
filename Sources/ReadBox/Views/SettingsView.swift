import SwiftUI
import AppKit

/// Native macOS Preferences (`⌘,`): Vault & iCloud Drive, Custom AI Providers (DeepSeek BYOK),
/// General behavior, and Reserved Integrations (Obsidian / Notion TODOs).
public struct SettingsView: View {
    @EnvironmentObject var appState: AppState

    public var body: some View {
        TabView {
            AISettingsTab()
                .environmentObject(appState)
                .tabItem { Label("AI 服务商", systemImage: "sparkles") }

            StorageAndSyncTab()
                .environmentObject(appState)
                .tabItem { Label("存储与 iCloud", systemImage: "icloud.fill") }

            GeneralSettingsTab()
                .environmentObject(appState)
                .tabItem { Label("通用设置", systemImage: "gearshape") }

            IntegrationsTodoTab()
                .tabItem { Label("生态集成 (TODO)", systemImage: "puzzlepiece.extension") }
        }
        .frame(width: 640, height: 470)
    }
}

private struct AISettingsTab: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedProviderId: String = "deepseek"
    @State private var apiKeyInput: String = ""
    @State private var customModelInput: String = ""
    @State private var testStatus: String = ""
    @State private var isTesting: Bool = false

    private var selectedIndex: Int? {
        appState.settings.providers.firstIndex(where: { $0.id == selectedProviderId })
    }

    var body: some View {
        HSplitView {
            // Provider List
            VStack(spacing: 0) {
                List(selection: $selectedProviderId) {
                    ForEach(appState.settings.providers) { provider in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(provider.name)
                                    .font(.system(size: 13, weight: .medium))
                                Text(provider.defaultModel)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if appState.settings.activeProviderId == provider.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.purple)
                                    .font(.caption)
                            }
                        }
                        .tag(provider.id)
                    }
                }
                .listStyle(.sidebar)

                Divider()
                HStack {
                    Button {
                        addCustomProvider()
                    } label: {
                        Label("新增自定义", systemImage: "plus")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    Spacer()
                }
                .padding(8)
            }
            .frame(width: 190)

            // Provider Detail Config
            if let idx = selectedIndex {
                let provider = appState.settings.providers[idx]
                Form {
                    Section("服务商配置") {
                        TextField("名称", text: $appState.settings.providers[idx].name)
                        Picker("接口协议", selection: $appState.settings.providers[idx].apiFormat) {
                            ForEach(AIAPIFormat.allCases, id: \.self) { fmt in
                                Text(fmt.displayName).tag(fmt)
                            }
                        }
                        TextField("Base URL", text: $appState.settings.providers[idx].baseURL)
                            .font(.system(.body, design: .monospaced))

                        SecureField(provider.requiresAPIKey ? "粘贴 API Key（安全存于 macOS 钥匙串）" : "本地模型可留空", text: $apiKeyInput)
                            .onChange(of: apiKeyInput) { _, newKey in
                                KeychainService.shared.saveAPIKey(newKey, forProviderId: provider.id)
                            }
                    }

                    Section("模型列表") {
                        Picker("默认模型", selection: $appState.settings.providers[idx].defaultModel) {
                            ForEach(provider.availableModels, id: \.self) { m in
                                Text(m).tag(m)
                            }
                        }
                        HStack {
                            TextField("添加模型 ID（如 deepseek-chat）", text: $customModelInput)
                            Button("添加") {
                                let m = customModelInput.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !m.isEmpty else { return }
                                if !appState.settings.providers[idx].availableModels.contains(m) {
                                    appState.settings.providers[idx].availableModels.append(m)
                                }
                                appState.settings.providers[idx].defaultModel = m
                                customModelInput = ""
                                appState.saveSettings()
                            }
                            .disabled(customModelInput.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }

                    Section {
                        HStack {
                            Button("设为当前使用") {
                                appState.settings.activeProviderId = provider.id
                                appState.settings.activeModelName = appState.settings.providers[idx].defaultModel
                                appState.saveSettings()
                                testStatus = "已切换为 \(provider.name) · \(appState.settings.activeModelName)"
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.purple)

                            Button(isTesting ? "测试中…" : "测试连通性") {
                                runConnectionTest(provider: appState.settings.providers[idx])
                            }
                            .disabled(isTesting)

                            Spacer()

                            if !["deepseek", "openai", "anthropic", "ollama"].contains(provider.id) {
                                Button("删除", role: .destructive) {
                                    deleteProvider(provider)
                                }
                            }
                        }

                        if !testStatus.isEmpty {
                            Text(testStatus)
                                .font(.caption)
                                .foregroundStyle(testStatus.contains("失败") || testStatus.contains("⚠️") ? .red : .green)
                        }
                    }
                }
                .formStyle(.grouped)
                .onChange(of: appState.settings.providers[idx]) { _, _ in
                    appState.saveSettings()
                }
            }
        }
        .onAppear {
            selectedProviderId = appState.settings.activeProviderId
            apiKeyInput = KeychainService.shared.loadAPIKey(forProviderId: selectedProviderId)
        }
        .onChange(of: selectedProviderId) { _, newId in
            apiKeyInput = KeychainService.shared.loadAPIKey(forProviderId: newId)
            testStatus = ""
        }
    }

    private func addCustomProvider() {
        let newP = AIProviderProfile(
            name: "自定义 OpenAI 服务",
            apiFormat: .openAICompatible,
            baseURL: "https://api.example.com/v1",
            defaultModel: "gpt-4o-mini",
            availableModels: ["gpt-4o-mini"]
        )
        appState.settings.providers.append(newP)
        appState.saveSettings()
        selectedProviderId = newP.id
    }

    private func deleteProvider(_ p: AIProviderProfile) {
        KeychainService.shared.deleteAPIKey(forProviderId: p.id)
        appState.settings.providers.removeAll { $0.id == p.id }
        if appState.settings.activeProviderId == p.id {
            appState.settings.activeProviderId = "deepseek"
            appState.settings.activeModelName = "deepseek-chat"
        }
        selectedProviderId = appState.settings.providers.first?.id ?? "deepseek"
        appState.saveSettings()
    }

    private func runConnectionTest(provider: AIProviderProfile) {
        isTesting = true
        testStatus = ""
        let key = KeychainService.shared.loadAPIKey(forProviderId: provider.id)
        Task {
            do {
                let resp = try await appState.aiService.testConnection(provider: provider, model: provider.defaultModel, apiKey: key)
                testStatus = "✅ 连接成功：\(resp)"
            } catch {
                testStatus = "⚠️ 测试失败：\(error.localizedDescription)"
            }
            isTesting = false
        }
    }
}

private struct StorageAndSyncTab: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Form {
            Section("知识库与收藏存储目录（Local-First 明文 .md）") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: appState.vault.isUsingiCloudDrive ? "icloud.fill" : "folder.fill")
                            .foregroundStyle(appState.vault.isUsingiCloudDrive ? .blue : .secondary)
                        Text(appState.vault.isUsingiCloudDrive ? "当前已启用 iCloud Drive 自动同步" : "当前使用本地目录")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                    Text(appState.vault.vaultURL.path)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)

                    HStack(spacing: 10) {
                        if let iCloudURL = VaultManager.defaultiCloudVaultURL {
                            Button("切换到 iCloud Drive") {
                                appState.switchVaultDirectory(to: iCloudURL)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(appState.vault.vaultURL == iCloudURL)
                        }

                        Button("选择任意本地文件夹…") {
                            chooseCustomVaultFolder()
                        }

                        Button("在 Finder 中打开") {
                            NSWorkspace.shared.open(appState.vault.vaultURL)
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            Section("目录结构与索引维护") {
                Text("• knowledge/：所有 AI 归纳与自建知识文档（纯 Markdown + YAML Frontmatter）\n• clips/：每篇收藏的正文、离线快照、本地化图片与独立笔记 note.md\n• .readbox/index.sqlite：本地全文检索引擎缓存，可随时重建")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)

                Button("重新扫描目录并重建全文索引") {
                    appState.reloadVaultData()
                    appState.showToast("已完成目录同步与全文索引重建")
                }
            }
        }
        .formStyle(.grouped)
    }

    private func chooseCustomVaultFolder() {
        let panel = NSOpenPanel()
        panel.title = "选择 ReadBox 知识库存储目录（支持本地或 iCloud Drive 目录）"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            appState.switchVaultDirectory(to: url)
        }
    }
}

private struct GeneralSettingsTab: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Form {
            Section("采集效率") {
                Toggle("自动监测剪贴板中的微信公众号 / 网页链接", isOn: $appState.settings.clipboardMonitorEnabled)
                Toggle("收藏文章后自动调用 AI 生成快读解读", isOn: $appState.settings.autoInsightOnSave)
            }
            .onChange(of: appState.settings.clipboardMonitorEnabled) { _, _ in appState.saveSettings() }
            .onChange(of: appState.settings.autoInsightOnSave) { _, _ in appState.saveSettings() }

            Section("URL Scheme 快捷联动") {
                Text("支持在 macOS 快捷指令或浏览器书签中调用以下链接直接触发收藏：")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("readbox://save?url=https://mp.weixin.qq.com/...")
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
            }
        }
        .formStyle(.grouped)
    }
}

private struct IntegrationsTodoTab: View {
    var body: some View {
        Form {
            Section("未来生态集成规划（已预留 VaultSyncAdapter 架构）") {
                ForEach(ExternalSyncTarget.allCases) { target in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(target.title)
                                .font(.system(size: 14, weight: .semibold))
                            Spacer()
                            Text(target.statusBadge)
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.orange.opacity(0.14))
                                .foregroundStyle(.orange)
                                .clipShape(Capsule())
                        }
                        Text(target.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineSpacing(3)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .formStyle(.grouped)
    }
}
