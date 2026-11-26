import Foundation
import WebKit

public struct PresetLoginSite: Identifiable, Hashable {
    public let id: String
    public let name: String
    public let domain: String
    public let loginURL: String
    public let icon: String

    public static let defaults: [PresetLoginSite] = [
        PresetLoginSite(id: "zhihu", name: "知乎", domain: "zhihu.com", loginURL: "https://www.zhihu.com/signin", icon: "text.bubble.fill"),
        PresetLoginSite(id: "xiaohongshu", name: "小红书", domain: "xiaohongshu.com", loginURL: "https://www.xiaohongshu.com", icon: "flame.fill"),
        PresetLoginSite(id: "juejin", name: "稀土掘金", domain: "juejin.cn", loginURL: "https://juejin.cn", icon: "chevron.left.forwardslash.chevron.right"),
        PresetLoginSite(id: "sspai", name: "少数派", domain: "sspai.com", loginURL: "https://sspai.com/login", icon: "sparkles"),
        PresetLoginSite(id: "medium", name: "Medium", domain: "medium.com", loginURL: "https://medium.com/m/signin", icon: "book.closed.fill"),
        PresetLoginSite(id: "substack", name: "Substack", domain: "substack.com", loginURL: "https://substack.com/sign-in", icon: "envelope.open.fill"),
        PresetLoginSite(id: "x", name: "X / Twitter", domain: "x.com", loginURL: "https://x.com/i/flow/login", icon: "at")
    ]
}

public struct DomainCookieSummary: Identifiable, Hashable {
    public var id: String { domain }
    public let domain: String
    public let cookieCount: Int
}

/// Unified persistent Cookie store backed by `WKWebsiteDataStore.default()`.
/// Shares logged-in sessions seamlessly between the built-in login browser, Reader's「原网页」WebView,
/// OffscreenWebViewFetcher, and URLSession HTML/image clipping requests.
@MainActor
public final class SiteCookieManager {
    public static let shared = SiteCookieManager()
    private let dataStore = WKWebsiteDataStore.default()

    private init() {}

    /// Returns all persisted HTTPCookies matching the target URL's host (including parent domains like `.zhihu.com`).
    public func cookies(for url: URL) async -> [HTTPCookie] {
        guard let host = url.host?.lowercased() else { return [] }
        let all = await fetchAllCookies()
        let now = Date()
        return all.filter { cookie in
            if let exp = cookie.expiresDate, exp < now { return false }
            return Self.domainMatches(cookieDomain: cookie.domain, requestHost: host)
        }
    }

    /// Formats matching cookies into a standard HTTP `Cookie` request header string.
    public func cookieHeader(for url: URL) async -> String? {
        let matched = await cookies(for: url)
        guard !matched.isEmpty else { return nil }
        // Deduplicate by cookie name, preferring more specific domain match
        var byName: [String: HTTPCookie] = [:]
        for c in matched {
            if let existing = byName[c.name] {
                if c.domain.count >= existing.domain.count {
                    byName[c.name] = c
                }
            } else {
                byName[c.name] = c
            }
        }
        return byName.values
            .map { "\($0.name)=\($0.value)" }
            .joined(separator: "; ")
    }

    /// Returns grouped cookie counts per normalized root domain for display in Settings.
    public func loggedInDomains() async -> [DomainCookieSummary] {
        let all = await fetchAllCookies()
        let now = Date()
        var counts: [String: Int] = [:]
        for c in all {
            if let exp = c.expiresDate, exp < now { continue }
            let cleanDomain = c.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
            guard !cleanDomain.isEmpty else { continue }
            counts[cleanDomain, default: 0] += 1
        }
        return counts
            .map { DomainCookieSummary(domain: $0.key, cookieCount: $0.value) }
            .sorted { $0.cookieCount > $1.cookieCount || ($0.cookieCount == $1.cookieCount && $0.domain < $1.domain) }
    }

    public func cookieCount(matchingDomain domain: String) async -> Int {
        let target = domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
        let all = await fetchAllCookies()
        let now = Date()
        return all.filter { c in
            if let exp = c.expiresDate, exp < now { return false }
            let cd = c.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
            return cd == target || cd.hasSuffix(".\(target)") || target.hasSuffix(".\(cd)")
        }.count
    }

    /// Imports a raw `Cookie:` header string (e.g. copied from browser DevTools) into WebKit's persistent store.
    @discardableResult
    public func importCookieHeader(_ rawHeader: String, forDomain domain: String) async -> Int {
        let cleanDomain = domain
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .components(separatedBy: "/").first?
            .trimmingCharacters(in: CharacterSet(charactersIn: ".")) ?? ""
        guard !cleanDomain.isEmpty else { return 0 }

        var cleanedHeader = rawHeader.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanedHeader.lowercased().hasPrefix("cookie:") {
            cleanedHeader = String(cleanedHeader.dropFirst(7)).trimmingCharacters(in: .whitespaces)
        }

        let pairs = cleanedHeader.components(separatedBy: ";")
        var imported = 0
        let expiry = Date().addingTimeInterval(60 * 60 * 24 * 180) // 180 days

        for pair in pairs {
            let trimmed = pair.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let eqIdx = trimmed.firstIndex(of: "=") else { continue }
            let name = String(trimmed[..<eqIdx]).trimmingCharacters(in: .whitespaces)
            let value = String(trimmed[trimmed.index(after: eqIdx)...]).trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { continue }

            let props: [HTTPCookiePropertyKey: Any] = [
                .domain: ".\(cleanDomain)",
                .path: "/",
                .name: name,
                .value: value,
                .secure: "TRUE",
                .expires: expiry
            ]
            if let cookie = HTTPCookie(properties: props) {
                await setCookie(cookie)
                imported += 1
            }
        }
        return imported
    }

    /// Clears all persisted cookies & website data for the specified domain.
    public func clearCookies(forDomain domain: String) async {
        let target = domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
        let all = await fetchAllCookies()
        for c in all {
            let cd = c.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
            if cd == target || cd.hasSuffix(".\(target)") || target.hasSuffix(".\(cd)") {
                await deleteCookie(c)
            }
        }

        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        let records = await fetchDataRecords(ofTypes: types)
        let matchingRecords = records.filter { rec in
            let name = rec.displayName.lowercased()
            return name == target || name.hasSuffix(".\(target)") || target.hasSuffix(".\(name)")
        }
        if !matchingRecords.isEmpty {
            await removeData(ofTypes: types, for: matchingRecords)
        }
    }

    // MARK: - Domain Matching Helper (nonisolated for unit testing)

    public nonisolated static func domainMatches(cookieDomain: String, requestHost: String) -> Bool {
        let cd = cookieDomain.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
        let host = requestHost.lowercased()
        guard !cd.isEmpty else { return false }
        return host == cd || host.hasSuffix(".\(cd)")
    }

    // MARK: - Async WKHTTPCookieStore wrappers

    private func fetchAllCookies() async -> [HTTPCookie] {
        await withCheckedContinuation { cont in
            dataStore.httpCookieStore.getAllCookies { cookies in
                cont.resume(returning: cookies)
            }
        }
    }

    private func setCookie(_ cookie: HTTPCookie) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            dataStore.httpCookieStore.setCookie(cookie) {
                cont.resume()
            }
        }
    }

    private func deleteCookie(_ cookie: HTTPCookie) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            dataStore.httpCookieStore.delete(cookie) {
                cont.resume()
            }
        }
    }

    private func fetchDataRecords(ofTypes types: Set<String>) async -> [WKWebsiteDataRecord] {
        await withCheckedContinuation { cont in
            dataStore.fetchDataRecords(ofTypes: types) { records in
                cont.resume(returning: records)
            }
        }
    }

    private func removeData(ofTypes types: Set<String>, for records: [WKWebsiteDataRecord]) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            dataStore.removeData(ofTypes: types, for: records) {
                cont.resume()
            }
        }
    }
}
