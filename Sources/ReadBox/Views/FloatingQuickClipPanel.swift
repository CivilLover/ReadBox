import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - URL Extraction Helper

public enum FloatingURLParser {
    /// Extracts one or more HTTP(S) URLs from pasted or dropped text (supports bare URLs, multi-line URLs,
    /// and share text like "标题 https://mp.weixin.qq.com/s/xxx").
    public static func extractURLs(from raw: String) -> [String] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var results: [String] = []
        var seen = Set<String>()

        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            let nsRange = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
            let matches = detector.matches(in: trimmed, options: [], range: nsRange)
            for m in matches {
                guard let url = m.url,
                      let scheme = url.scheme?.lowercased(),
                      (scheme == "http" || scheme == "https"),
                      url.host != nil else { continue }
                var str = url.absoluteString
                if let swiftRange = Range(m.range, in: trimmed) {
                    let matchedText = trimmed[swiftRange].lowercased()
                    if !matchedText.hasPrefix("http://") && !matchedText.hasPrefix("https://") && str.hasPrefix("http://") {
                        str = "https://" + str.dropFirst("http://".count)
                    }
                }
                if seen.insert(str).inserted {
                    results.append(str)
                }
            }
        }

        if results.isEmpty {
            // Fallback for bare domain/path without scheme like "mp.weixin.qq.com/s/abc"
            for line in trimmed.components(separatedBy: .newlines) {
                let candidate = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !candidate.isEmpty, !candidate.contains(" "), candidate.contains(".") else { continue }
                let withScheme = (candidate.hasPrefix("http://") || candidate.hasPrefix("https://"))
                    ? candidate
                    : "https://\(candidate)"
                if let url = URL(string: withScheme),
                   let host = url.host,
                   host.contains("."),
                   seen.insert(withScheme).inserted {
                    results.append(withScheme)
                }
            }
        }

        return results
    }
}

// MARK: - Non-Activating Floating NSPanel

final class FloatingQuickClipNSPanel: NSPanel {
    var onEscape: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.isFloatingPanel = true
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.hidesOnDeactivate = false
        self.isMovableByWindowBackground = true
        self.animationBehavior = .utilityWindow
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return super.performKeyEquivalent(with: event) }

        // Escape hides/dismisses focus cleanly
        if event.keyCode == 53 {
            onEscape?()
            return true
        }

        // Ensure Cmd+V/C/X/A/Z work even when ReadBox is NOT the frontmost active app
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .command, let key = event.charactersIgnoringModifiers?.lowercased() {
            switch key {
            case "v":
                if NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: self) { return true }
            case "c":
                if NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: self) { return true }
            case "x":
                if NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: self) { return true }
            case "a":
                if NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: self) { return true }
            case "z":
                if NSApp.sendAction(Selector(("undo:")), to: nil, from: self) { return true }
            default:
                break
            }
        } else if flags == [.command, .shift], event.charactersIgnoringModifiers?.lowercased() == "z" {
            if NSApp.sendAction(Selector(("redo:")), to: nil, from: self) { return true }
        }

        return super.performKeyEquivalent(with: event)
    }
}

// MARK: - Window Controller

@MainActor
final class FloatingQuickClipModel: ObservableObject {
    @Published var focusTick: Int = 0
}

@MainActor
public final class FloatingQuickClipController: NSObject, NSWindowDelegate {
    private static let panelSize = NSSize(width: 472, height: 96)

    private weak var appState: AppState?
    private var panel: FloatingQuickClipNSPanel?
    private let model = FloatingQuickClipModel()
    private var isInternalSync = false

    public var isVisible: Bool {
        panel?.isVisible ?? false
    }

    public init(appState: AppState) {
        self.appState = appState
        super.init()
    }

    public func toggleFromHotKey() {
        guard let appState else { return }
        if let panel, panel.isVisible {
            if appState.settings.floatingCapture.alwaysVisible {
                if panel.isKeyWindow {
                    panel.resignKey()
                } else {
                    focusPanel(panel)
                }
            } else {
                hide()
            }
        } else {
            showAndFocus()
        }
    }

    public func toggleVisibility() {
        if isVisible {
            closeByUser()
        } else {
            showAndFocus()
        }
    }

    public func showAndFocus() {
        let p = ensurePanel()
        positionPanelIfNeeded(p)
        focusPanel(p)
        appState?.isFloatingClipVisible = true
    }

    public func showWithoutStealingFocus() {
        let p = ensurePanel()
        positionPanelIfNeeded(p)
        p.orderFrontRegardless()
        appState?.isFloatingClipVisible = true
    }

    public func hide() {
        panel?.orderOut(nil)
        appState?.isFloatingClipVisible = false
    }

    /// Invoked when the user explicitly clicks the close (×) button on the floating pill.
    public func closeByUser() {
        hide()
        if let appState, appState.settings.floatingCapture.alwaysVisible {
            isInternalSync = true
            appState.settings.floatingCapture.alwaysVisible = false
            appState.saveSettings()
            isInternalSync = false
        }
    }

    /// Syncs panel visibility with `settings.floatingCapture.alwaysVisible`.
    public func syncWithSettings() {
        guard !isInternalSync, let appState else { return }
        if appState.settings.floatingCapture.alwaysVisible {
            if !isVisible {
                showWithoutStealingFocus()
            }
        }
    }

    private func focusPanel(_ panel: FloatingQuickClipNSPanel) {
        panel.orderFrontRegardless()
        panel.makeKey()
        model.focusTick += 1
    }

    private func ensurePanel() -> FloatingQuickClipNSPanel {
        if let existing = panel {
            return existing
        }
        let rect = NSRect(origin: .zero, size: Self.panelSize)
        let newPanel = FloatingQuickClipNSPanel(contentRect: rect)
        newPanel.delegate = self
        newPanel.onEscape = { [weak self] in
            guard let self, let appState = self.appState else { return }
            if appState.settings.floatingCapture.alwaysVisible {
                self.panel?.resignKey()
            } else {
                self.hide()
            }
        }

        if let appState {
            let rootView = FloatingQuickClipView(
                model: model,
                onAutoHide: { [weak self] in
                    guard let self, let state = self.appState else { return }
                    if !state.settings.floatingCapture.alwaysVisible && state.settings.floatingCapture.autoHideAfterSave {
                        self.hide()
                    }
                },
                onClose: { [weak self] in
                    self?.closeByUser()
                }
            )
            .environmentObject(appState)

            let hosting = NSHostingView(rootView: rootView)
            hosting.frame = NSRect(origin: .zero, size: Self.panelSize)
            hosting.autoresizingMask = [.width, .height]
            newPanel.contentView = hosting
        }

        self.panel = newPanel
        positionPanelIfNeeded(newPanel)
        return newPanel
    }

    private func positionPanelIfNeeded(_ panel: NSPanel) {
        let size = Self.panelSize
        if let appState,
           let x = appState.settings.floatingCapture.savedOriginX,
           let y = appState.settings.floatingCapture.savedOriginY {
            let candidate = NSRect(x: x, y: y, width: size.width, height: size.height)
            let onSomeScreen = NSScreen.screens.contains { screen in
                screen.visibleFrame.intersects(candidate.insetBy(dx: 40, dy: 20))
            }
            if onSomeScreen {
                panel.setFrameOrigin(NSPoint(x: x, y: y))
                return
            }
        }

        let targetScreen = NSScreen.main ?? NSScreen.screens.first
        let visible = targetScreen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let originX = visible.midX - size.width / 2
        let originY = visible.maxY - size.height - 76
        panel.setFrameOrigin(NSPoint(x: originX, y: originY))
    }

    public func windowDidMove(_ notification: Notification) {
        guard let panel, let appState else { return }
        let origin = panel.frame.origin
        appState.settings.floatingCapture.savedOriginX = origin.x
        appState.settings.floatingCapture.savedOriginY = origin.y
        appState.saveSettingsSilently()
    }
}

// MARK: - Liquid Glass Floating Capsule View

private struct FloatingQuickClipView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var model: FloatingQuickClipModel
    @Environment(\.colorScheme) private var colorScheme

    let onAutoHide: () -> Void
    let onClose: () -> Void

    enum StatusFeedback: Equatable {
        case idle
        case clipping(String)
        case saved(String)
        case notice(String)
    }

    @State private var urlText: String = ""
    @State private var feedback: StatusFeedback = .idle
    @State private var feedbackResetTask: Task<Void, Never>?
    @State private var isDropTargeted: Bool = false
    @FocusState private var isInputFocused: Bool

    private var isPinned: Bool {
        appState.settings.floatingCapture.alwaysVisible
    }

    private var hasClipboardURL: Bool {
        appState.clipboardMonitor.detectedURL != nil
    }

    private var trimmedInput: String {
        urlText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        let glassPrefs = appState.settings.liquidGlass
        ZStack {
            capsuleContent
                .padding(.horizontal, 10)
                .frame(width: 428, height: 54)
                .modifier(FloatingCrystalGlassModifier(
                    ambientTheme: glassPrefs.ambientTheme,
                    isDropTargeted: isDropTargeted
                ))
                .shadow(
                    color: .black.opacity(colorScheme == .dark ? 0.42 : 0.18),
                    radius: 16,
                    x: 0,
                    y: 7
                )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDrop(of: [.url, .plainText], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers: providers)
        }
        .onChange(of: model.focusTick) { _, _ in
            DispatchQueue.main.async {
                isInputFocused = true
            }
        }
        .environment(\.readBoxGlassPreferences, glassPrefs)
        .preferredColorScheme(glassPrefs.appearance.colorScheme)
    }

    private var capsuleContent: some View {
        HStack(spacing: 9) {
            leadingStatusBadge

            ZStack(alignment: .leading) {
                TextField("粘贴链接，回车存入收集箱…", text: $urlText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13.5, weight: .regular))
                    .focused($isInputFocused)
                    .onSubmit {
                        submitInput()
                    }
                    .opacity(shouldOverlayStatus ? 0.02 : 1.0)

                if shouldOverlayStatus {
                    statusLabelView
                        .allowsHitTesting(false)
                        .transition(.opacity.combined(with: .scale(scale: 0.97)))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.easeInOut(duration: 0.18), value: feedback)

            ReadBoxGlassGroup(spacing: 5) {
                HStack(spacing: 5) {
                    if !trimmedInput.isEmpty {
                        Button {
                            submitInput()
                        } label: {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 11.5, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 28, height: 28)
                                .background(
                                    LinearGradient(
                                        colors: [
                                            appState.settings.liquidGlass.ambientTheme.accentColor,
                                            appState.settings.liquidGlass.ambientTheme.secondaryColor
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .clipShape(Circle())
                                .overlay(
                                    Circle().stroke(Color.white.opacity(0.45), lineWidth: 0.8)
                                )
                        }
                        .buttonStyle(.plain)
                        .help("存入收集箱 (↩)")
                    } else {
                        Button {
                            pasteAndClipFromClipboard()
                        } label: {
                            ZStack(alignment: .topTrailing) {
                                Image(systemName: "doc.on.clipboard")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.primary.opacity(0.86))
                                    .frame(width: 28, height: 28)
                                    .modifier(FloatingMiniGlassCircle(active: false))

                                if hasClipboardURL {
                                    Circle()
                                        .fill(appState.settings.liquidGlass.ambientTheme.accentColor)
                                        .frame(width: 6.5, height: 6.5)
                                        .offset(x: -2, y: 2)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .help("一键粘贴剪贴板链接并存入收集箱")
                    }

                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            appState.settings.floatingCapture.alwaysVisible.toggle()
                            appState.saveSettings()
                        }
                    } label: {
                        Image(systemName: isPinned ? "pin.fill" : "pin")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(isPinned ? appState.settings.liquidGlass.ambientTheme.accentColor : .secondary)
                            .frame(width: 28, height: 28)
                            .modifier(FloatingMiniGlassCircle(active: isPinned))
                    }
                    .buttonStyle(.plain)
                    .help(isPinned ? "已开启始终悬浮（点击取消固定）" : "固定在桌面始终显示")

                    Button {
                        onClose()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 26, height: 26)
                            .modifier(FloatingMiniGlassCircle(active: false))
                    }
                    .buttonStyle(.plain)
                    .help("关闭悬浮窗")
                }
            }
        }
    }

    private var shouldOverlayStatus: Bool {
        trimmedInput.isEmpty && feedback != .idle
    }

    @ViewBuilder
    private var leadingStatusBadge: some View {
        ZStack {
            Circle()
                .fill(badgeBackground)
                .frame(width: 30, height: 30)
                .overlay(
                    Circle().stroke(Color.white.opacity(colorScheme == .dark ? 0.22 : 0.55), lineWidth: 0.8)
                )

            switch feedback {
            case .clipping:
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.72)
            case .saved:
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.green)
            case .notice:
                Image(systemName: "exclamationmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.orange)
            case .idle:
                Image(systemName: isDropTargeted ? "arrow.down.circle.fill" : "tray.and.arrow.down.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                appState.settings.liquidGlass.ambientTheme.accentColor,
                                appState.settings.liquidGlass.ambientTheme.secondaryColor
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
        }
        .help("拖动可移动悬浮窗 · 支持直接拖入网页链接")
    }

    private var badgeBackground: Color {
        switch feedback {
        case .saved: return Color.green.opacity(0.16)
        case .notice: return Color.orange.opacity(0.16)
        default: return colorScheme == .dark ? Color.white.opacity(0.10) : Color.white.opacity(0.35)
        }
    }

    @ViewBuilder
    private var statusLabelView: some View {
        switch feedback {
        case .idle:
            EmptyView()
        case .clipping(let msg):
            Text(msg)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        case .saved(let msg):
            Text(msg)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.green)
                .lineLimit(1)
        case .notice(let msg):
            Text(msg)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.orange)
                .lineLimit(1)
        }
    }

    // MARK: - Actions

    private func submitInput() {
        let raw = trimmedInput
        guard !raw.isEmpty else { return }
        let urls = FloatingURLParser.extractURLs(from: raw)
        guard !urls.isEmpty else {
            showTemporaryFeedback(.notice("未识别到有效网址，请粘贴 http(s) 链接"), duration: 2.0)
            return
        }
        urlText = ""
        clipURLsToInbox(urls)
    }

    private func pasteAndClipFromClipboard() {
        guard let pb = NSPasteboard.general.string(forType: .string) else {
            showTemporaryFeedback(.notice("剪贴板暂无链接"), duration: 1.8)
            return
        }
        let urls = FloatingURLParser.extractURLs(from: pb)
        guard !urls.isEmpty else {
            showTemporaryFeedback(.notice("剪贴板未检测到有效网址"), duration: 1.8)
            return
        }
        appState.clipboardMonitor.dismissCurrent()
        clipURLsToInbox(urls)
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        var accepted = false
        for provider in providers {
            if provider.canLoadObject(ofClass: URL.self) {
                accepted = true
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    let str = url.absoluteString
                    Task { @MainActor in
                        let urls = FloatingURLParser.extractURLs(from: str)
                        if !urls.isEmpty {
                            clipURLsToInbox(urls)
                        }
                    }
                }
            } else if provider.canLoadObject(ofClass: String.self) {
                accepted = true
                _ = provider.loadObject(ofClass: String.self) { str, _ in
                    guard let str else { return }
                    Task { @MainActor in
                        let urls = FloatingURLParser.extractURLs(from: str)
                        if !urls.isEmpty {
                            clipURLsToInbox(urls)
                        }
                    }
                }
            }
        }
        return accepted
    }

    private func clipURLsToInbox(_ urls: [String]) {
        feedbackResetTask?.cancel()
        feedback = .clipping(urls.count > 1 ? "正在存入 \(urls.count) 篇到收集箱…" : "正在存入收集箱…")

        Task {
            var savedCount = 0
            var lastTitle = ""
            for u in urls {
                if let saved = await appState.addClipFromURL(u, folderId: nil, tags: []) {
                    savedCount += 1
                    lastTitle = saved.title
                }
            }

            if savedCount > 0 {
                let message = savedCount == 1
                    ? "已存入收集箱 · \(lastTitle)"
                    : "已存入 \(savedCount) 篇到收集箱"
                showTemporaryFeedback(.saved(message), duration: 1.4, autoHideAfter: true)
            } else {
                showTemporaryFeedback(.notice("收集失败，请检查链接或网络"), duration: 2.2)
            }
        }
    }

    private func showTemporaryFeedback(_ next: StatusFeedback, duration: TimeInterval, autoHideAfter: Bool = false) {
        feedback = next
        feedbackResetTask?.cancel()
        feedbackResetTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            feedback = .idle
            if autoHideAfter {
                onAutoHide()
            }
        }
    }
}

// MARK: - Extra-Glassy Liquid Crystal Surface Modifiers

private struct FloatingCrystalGlassModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let ambientTheme: LiquidGlassAmbientTheme
    let isDropTargeted: Bool

    private var rimOverlay: some View {
        let shape = Capsule()
        return ZStack {
            // Subtle inner glass sheen along top arc for unmistakable liquid-glass refraction
            shape.stroke(
                LinearGradient(
                    colors: isDropTargeted
                        ? [ambientTheme.accentColor.opacity(0.95), ambientTheme.secondaryColor.opacity(0.7)]
                        : [
                            Color.white.opacity(colorScheme == .dark ? 0.48 : 0.85),
                            Color.white.opacity(colorScheme == .dark ? 0.10 : 0.22),
                            Color.white.opacity(colorScheme == .dark ? 0.26 : 0.55)
                        ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: isDropTargeted ? 2.0 : 1.1
            )
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = Capsule()
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            // Clear Liquid Glass with whisper-light adaptive frost tint for crystal-clear refraction & legibility
            let crystalTint: Color = isDropTargeted
                ? ambientTheme.accentColor.opacity(0.18)
                : (colorScheme == .dark ? Color.white.opacity(0.05) : Color.white.opacity(0.18))
            content
                .glassEffect(.clear.tint(crystalTint).interactive(), in: shape)
                .overlay(rimOverlay)
        } else {
            legacyCrystalGlass(content, shape: shape)
        }
        #else
        legacyCrystalGlass(content, shape: shape)
        #endif
    }

    @ViewBuilder
    private func legacyCrystalGlass(_ content: Content, shape: Capsule) -> some View {
        content
            .background {
                ZStack {
                    shape.fill(.ultraThinMaterial)
                    shape.fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(colorScheme == .dark ? 0.14 : 0.38),
                                Color.white.opacity(colorScheme == .dark ? 0.03 : 0.08)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    if isDropTargeted {
                        shape.fill(ambientTheme.accentColor.opacity(0.14))
                    }
                }
            }
            .overlay(rimOverlay)
    }
}

private struct FloatingMiniGlassCircle: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let active: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            let tint = active ? Color.accentColor.opacity(0.20) : Color.white.opacity(colorScheme == .dark ? 0.06 : 0.16)
            content
                .glassEffect(.clear.tint(tint).interactive(), in: Circle())
        } else {
            content
                .background(active ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.06))
                .clipShape(Circle())
        }
        #else
        content
            .background(active ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.06))
            .clipShape(Circle())
        #endif
    }
}
