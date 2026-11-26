import SwiftUI
import WebKit

/// Built-in persistent-cookie Safari-engine browser sheet for signing into websites
/// (e.g. Zhihu, Xiaohongshu, Juejin, Medium, Substack) so ReadBox can clip authenticated pages automatically.
public struct SiteLoginBrowserSheet: View {
    @Environment(\.dismiss) private var dismiss
    public let initialURLString: String
    public var onDismissRefresh: (() -> Void)? = nil

    @State private var addressText: String = ""
    @State private var currentURL: URL?
    @State private var currentCookieCount: Int = 0
    @State private var isLoading: Bool = false
    @State private var navCommand: LoginWebViewCommand? = nil

    public init(initialURLString: String, onDismissRefresh: (() -> Void)? = nil) {
        self.initialURLString = initialURLString
        self.onDismissRefresh = onDismissRefresh
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Top Navigation & Address Bar
            HStack(spacing: 8) {
                Button {
                    navCommand = .back(UUID())
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.borderless)

                Button {
                    navCommand = .forward(UUID())
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.borderless)

                Button {
                    navCommand = .reload(UUID())
                } label: {
                    Image(systemName: isLoading ? "xmark" : "arrow.clockwise")
                }
                .buttonStyle(.borderless)

                TextField("输入任意需要登录的网址并回车…", text: $addressText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12.5, design: .monospaced))
                    .onSubmit { navigateToAddress() }

                Button("前往") { navigateToAddress() }
                    .readBoxGlassButton()
                    .controlSize(.small)

                Divider().frame(height: 16)

                HStack(spacing: 5) {
                    Circle()
                        .fill(currentCookieCount > 0 ? Color.green : Color.secondary.opacity(0.4))
                        .frame(width: 7, height: 7)
                    Text("已存 \(currentCookieCount) 条 Cookie")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .readBoxGlassSurface(in: Capsule())

                Button("完成") {
                    onDismissRefresh?()
                    dismiss()
                }
                .readBoxGlassButton(prominent: true, tint: .blue)
                .controlSize(.small)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)

            // Quick Site Shortcuts Strip
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    Text("常用站点：")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(PresetLoginSite.defaults) { site in
                        Button {
                            addressText = site.loginURL
                            navigateToAddress()
                        } label: {
                            Label(site.name, systemImage: site.icon)
                                .font(.system(size: 11.5))
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .readBoxGlassSurface(in: Capsule(), interactive: true)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
            }
            .background(Color.primary.opacity(0.02))

            Divider()

            // Live persistent WKWebView
            LoginWKWebView(
                targetURL: $currentURL,
                navCommand: $navCommand,
                isLoading: $isLoading,
                onURLChanged: { newURL in
                    addressText = newURL.absoluteString
                    refreshCookieCount(for: newURL)
                }
            )

            Divider()

            HStack {
                Image(systemName: "lock.shield.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
                Text("登录会话与 Cookie 仅保存在你本机 macOS WebKit 存储中，不会上传任何服务器；登录成功后，剪藏该站点及其图片会自动复用登录态。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
        }
        .frame(width: 980, height: 680)
        .onAppear {
            addressText = initialURLString
            navigateToAddress()
        }
    }

    private func navigateToAddress() {
        var str = addressText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !str.isEmpty else { return }
        if !str.hasPrefix("http://") && !str.hasPrefix("https://") {
            str = "https://\(str)"
        }
        if let url = URL(string: str) {
            currentURL = url
            refreshCookieCount(for: url)
        }
    }

    private func refreshCookieCount(for url: URL) {
        guard let host = url.host else { return }
        Task {
            currentCookieCount = await SiteCookieManager.shared.cookieCount(matchingDomain: host)
        }
    }
}

public enum LoginWebViewCommand: Equatable {
    case back(UUID)
    case forward(UUID)
    case reload(UUID)
}

private struct LoginWKWebView: NSViewRepresentable {
    @Binding var targetURL: URL?
    @Binding var navCommand: LoginWebViewCommand?
    @Binding var isLoading: Bool
    var onURLChanged: (URL) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default() // persistent cookie store shared with clipper!
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.navigationDelegate = context.coordinator
        wv.uiDelegate = context.coordinator
        wv.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
        context.coordinator.webView = wv
        if let url = targetURL {
            context.coordinator.lastRequestedURL = url
            wv.load(URLRequest(url: url))
        }
        return wv
    }

    func updateNSView(_ wv: WKWebView, context: Context) {
        context.coordinator.parent = self
        if let url = targetURL, url != context.coordinator.lastRequestedURL {
            context.coordinator.lastRequestedURL = url
            wv.load(URLRequest(url: url))
        }
        if let cmd = navCommand, cmd != context.coordinator.lastCommand {
            context.coordinator.lastCommand = cmd
            switch cmd {
            case .back: if wv.canGoBack { wv.goBack() }
            case .forward: if wv.canGoForward { wv.goForward() }
            case .reload:
                if wv.isLoading { wv.stopLoading() }
                else { wv.reload() }
            }
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var parent: LoginWKWebView
        weak var webView: WKWebView?
        var lastRequestedURL: URL?
        var lastCommand: LoginWebViewCommand?

        init(parent: LoginWKWebView) { self.parent = parent }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            DispatchQueue.main.async { self.parent.isLoading = true }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.parent.isLoading = false
                if let url = webView.url {
                    self.lastRequestedURL = url
                    self.parent.onURLChanged(url)
                }
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async { self.parent.isLoading = false }
        }

        // Open target="_blank" OAuth/login popups inside the same WebView so login completes smoothly
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
                webView.load(URLRequest(url: url))
            }
            return nil
        }
    }
}
