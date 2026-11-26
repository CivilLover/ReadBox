import SwiftUI
import AppKit

/// Native macOS Preferences (`⌘,`): Vault & iCloud Drive, Custom AI Providers (DeepSeek BYOK),
/// General behavior, and Reserved Integrations (Obsidian / Notion TODOs).
public struct SettingsView: View {
    @EnvironmentObject var appState: AppState

    public var body: some View {
        TabView {
            AppearanceSettingsTab()
                .environmentObject(appState)
                .tabItem { Label("外观与玻璃", systemImage: "paintbrush.pointed.fill") }

            AISettingsTab()
                .environmentObject(appState)
                .tabItem { Label("AI 服务商", systemImage: "sparkles") }

            StorageAndSyncTab()
                .environmentObject(appState)
                .tabItem { Label("存储与 iCloud", systemImage: "icloud.fill") }

            SiteLoginSettingsTab()
                .environmentObject(appState)
                .tabItem { Label("站点登录 / Cookie", systemImage: "person.badge.key.fill") }

            GeneralSettingsTab()
                .environmentObject(appState)
                .tabItem { Label("通用设置", systemImage: "gearshape") }

            IntegrationsTodoTab()
                .tabItem { Label("生态集成 (TODO)", systemImage: "puzzlepiece.extension") }
        }
        .frame(width: 700, height: 575)
        .environment(\.readBoxGlassPreferences, appState.settings.liquidGlass)
    }
}

private struct AppearanceSettingsTab: View {
    @EnvironmentObject var appState: AppState

    private var prefs: Binding<LiquidGlassPreferences> {
        $appState.settings.liquidGlass
    }

    var body: some View {
        VStack(spacing: 0) {
            // Sticky Live Preview Card at top so adjustments are visible immediately without scrolling
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("实时预览", systemImage: "eye.fill")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    presetButton("标准玻璃", target: .standard)
                    presetButton("通透晶莹", target: .crystalClear)
                    presetButton("柔雾磨砂", target: .softFrosted)
                    presetButton("极简纯色", target: .minimalSolid)
                }

                LiquidGlassLivePreviewCard(preferences: appState.settings.liquidGlass)
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider()

            Form {
                Section("界面外观与液态玻璃材质") {
                    Picker("外观模式", selection: prefs.appearance) {
                        ForEach(AppAppearanceMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    Picker("玻璃材质风格", selection: prefs.materialStyle) {
                        ForEach(LiquidGlassMaterialStyle.allCases, id: \.self) { style in
                            Text(style.displayName).tag(style)
                        }
                    }

                    Text(appState.settings.liquidGlass.materialStyle.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Toggle("收藏卡片启用玻璃半透明效果", isOn: prefs.cardTranslucent)
                        .disabled(appState.settings.liquidGlass.materialStyle == .solid)
                }

                Section("背景氛围与折射光影") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("背景光晕主题")
                            .font(.subheadline)
                        HStack(spacing: 8) {
                            ForEach(LiquidGlassAmbientTheme.allCases, id: \.self) { theme in
                                let active = appState.settings.liquidGlass.ambientTheme == theme
                                Button {
                                    appState.settings.liquidGlass.ambientTheme = theme
                                } label: {
                                    HStack(spacing: 6) {
                                        Circle()
                                            .fill(
                                                LinearGradient(
                                                    colors: [theme.accentColor, theme.secondaryColor],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            )
                                            .frame(width: 13, height: 13)
                                        Text(theme.displayName)
                                            .font(.system(size: 11.5, weight: active ? .semibold : .regular))
                                    }
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 5)
                                    .background(active ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.05))
                                    .overlay(
                                        Capsule().stroke(active ? Color.accentColor : Color.clear, lineWidth: 1.2)
                                    )
                                    .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.vertical, 2)

                    sliderRow(
                        title: "背景光晕强度",
                        valueText: "\(Int(appState.settings.liquidGlass.ambientIntensity * 100))%",
                        value: prefs.ambientIntensity,
                        range: 0.0...1.5,
                        step: 0.05
                    )

                    sliderRow(
                        title: "玻璃着色浓度",
                        valueText: appState.settings.liquidGlass.glassTintOpacity < 0.01 ? "无着色" : "\(Int(appState.settings.liquidGlass.glassTintOpacity * 100))%",
                        value: prefs.glassTintOpacity,
                        range: 0.0...0.35,
                        step: 0.01
                    )

                    sliderRow(
                        title: "玻璃边缘高光",
                        valueText: "\(Int(appState.settings.liquidGlass.rimHighlightOpacity * 100))%",
                        value: prefs.rimHighlightOpacity,
                        range: 0.0...1.0,
                        step: 0.05
                    )
                }

                Section {
                    HStack {
                        Text("所有调整会实时生效于主窗口，并自动保存。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("恢复默认液态玻璃") {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                appState.settings.liquidGlass = .standard
                            }
                        }
                        .controlSize(.small)
                    }
                }
            }
            .formStyle(.grouped)
        }
        .onChange(of: appState.settings.liquidGlass) { _, _ in
            appState.saveSettings()
        }
    }

    private func presetButton(_ title: String, target: LiquidGlassPreferences) -> some View {
        let isActive = appState.settings.liquidGlass.materialStyle == target.materialStyle
            && abs(appState.settings.liquidGlass.ambientIntensity - target.ambientIntensity) < 0.06
            && abs(appState.settings.liquidGlass.glassTintOpacity - target.glassTintOpacity) < 0.02
            && appState.settings.liquidGlass.cardTranslucent == target.cardTranslucent
        return Button(title) {
            withAnimation(.easeInOut(duration: 0.2)) {
                var next = target
                next.appearance = appState.settings.liquidGlass.appearance
                appState.settings.liquidGlass = next
            }
        }
        .font(.system(size: 11, weight: isActive ? .semibold : .regular))
        .padding(.horizontal, 9)
        .padding(.vertical, 3.5)
        .background(isActive ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.06))
        .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
        .clipShape(Capsule())
        .buttonStyle(.plain)
    }

    private func sliderRow(
        title: String,
        valueText: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(valueText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: value, in: range, step: step)
        }
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

private struct SiteLoginSettingsTab: View {
    @EnvironmentObject var appState: AppState
    @State private var presetCounts: [String: Int] = [:]
    @State private var domainSummaries: [DomainCookieSummary] = []
    @State private var loginBrowserURL: String? = nil
    @State private var customURLInput: String = ""

    // Advanced manual cookie import
    @State private var importDomain: String = "zhihu.com"
    @State private var importCookieString: String = ""
    @State private var importStatus: String = ""

    var body: some View {
        Form {
            Section("一键打开内置浏览器登录（Cookie 自动持久保存并复用于剪藏）") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 10)], spacing: 10) {
                    ForEach(PresetLoginSite.defaults) { site in
                        let count = presetCounts[site.domain] ?? 0
                        HStack(spacing: 8) {
                            Image(systemName: site.icon)
                                .foregroundStyle(count > 0 ? .green : .secondary)
                                .frame(width: 20)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(site.name)
                                    .font(.system(size: 12.5, weight: .semibold))
                                Text(count > 0 ? "已保存 \(count) 条 Cookie" : "未登录")
                                    .font(.caption2)
                                    .foregroundStyle(count > 0 ? .green : .secondary)
                            }
                            Spacer()
                            Button(count > 0 ? "查看" : "登录") {
                                loginBrowserURL = site.loginURL
                            }
                            .controlSize(.small)
                        }
                        .padding(8)
                        .background(Color.primary.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }

                HStack {
                    TextField("或输入任意其他站点网址（如 https://...）", text: $customURLInput)
                        .onSubmit { openCustomURL() }
                    Button("打开登录") { openCustomURL() }
                        .disabled(customURLInput.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            Section("已保存登录态的域名（共 \(domainSummaries.count) 个）") {
                if domainSummaries.isEmpty {
                    Text("尚未登录任何站点。点击上方「登录」完成一次登录后，对应站点的 Cookie 会长期保存在本机。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(domainSummaries.prefix(12)) { item in
                        HStack {
                            Text(item.domain)
                                .font(.system(size: 12.5, design: .monospaced))
                            Spacer()
                            Text("\(item.cookieCount) 条")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button("清除", role: .destructive) {
                                Task {
                                    await SiteCookieManager.shared.clearCookies(forDomain: item.domain)
                                    await refreshCookies()
                                }
                            }
                            .controlSize(.small)
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }

            Section("高级：手动导入 Cookie 字符串（可选）") {
                HStack {
                    TextField("域名（如 zhihu.com）", text: $importDomain)
                        .frame(width: 170)
                    SecureField("粘贴浏览器 DevTools 中的 Cookie 值（a=1; b=2）", text: $importCookieString)
                    Button("导入") {
                        Task {
                            let n = await SiteCookieManager.shared.importCookieHeader(importCookieString, forDomain: importDomain)
                            importStatus = n > 0 ? "✅ 已为 \(importDomain) 导入 \(n) 条 Cookie" : "⚠️ 未识别到有效 Cookie（格式应为 key=value; ...）"
                            importCookieString = ""
                            await refreshCookies()
                        }
                    }
                    .disabled(importDomain.trimmingCharacters(in: .whitespaces).isEmpty || importCookieString.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if !importStatus.isEmpty {
                    Text(importStatus)
                        .font(.caption)
                        .foregroundStyle(importStatus.hasPrefix("✅") ? .green : .orange)
                }
            }
        }
        .formStyle(.grouped)
        .task { await refreshCookies() }
        .sheet(isPresented: Binding(
            get: { loginBrowserURL != nil },
            set: { if !$0 { loginBrowserURL = nil } }
        )) {
            if let urlStr = loginBrowserURL {
                SiteLoginBrowserSheet(initialURLString: urlStr) {
                    Task { await refreshCookies() }
                }
            }
        }
    }

    private func openCustomURL() {
        let trimmed = customURLInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        loginBrowserURL = trimmed.hasPrefix("http") ? trimmed : "https://\(trimmed)"
    }

    private func refreshCookies() async {
        var counts: [String: Int] = [:]
        for site in PresetLoginSite.defaults {
            counts[site.domain] = await SiteCookieManager.shared.cookieCount(matchingDomain: site.domain)
        }
        presetCounts = counts
        domainSummaries = await SiteCookieManager.shared.loggedInDomains()
    }
}

private struct GeneralSettingsTab: View {
    @EnvironmentObject var appState: AppState
    @State private var isRecordingHotKey: Bool = false
    @State private var hotKeyMonitor: Any? = nil
    @State private var recorderHint: String? = nil

    private var isCustomHotKey: Bool {
        appState.settings.floatingCapture.hotKeyCode != FloatingCaptureSettings.defaultHotKeyCode
            || appState.settings.floatingCapture.hotKeyModifiers != FloatingCaptureSettings.defaultHotKeyModifiers
    }

    var body: some View {
        Form {
            Section("快捷悬浮收集窗（液态玻璃）") {
                Toggle("始终在桌面显示悬浮收集窗", isOn: $appState.settings.floatingCapture.alwaysVisible)
                    .onChange(of: appState.settings.floatingCapture.alwaysVisible) { _, newValue in
                        if newValue {
                            appState.saveSettings()
                        } else {
                            appState.hideFloatingClipPanel()
                            appState.saveSettings()
                        }
                    }

                Toggle("启用全局快捷键快速唤出 / 隐藏", isOn: $appState.settings.floatingCapture.globalHotKeyEnabled)
                    .onChange(of: appState.settings.floatingCapture.globalHotKeyEnabled) { _, _ in
                        stopRecordingHotKey()
                        appState.saveSettings()
                    }

                HStack {
                    Text("全局唤出快捷键")
                    Spacer()

                    if isRecordingHotKey {
                        Text("请按下组合键（Esc 取消）…")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.blue)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.12))
                            .overlay(Capsule().stroke(Color.blue.opacity(0.5), lineWidth: 1))
                            .clipShape(Capsule())

                        Button("取消") {
                            stopRecordingHotKey()
                        }
                        .controlSize(.small)
                    } else {
                        Text(appState.floatingHotKeyDisplayString)
                            .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 3.5)
                            .background(Color.primary.opacity(0.07))
                            .clipShape(Capsule())

                        Button("录制快捷键") {
                            startRecordingHotKey()
                        }
                        .controlSize(.small)
                        .disabled(!appState.settings.floatingCapture.globalHotKeyEnabled)

                        if isCustomHotKey {
                            Button("恢复默认") {
                                appState.settings.floatingCapture.hotKeyCode = FloatingCaptureSettings.defaultHotKeyCode
                                appState.settings.floatingCapture.hotKeyModifiers = FloatingCaptureSettings.defaultHotKeyModifiers
                                appState.saveSettings()
                            }
                            .controlSize(.small)
                            .buttonStyle(.borderless)
                        }
                    }
                }

                if let hint = recorderHint {
                    Text(hint)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                if let err = appState.hotKeyRegistrationError {
                    Text("⚠️ \(err)")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                Toggle("存入收集箱后自动收起悬浮窗（仅按需唤出模式）", isOn: $appState.settings.floatingCapture.autoHideAfterSave)
                    .disabled(appState.settings.floatingCapture.alwaysVisible)
                    .onChange(of: appState.settings.floatingCapture.autoHideAfterSave) { _, _ in
                        appState.saveSettings()
                    }

                HStack {
                    Text("在浏览器或微信复制文章链接后，按快捷键唤出悬浮窗或直接粘贴，回车即刻存入收集箱。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(appState.isFloatingClipVisible ? "隐藏悬浮窗" : "立即打开悬浮窗") {
                        appState.toggleFloatingClipPanel()
                    }
                    .controlSize(.small)
                }
            }

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
        .onDisappear {
            if isRecordingHotKey {
                stopRecordingHotKey()
                appState.syncFloatingCaptureSystem()
            }
        }
    }

    private func startRecordingHotKey() {
        stopRecordingHotKey()
        recorderHint = nil
        isRecordingHotKey = true
        appState.suspendGlobalHotKey()

        hotKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // Escape cancels
                stopRecordingHotKey()
                appState.syncFloatingCaptureSystem()
                return nil
            }
            let code = UInt32(event.keyCode)
            let mods = GlobalHotKeyFormatter.carbonModifiers(from: event.modifierFlags)
            if GlobalHotKeyFormatter.isValidHotKey(keyCode: code, carbonModifiers: mods) {
                appState.settings.floatingCapture.hotKeyCode = code
                appState.settings.floatingCapture.hotKeyModifiers = mods
                stopRecordingHotKey()
                appState.saveSettings()
                return nil
            } else {
                recorderHint = "请同时按下 ⌘ / ⌥ / ⌃ 修饰键与一个字母或数字键"
                return nil
            }
        }
    }

    private func stopRecordingHotKey() {
        if let monitor = hotKeyMonitor {
            NSEvent.removeMonitor(monitor)
            hotKeyMonitor = nil
        }
        isRecordingHotKey = false
        recorderHint = nil
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
