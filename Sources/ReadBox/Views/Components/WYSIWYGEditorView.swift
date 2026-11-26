import SwiftUI
import WebKit

/// Single-Pane WYSIWYG Markdown Editor (Typora / Bear style — zero split-pane code/preview).
public struct WYSIWYGEditorView: NSViewRepresentable {
    public let documentId: String
    public let markdown: String
    public let pendingAppend: String?
    public var onMarkdownChange: (String) -> Void
    public var onConsumeAppend: () -> Void

    public func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    public func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "editor")
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        context.coordinator.webView = webView

        if let url = Bundle.module.url(forResource: "wysiwyg_editor", withExtension: "html"),
           let html = try? String(contentsOf: url, encoding: .utf8) {
            webView.loadHTMLString(html, baseURL: url.deletingLastPathComponent())
        }
        return webView
    }

    public func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.syncIfNeeded(webView: webView)
    }

    public final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: WYSIWYGEditorView
        weak var webView: WKWebView?
        private var isLoaded = false
        private var loadedDocumentId: String?

        init(parent: WYSIWYGEditorView) {
            self.parent = parent
        }

        public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isLoaded = true
            loadedDocumentId = nil
            syncIfNeeded(webView: webView)
        }

        func syncIfNeeded(webView: WKWebView) {
            guard isLoaded else { return }

            if loadedDocumentId != parent.documentId {
                loadedDocumentId = parent.documentId
                if let jsonStr = encodeJSONString(parent.markdown) {
                    webView.evaluateJavaScript("window.setMarkdown(\(jsonStr));", completionHandler: nil)
                }
            }

            if let appendText = parent.pendingAppend, !appendText.isEmpty {
                if let jsonStr = encodeJSONString(appendText) {
                    webView.evaluateJavaScript("window.appendMarkdown(\(jsonStr));", completionHandler: nil)
                }
                DispatchQueue.main.async { [weak self] in
                    self?.parent.onConsumeAppend()
                }
            }
        }

        private func encodeJSONString(_ s: String) -> String? {
            guard let data = try? JSONSerialization.data(withJSONObject: [s]),
                  let arrStr = String(data: data, encoding: .utf8),
                  arrStr.count >= 2 else { return nil }
            return String(arrStr.dropFirst().dropLast())
        }

        public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let dict = message.body as? [String: Any],
                  let type = dict["type"] as? String,
                  type == "change",
                  let md = dict["markdown"] as? String else { return }

            DispatchQueue.main.async { [weak self] in
                self?.parent.onMarkdownChange(md)
            }
        }
    }
}
