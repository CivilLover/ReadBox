import SwiftUI
import WebKit
import AppKit

/// Native WKWebView bridge hosting the Cubox-inspired distraction-free reader canvas (`reader.html`)
/// with 5-color highlighting, quote-to-note, and ask-AI actions.
public struct ReaderWebView: NSViewRepresentable {
    public let clip: ClipItem
    public let articleHTML: String
    public let clipDirectoryURL: URL
    public let preferences: ReaderPreferences
    public let scrollToHighlightId: String?

    public var onAddHighlight: (String, HighlightColor) -> Void
    public var onRemoveHighlight: (String) -> Void
    public var onQuoteToNote: (String) -> Void
    public var onAskAI: (String) -> Void
    public var onClearScrollTarget: () -> Void

    public func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    public func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "reader")
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        context.coordinator.webView = webView
        context.coordinator.loadTemplate(into: webView, baseURL: clipDirectoryURL)
        return webView
    }

    public func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.syncIfNeeded(webView: webView)
    }

    public final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: ReaderWebView
        weak var webView: WKWebView?
        private var isLoaded = false
        private var loadedClipId: String?
        private var lastHighlightsHash: Int = 0
        private var lastPrefsHash: Int = 0
        private var lastBaseURL: URL?

        init(parent: ReaderWebView) {
            self.parent = parent
        }

        func loadTemplate(into webView: WKWebView, baseURL: URL) {
            isLoaded = false
            lastBaseURL = baseURL
            guard let url = Bundle.module.url(forResource: "reader", withExtension: "html"),
                  let html = try? String(contentsOf: url, encoding: .utf8) else {
                return
            }
            webView.loadHTMLString(html, baseURL: baseURL)
        }

        func syncIfNeeded(webView: WKWebView) {
            if lastBaseURL != parent.clipDirectoryURL {
                loadedClipId = nil
                loadTemplate(into: webView, baseURL: parent.clipDirectoryURL)
                return
            }
            guard isLoaded else { return }

            let prefsHash = parent.preferences.hashValue
            if prefsHash != lastPrefsHash {
                lastPrefsHash = prefsHash
                pushPreferences(webView)
            }

            if loadedClipId != parent.clip.id {
                loadedClipId = parent.clip.id
                lastHighlightsHash = parent.clip.highlights.hashValue
                pushArticle(webView)
            } else {
                let hlHash = parent.clip.highlights.hashValue
                if hlHash != lastHighlightsHash {
                    lastHighlightsHash = hlHash
                    pushHighlightsOnly(webView)
                }
            }

            if let targetId = parent.scrollToHighlightId {
                let escaped = targetId.replacingOccurrences(of: "\"", with: "\\\"")
                webView.evaluateJavaScript("window.scrollToHighlight(\"\(escaped)\");", completionHandler: nil)
                DispatchQueue.main.async { [weak self] in
                    self?.parent.onClearScrollTarget()
                }
            }
        }

        public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isLoaded = true
            lastPrefsHash = 0
            loadedClipId = nil
            syncIfNeeded(webView: webView)
        }

        public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        private func pushPreferences(_ webView: WKWebView) {
            let dict: [String: Any] = [
                "theme": parent.preferences.theme.rawValue,
                "fontFamily": parent.preferences.fontFamily,
                "fontSize": parent.preferences.fontSize,
                "lineHeight": parent.preferences.lineHeight,
                "contentWidth": parent.preferences.contentWidth
            ]
            if let json = toJSON(dict) {
                webView.evaluateJavaScript("window.applyPreferences(\(json));", completionHandler: nil)
            }
        }

        private func pushArticle(_ webView: WKWebView) {
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd"
            let hlArray: [[String: Any]] = parent.clip.highlights.map {
                ["id": $0.id, "quote": $0.quote, "color": $0.color.rawValue]
            }
            let payload: [String: Any] = [
                "title": parent.clip.title,
                "author": parent.clip.author,
                "domain": parent.clip.domain,
                "dateText": df.string(from: parent.clip.createdAt),
                "url": parent.clip.url,
                "html": parent.articleHTML,
                "highlights": hlArray
            ]
            if let json = toJSON(payload) {
                webView.evaluateJavaScript("window.loadArticle(\(json));", completionHandler: nil)
            }
        }

        private func pushHighlightsOnly(_ webView: WKWebView) {
            let hlArray: [[String: Any]] = parent.clip.highlights.map {
                ["id": $0.id, "quote": $0.quote, "color": $0.color.rawValue]
            }
            if let json = toJSON(hlArray) {
                webView.evaluateJavaScript("window.renderHighlights(\(json));", completionHandler: nil)
            }
        }

        private func toJSON(_ obj: Any) -> String? {
            guard let data = try? JSONSerialization.data(withJSONObject: obj),
                  let str = String(data: data, encoding: .utf8) else { return nil }
            return str
        }

        public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let dict = message.body as? [String: Any],
                  let type = dict["type"] as? String else { return }

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                switch type {
                case "addHighlight":
                    if let quote = dict["quote"] as? String,
                       let colorRaw = dict["color"] as? String,
                       let color = HighlightColor(rawValue: colorRaw) {
                        self.parent.onAddHighlight(quote, color)
                    }
                case "removeHighlight":
                    if let id = dict["id"] as? String {
                        self.parent.onRemoveHighlight(id)
                    }
                case "quoteToNote":
                    if let quote = dict["quote"] as? String {
                        self.parent.onQuoteToNote(quote)
                    }
                case "copyText":
                    if let text = dict["text"] as? String {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                    }
                case "askAI":
                    if let quote = dict["quote"] as? String {
                        self.parent.onAskAI(quote)
                    }
                default:
                    break
                }
            }
        }
    }
}

/// Simple WKWebView for viewing live Webpage or offline Snapshot HTML inside Reader tabs,
/// with persistent cookies and optional live DOM extraction callback for anti-bot/login sites (e.g. Zhihu).
public struct SimpleWebView: NSViewRepresentable {
    public let url: URL?
    public let htmlString: String?
    public let baseURL: URL?
    public var extractTrigger: Int = 0
    public var onExtractedHTML: ((String) -> Void)? = nil

    public func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
        load(into: wv)
        return wv
    }

    public func updateNSView(_ wv: WKWebView, context: Context) {
        if let html = htmlString {
            if context.coordinator.lastLoadedKey != "html:\(html.hashValue)" {
                context.coordinator.lastLoadedKey = "html:\(html.hashValue)"
                wv.loadHTMLString(html, baseURL: baseURL)
            }
        } else if let url {
            if context.coordinator.lastLoadedKey != "url:\(url.absoluteString)" {
                context.coordinator.lastLoadedKey = "url:\(url.absoluteString)"
                wv.load(URLRequest(url: url))
            }
        }

        if extractTrigger != context.coordinator.lastExtractTrigger {
            context.coordinator.lastExtractTrigger = extractTrigger
            let callback = onExtractedHTML
            wv.evaluateJavaScript("document.documentElement.outerHTML") { result, _ in
                if let html = result as? String, !html.isEmpty {
                    DispatchQueue.main.async {
                        callback?(html)
                    }
                }
            }
        }
    }

    public func makeCoordinator() -> Coordinator { Coordinator() }

    private func load(into wv: WKWebView) {
        if let html = htmlString {
            wv.loadHTMLString(html, baseURL: baseURL)
        } else if let url {
            wv.load(URLRequest(url: url))
        }
    }

    public final class Coordinator {
        var lastLoadedKey: String = ""
        var lastExtractTrigger: Int = 0
    }
}
