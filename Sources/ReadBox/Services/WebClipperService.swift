import Foundation
import WebKit
import AppKit

public struct ClippedPageResult: Sendable {
    public var title: String
    public var author: String
    public var excerpt: String
    public var domain: String
    public var sourceType: ClipSourceType
    public var cleanedHTML: String
    public var markdown: String
    public var snapshotHTML: String
    public var coverImageName: String?
}

public enum ClipperError: LocalizedError {
    case invalidURL
    case networkFailure(String)
    case emptyContent

    public var errorDescription: String? {
        switch self {
        case .invalidURL: return "无效的链接格式，请检查网址是否以 http:// 或 https:// 开头。"
        case .networkFailure(let msg): return "抓取网页失败：\(msg)"
        case .emptyContent: return "未能提取到有效正文内容，可尝试切换到「原网页」查看。"
        }
    }
}

/// Fetches & parses WeChat Official Accounts (`mp.weixin.qq.com`) and general web pages,
/// localizing images into `<clipDir>/assets/` to defeat hotlink protection and link rot.
public final class WebClipperService {
    private let session: URLSession

    public init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 45
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.6 Safari/605.1.15",
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8"
        ]
        self.session = URLSession(configuration: config)
    }

    public func clipURL(_ rawURLString: String, assetsDirectory: URL) async throws -> ClippedPageResult {
        let normalized = normalizeURLString(rawURLString)
        guard let url = URL(string: normalized), let host = url.host else {
            throw ClipperError.invalidURL
        }

        let isWeChat = host.lowercased().contains("mp.weixin.qq.com")
        var rawHTML = try await fetchHTML(url: url, isWeChat: isWeChat)

        // Fallback to offscreen WKWebView when static HTML looks JS-rendered or blocked
        if shouldUseWebViewFallback(html: rawHTML, isWeChat: isWeChat) {
            if let rendered = await OffscreenWebViewFetcher.fetchRenderedHTML(url: url) {
                rawHTML = rendered
            }
        }

        try? FileManager.default.createDirectory(at: assetsDirectory, withIntermediateDirectories: true)

        if isWeChat {
            return await parseWeChatArticle(rawHTML: rawHTML, sourceURL: url, assetsDir: assetsDirectory)
        } else {
            return await parseGeneralWebPage(rawHTML: rawHTML, sourceURL: url, assetsDir: assetsDirectory)
        }
    }

    private func normalizeURLString(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            return trimmed
        }
        return "https://\(trimmed)"
    }

    private func fetchHTML(url: URL, isWeChat: Bool) async throws -> String {
        var req = URLRequest(url: url)
        if isWeChat {
            req.setValue("https://mp.weixin.qq.com/", forHTTPHeaderField: "Referer")
        }
        do {
            let (data, response) = try await session.data(for: req)
            if let http = response as? HTTPURLResponse, !(200...399).contains(http.statusCode) {
                throw ClipperError.networkFailure("HTTP \(http.statusCode)")
            }
            if let utf8 = String(data: data, encoding: .utf8) {
                return utf8
            }
            let gb18030 = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
            if let gbk = String(data: data, encoding: String.Encoding(rawValue: gb18030)) {
                return gbk
            }
            return String(decoding: data, as: UTF8.self)
        } catch let err as ClipperError {
            throw err
        } catch {
            throw ClipperError.networkFailure(error.localizedDescription)
        }
    }

    private func shouldUseWebViewFallback(html: String, isWeChat: Bool) -> Bool {
        if html.count < 800 { return true }
        if isWeChat && !html.contains("js_content") { return true }
        let lower = html.lowercased()
        if lower.contains("enable javascript") && html.count < 4000 { return true }
        return false
    }

    // MARK: - WeChat Official Account Specialized Parser

    private func parseWeChatArticle(rawHTML: String, sourceURL: URL, assetsDir: URL) async -> ClippedPageResult {
        let title = firstNonEmpty([
            extractMetaContent(rawHTML, property: "og:title"),
            extractRegex(rawHTML, pattern: #"var\s+msg_title\s*=\s*['"]([^'"]+)['"]"#),
            extractElementInnerText(rawHTML, id: "activity-name"),
            extractTagText(rawHTML, tag: "title")
        ]) ?? "微信公众号文章"

        let author = firstNonEmpty([
            extractRegex(rawHTML, pattern: #"var\s+nickname\s*=\s*htmlDecode\(['"]([^'"]+)['"]\)"#),
            extractElementInnerText(rawHTML, id: "js_name"),
            extractMetaContent(rawHTML, property: "og:article:author")
        ]) ?? "微信公众号"

        let metaDesc = firstNonEmpty([
            extractMetaContent(rawHTML, property: "og:description"),
            extractRegex(rawHTML, pattern: #"var\s+msg_desc\s*=\s*htmlDecode\(['"]([^'"]+)['"]\)"#)
        ]) ?? ""

        let coverURL = firstNonEmpty([
            extractMetaContent(rawHTML, property: "og:image"),
            extractRegex(rawHTML, pattern: #"var\s+msg_cdn_url\s*=\s*['"]([^'"]+)['"]"#)
        ])

        var contentHTML = extractBalancedDiv(in: rawHTML, id: "js_content") ?? extractMainContentHTML(rawHTML)
        // WeChat uses data-src for lazy images and sometimes visibility:hidden on js_content
        contentHTML = contentHTML.replacingOccurrences(of: #"visibility\s*:\s*hidden"#, with: "visibility:visible", options: .regularExpression)
        contentHTML = promoteWeChatDataSrc(contentHTML)
        contentHTML = sanitizeArticleHTML(contentHTML)

        let (localizedHTML, firstImgName) = await localizeImages(in: contentHTML, baseURL: sourceURL, assetsDir: assetsDir, referer: "https://mp.weixin.qq.com/")

        var coverName = firstImgName
        if let coverURL, let downloadedCover = await downloadImage(urlString: coverURL, baseURL: sourceURL, assetsDir: assetsDir, filenamePrefix: "cover", referer: "https://mp.weixin.qq.com/") {
            coverName = downloadedCover
        }

        let markdown = HTMLToMarkdown.convert(localizedHTML)
        let plainText = HTMLToMarkdown.stripTags(localizedHTML)
        let excerpt = metaDesc.isEmpty ? String(plainText.prefix(180)) : decodeHTMLEntities(metaDesc)

        let snapshot = wrapSnapshotHTML(title: decodeHTMLEntities(title), author: decodeHTMLEntities(author), bodyHTML: localizedHTML, sourceURL: sourceURL.absoluteString)

        return ClippedPageResult(
            title: decodeHTMLEntities(title).trimmingCharacters(in: .whitespacesAndNewlines),
            author: decodeHTMLEntities(author).trimmingCharacters(in: .whitespacesAndNewlines),
            excerpt: excerpt.trimmingCharacters(in: .whitespacesAndNewlines),
            domain: sourceURL.host ?? "mp.weixin.qq.com",
            sourceType: .wechat,
            cleanedHTML: localizedHTML,
            markdown: markdown,
            snapshotHTML: snapshot,
            coverImageName: coverName
        )
    }

    // MARK: - General Web Page Parser

    private func parseGeneralWebPage(rawHTML: String, sourceURL: URL, assetsDir: URL) async -> ClippedPageResult {
        let title = firstNonEmpty([
            extractMetaContent(rawHTML, property: "og:title"),
            extractMetaContent(rawHTML, name: "twitter:title"),
            extractTagText(rawHTML, tag: "h1"),
            extractTagText(rawHTML, tag: "title")
        ]) ?? (sourceURL.host ?? "未命名网页")

        let author = firstNonEmpty([
            extractMetaContent(rawHTML, name: "author"),
            extractMetaContent(rawHTML, property: "article:author"),
            extractMetaContent(rawHTML, property: "og:site_name")
        ]) ?? (sourceURL.host ?? "")

        let metaDesc = firstNonEmpty([
            extractMetaContent(rawHTML, property: "og:description"),
            extractMetaContent(rawHTML, name: "description")
        ]) ?? ""

        let coverURL = firstNonEmpty([
            extractMetaContent(rawHTML, property: "og:image"),
            extractMetaContent(rawHTML, name: "twitter:image")
        ])

        var contentHTML = extractMainContentHTML(rawHTML)
        contentHTML = promoteWeChatDataSrc(contentHTML)
        contentHTML = sanitizeArticleHTML(contentHTML)

        let (localizedHTML, firstImgName) = await localizeImages(in: contentHTML, baseURL: sourceURL, assetsDir: assetsDir, referer: sourceURL.absoluteString)

        var coverName = firstImgName
        if let coverURL, let downloadedCover = await downloadImage(urlString: coverURL, baseURL: sourceURL, assetsDir: assetsDir, filenamePrefix: "cover", referer: sourceURL.absoluteString) {
            coverName = downloadedCover
        }

        let markdown = HTMLToMarkdown.convert(localizedHTML)
        let plainText = HTMLToMarkdown.stripTags(localizedHTML)
        let excerpt = metaDesc.isEmpty ? String(plainText.prefix(180)) : decodeHTMLEntities(metaDesc)

        let snapshot = wrapSnapshotHTML(title: decodeHTMLEntities(title), author: decodeHTMLEntities(author), bodyHTML: localizedHTML, sourceURL: sourceURL.absoluteString)

        return ClippedPageResult(
            title: decodeHTMLEntities(title).trimmingCharacters(in: .whitespacesAndNewlines),
            author: decodeHTMLEntities(author).trimmingCharacters(in: .whitespacesAndNewlines),
            excerpt: excerpt.trimmingCharacters(in: .whitespacesAndNewlines),
            domain: sourceURL.host ?? "",
            sourceType: .webpage,
            cleanedHTML: localizedHTML,
            markdown: markdown,
            snapshotHTML: snapshot,
            coverImageName: coverName
        )
    }

    // MARK: - Image Localization (Defeats Hotlink & Deletion)

    private func localizeImages(in html: String, baseURL: URL, assetsDir: URL, referer: String) async -> (String, String?) {
        guard let regex = try? NSRegularExpression(pattern: #"<img\b[^>]*?\bsrc\s*=\s*["']([^"']+)["'][^>]*>"#, options: [.caseInsensitive]) else {
            return (html, nil)
        }
        let nsHTML = html as NSString
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: nsHTML.length))
        if matches.isEmpty { return (html, nil) }

        var urlToLocal: [String: String] = [:]
        var firstLocal: String?
        var counter = 0

        for match in matches {
            guard match.numberOfRanges >= 2 else { continue }
            let src = decodeHTMLEntities(nsHTML.substring(with: match.range(at: 1)))
            if src.hasPrefix("data:") || src.hasPrefix("assets/") { continue }
            if urlToLocal[src] != nil { continue }
            counter += 1
            if counter > 60 { break } // reasonable safety cap per article

            if let localName = await downloadImage(urlString: src, baseURL: baseURL, assetsDir: assetsDir, filenamePrefix: "img_\(counter)", referer: referer) {
                urlToLocal[src] = localName
                if firstLocal == nil { firstLocal = localName }
            }
        }

        var updated = html
        for (original, localName) in urlToLocal {
            updated = updated.replacingOccurrences(of: original, with: "assets/\(localName)")
            let escapedAmp = original.replacingOccurrences(of: "&", with: "&amp;")
            updated = updated.replacingOccurrences(of: escapedAmp, with: "assets/\(localName)")
        }
        return (updated, firstLocal)
    }

    private func downloadImage(urlString: String, baseURL: URL, assetsDir: URL, filenamePrefix: String, referer: String) async -> String? {
        var resolvedStr = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if resolvedStr.hasPrefix("//") {
            resolvedStr = "https:\(resolvedStr)"
        }
        guard let url = URL(string: resolvedStr, relativeTo: baseURL)?.absoluteURL else { return nil }
        guard url.scheme == "http" || url.scheme == "https" else { return nil }

        var req = URLRequest(url: url)
        req.timeoutInterval = 12
        req.setValue(referer, forHTTPHeaderField: "Referer")

        do {
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode), data.count > 200 else {
                return nil
            }
            let mime = (http.mimeType ?? "").lowercased()
            let ext: String
            if mime.contains("png") { ext = "png" }
            else if mime.contains("webp") { ext = "webp" }
            else if mime.contains("gif") { ext = "gif" }
            else if mime.contains("svg") { ext = "svg" }
            else { ext = "jpg" }

            let fileName = "\(filenamePrefix).\(ext)"
            let dest = assetsDir.appendingPathComponent(fileName)
            try data.write(to: dest, options: .atomic)
            return fileName
        } catch {
            return nil
        }
    }

    // MARK: - HTML Extraction & Cleaning Utilities

    private func promoteWeChatDataSrc(_ html: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"<img\b[^>]*>"#, options: [.caseInsensitive]) else {
            return html
        }
        let ns = html as NSString
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: ns.length))
        var result = html
        for match in matches.reversed() {
            let tag = ns.substring(with: match.range)
            if let dataSrc = extractRegex(tag, pattern: #"data-src\s*=\s*["']([^"']+)["']"#) {
                var newTag = tag
                if newTag.range(of: #"\bsrc\s*="#, options: .regularExpression) != nil {
                    newTag = newTag.replacingOccurrences(of: #"\bsrc\s*=\s*["'][^"']*["']"#, with: "src=\"\(dataSrc)\"", options: .regularExpression)
                } else {
                    newTag = newTag.replacingOccurrences(of: "<img", with: "<img src=\"\(dataSrc)\"", options: [.caseInsensitive])
                }
                let swiftRange = Range(match.range, in: result)!
                result.replaceSubrange(swiftRange, with: newTag)
            }
        }
        return result
    }

    private func extractMainContentHTML(_ html: String) -> String {
        if let article = extractBalancedTag(in: html, tag: "article"), article.count > 200 {
            return article
        }
        if let main = extractBalancedTag(in: html, tag: "main"), main.count > 200 {
            return main
        }
        if let body = extractBalancedTag(in: html, tag: "body") {
            return body
        }
        return html
    }

    private func sanitizeArticleHTML(_ html: String) -> String {
        var s = html
        let stripPatterns = [
            #"(?is)<script\b[^>]*>.*?</script>"#,
            #"(?is)<style\b[^>]*>.*?</style>"#,
            #"(?is)<noscript\b[^>]*>.*?</noscript>"#,
            #"(?is)<iframe\b[^>]*>.*?</iframe>"#,
            #"(?is)<nav\b[^>]*>.*?</nav>"#,
            #"(?is)<footer\b[^>]*>.*?</footer>"#,
            #"(?is)<aside\b[^>]*>.*?</aside>"#,
            #"(?is)<!--.*?-->"#
        ]
        for pattern in stripPatterns {
            s = s.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func wrapSnapshotHTML(title: String, author: String, bodyHTML: String, sourceURL: String) -> String {
        """
        <!DOCTYPE html>
        <html lang="zh-CN">
        <head>
          <meta charset="utf-8" />
          <meta name="viewport" content="width=device-width, initial-scale=1" />
          <title>\(escapeHTML(title))</title>
          <style>
            body { max-width: 740px; margin: 36px auto; padding: 0 24px 64px; font-family: -apple-system, 'PingFang SC', sans-serif; line-height: 1.8; color: #1d1d1f; background: #fff; }
            h1 { font-size: 28px; line-height: 1.35; margin-bottom: 8px; }
            .meta { color: #86868b; font-size: 13px; margin-bottom: 28px; padding-bottom: 16px; border-bottom: 1px solid #eee; }
            img { max-width: 100%; height: auto; border-radius: 8px; margin: 14px 0; }
            pre { background: #f5f5f7; padding: 14px; border-radius: 8px; overflow-x: auto; }
            blockquote { border-left: 3px solid #2563eb; margin: 16px 0; padding: 4px 16px; color: #555; background: #f8fafc; }
          </style>
        </head>
        <body>
          <h1>\(escapeHTML(title))</h1>
          <div class="meta">\(escapeHTML(author)) · <a href="\(escapeHTML(sourceURL))">\(escapeHTML(sourceURL))</a></div>
          <article>\(bodyHTML)</article>
        </body>
        </html>
        """
    }

    private func extractBalancedDiv(in html: String, id: String) -> String? {
        guard let startRegex = try? NSRegularExpression(pattern: #"<div\b[^>]*\bid\s*=\s*["']\#(id)["'][^>]*>"#, options: [.caseInsensitive]) else {
            return nil
        }
        let ns = html as NSString
        guard let firstMatch = startRegex.firstMatch(in: html, range: NSRange(location: 0, length: ns.length)) else {
            return nil
        }
        let contentStart = firstMatch.range.location + firstMatch.range.length
        guard let tagRegex = try? NSRegularExpression(pattern: #"<(/?)div\b[^>]*>"#, options: [.caseInsensitive]) else {
            return nil
        }
        let matches = tagRegex.matches(in: html, range: NSRange(location: contentStart, length: ns.length - contentStart))
        var depth = 1
        for m in matches {
            let isClosing = ns.substring(with: m.range(at: 1)) == "/"
            depth += isClosing ? -1 : 1
            if depth == 0 {
                return ns.substring(with: NSRange(location: contentStart, length: m.range.location - contentStart))
            }
        }
        return nil
    }

    private func extractBalancedTag(in html: String, tag: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"(?is)<\#(tag)\b[^>]*>(.*?)</\#(tag)>"#) else { return nil }
        let ns = html as NSString
        guard let m = regex.firstMatch(in: html, range: NSRange(location: 0, length: ns.length)), m.numberOfRanges >= 2 else {
            return nil
        }
        return ns.substring(with: m.range(at: 1))
    }

    private func extractElementInnerText(_ html: String, id: String) -> String? {
        guard let raw = extractRegex(html, pattern: #"(?is)<[a-z0-9]+\b[^>]*\bid\s*=\s*["']\#(id)["'][^>]*>(.*?)</[a-z0-9]+>"#) else {
            return nil
        }
        return HTMLToMarkdown.stripTags(raw).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func extractTagText(_ html: String, tag: String) -> String? {
        guard let raw = extractRegex(html, pattern: #"(?is)<\#(tag)\b[^>]*>(.*?)</\#(tag)>"#) else { return nil }
        return HTMLToMarkdown.stripTags(raw).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func extractMetaContent(_ html: String, property: String) -> String? {
        extractRegex(html, pattern: #"(?i)<meta\b[^>]*property\s*=\s*["']\#(property)["'][^>]*content\s*=\s*["']([^"']+)["']"#)
            ?? extractRegex(html, pattern: #"(?i)<meta\b[^>]*content\s*=\s*["']([^"']+)["'][^>]*property\s*=\s*["']\#(property)["']"#)
    }

    private func extractMetaContent(_ html: String, name: String) -> String? {
        extractRegex(html, pattern: #"(?i)<meta\b[^>]*name\s*=\s*["']\#(name)["'][^>]*content\s*=\s*["']([^"']+)["']"#)
            ?? extractRegex(html, pattern: #"(?i)<meta\b[^>]*content\s*=\s*["']([^"']+)["'][^>]*name\s*=\s*["']\#(name)["']"#)
    }

    private func extractRegex(_ text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)), match.numberOfRanges >= 2 else {
            return nil
        }
        return ns.substring(with: match.range(at: 1))
    }

    private func firstNonEmpty(_ candidates: [String?]) -> String? {
        for c in candidates {
            if let s = c?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
                return s
            }
        }
        return nil
    }

    private func decodeHTMLEntities(_ s: String) -> String {
        s.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
    }

    private func escapeHTML(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

/// Offscreen WKWebView helper for JS-rendered SPAs or dynamic pages when direct HTTP fetch returns empty body.
@MainActor
public final class OffscreenWebViewFetcher: NSObject, WKNavigationDelegate {
    private var webView: WKWebView?
    private var continuation: CheckedContinuation<String?, Never>?
    private var timeoutTask: Task<Void, Never>?

    public static func fetchRenderedHTML(url: URL, timeoutSeconds: Double = 10) async -> String? {
        let fetcher = OffscreenWebViewFetcher()
        return await fetcher.load(url: url, timeoutSeconds: timeoutSeconds)
    }

    private func load(url: URL, timeoutSeconds: Double) async -> String? {
        await withCheckedContinuation { cont in
            self.continuation = cont
            let config = WKWebViewConfiguration()
            let wv = WKWebView(frame: CGRect(x: 0, y: 0, width: 1200, height: 900), configuration: config)
            wv.navigationDelegate = self
            wv.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.6 Safari/605.1.15"
            self.webView = wv
            wv.load(URLRequest(url: url))

            self.timeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                self?.finish(with: nil)
            }
        }
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            let html = try? await webView.evaluateJavaScript("document.documentElement.outerHTML") as? String
            self?.finish(with: html)
        }
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(with: nil)
    }

    private func finish(with html: String?) {
        timeoutTask?.cancel()
        timeoutTask = nil
        webView?.navigationDelegate = nil
        webView = nil
        if let cont = continuation {
            continuation = nil
            cont.resume(returning: html)
        }
    }
}

/// Lightweight deterministic HTML-to-Markdown converter for clean offline `.md` snapshots and AI context.
public enum HTMLToMarkdown {
    public static func convert(_ html: String) -> String {
        var s = html
        // Headings
        for level in (1...6).reversed() {
            let hashes = String(repeating: "#", count: level)
            s = s.replacingOccurrences(of: "(?is)<h\(level)\\b[^>]*>(.*?)</h\(level)>", with: "\n\n\(hashes) $1\n\n", options: .regularExpression)
        }
        // Code blocks
        s = s.replacingOccurrences(of: #"(?is)<pre\b[^>]*>\s*<code\b[^>]*>(.*?)</code>\s*</pre>"#, with: "\n\n```\n$1\n```\n\n", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?is)<pre\b[^>]*>(.*?)</pre>"#, with: "\n\n```\n$1\n```\n\n", options: .regularExpression)
        // Inline code
        s = s.replacingOccurrences(of: #"(?is)<code\b[^>]*>(.*?)</code>"#, with: "`$1`", options: .regularExpression)
        // Bold & italic
        s = s.replacingOccurrences(of: #"(?is)<(?:strong|b)\b[^>]*>(.*?)</(?:strong|b)>"#, with: "**$1**", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?is)<(?:em|i)\b[^>]*>(.*?)</(?:em|i)>"#, with: "*$1*", options: .regularExpression)
        // Images
        s = s.replacingOccurrences(of: #"(?is)<img\b[^>]*src\s*=\s*["']([^"']+)["'][^>]*>"#, with: "\n\n![]($1)\n\n", options: .regularExpression)
        // Links
        s = s.replacingOccurrences(of: #"(?is)<a\b[^>]*href\s*=\s*["']([^"']+)["'][^>]*>(.*?)</a>"#, with: "[$2]($1)", options: .regularExpression)
        // Blockquotes
        s = s.replacingOccurrences(of: #"(?is)<blockquote\b[^>]*>(.*?)</blockquote>"#, with: "\n\n> $1\n\n", options: .regularExpression)
        // List items
        s = s.replacingOccurrences(of: #"(?is)<li\b[^>]*>(.*?)</li>"#, with: "\n- $1", options: .regularExpression)
        // Paragraphs & breaks
        s = s.replacingOccurrences(of: #"(?is)<br\s*/?>"#, with: "\n", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?is)</(?:p|div|section|tr)>"#, with: "\n\n", options: .regularExpression)
        // Strip remaining tags
        s = stripTags(s)
        // Collapse excessive blank lines
        s = s.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func stripTags(_ html: String) -> String {
        var s = html.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
        return s
    }
}
