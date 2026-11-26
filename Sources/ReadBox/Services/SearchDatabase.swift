import Foundation
import SQLite3

public struct SearchHit: Identifiable, Hashable, Sendable {
    public enum Kind: String, Sendable {
        case clip
        case highlight
        case knowledge
    }

    public var id: String
    public var kind: Kind
    public var targetId: String
    public var title: String
    public var snippet: String
    public var domainOrTag: String
}

/// Local SQLite3 + FTS5 full-text search cache stored under `<Vault>/.readbox/index.sqlite`.
/// Purely a rebuildable cache so iCloud Drive syncing of plaintext `.md` files never suffers DB lock conflicts.
public final class SearchDatabase {
    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "com.readbox.searchdb", qos: .userInitiated)

    public init() {}

    deinit {
        close()
    }

    public func open(at dbURL: URL) {
        queue.sync {
            closeUnlocked()
            let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
            if sqlite3_open_v2(dbURL.path, &db, flags, nil) == SQLITE_OK {
                createSchemaUnlocked()
            } else {
                closeUnlocked()
            }
        }
    }

    public func close() {
        queue.sync {
            closeUnlocked()
        }
    }

    private func closeUnlocked() {
        if let db {
            sqlite3_close(db)
            self.db = nil
        }
    }

    private func execUnlocked(_ sql: String) {
        guard let db else { return }
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    private func createSchemaUnlocked() {
        execUnlocked("""
        CREATE VIRTUAL TABLE IF NOT EXISTS fts_docs USING fts5(
            doc_key UNINDEXED,
            kind UNINDEXED,
            target_id UNINDEXED,
            title,
            body,
            meta,
            tokenize='unicode61'
        );
        """)
    }

    public func clearAll() {
        queue.sync {
            execUnlocked("DELETE FROM fts_docs;")
        }
    }

    public func upsertDocument(key: String, kind: SearchHit.Kind, targetId: String, title: String, body: String, meta: String) {
        queue.sync {
            guard let db else { return }
            // Delete previous entry
            let delSQL = "DELETE FROM fts_docs WHERE doc_key = ?;"
            var delStmt: OpaquePointer?
            if sqlite3_prepare_v2(db, delSQL, -1, &delStmt, nil) == SQLITE_OK {
                sqlite3_bind_text(delStmt, 1, (key as NSString).utf8String, -1, nil)
                sqlite3_step(delStmt)
            }
            sqlite3_finalize(delStmt)

            // Insert updated entry
            let insSQL = "INSERT INTO fts_docs (doc_key, kind, target_id, title, body, meta) VALUES (?, ?, ?, ?, ?, ?);"
            var insStmt: OpaquePointer?
            if sqlite3_prepare_v2(db, insSQL, -1, &insStmt, nil) == SQLITE_OK {
                sqlite3_bind_text(insStmt, 1, (key as NSString).utf8String, -1, nil)
                sqlite3_bind_text(insStmt, 2, (kind.rawValue as NSString).utf8String, -1, nil)
                sqlite3_bind_text(insStmt, 3, (targetId as NSString).utf8String, -1, nil)
                sqlite3_bind_text(insStmt, 4, (title as NSString).utf8String, -1, nil)
                sqlite3_bind_text(insStmt, 5, (body as NSString).utf8String, -1, nil)
                sqlite3_bind_text(insStmt, 6, (meta as NSString).utf8String, -1, nil)
                sqlite3_step(insStmt)
            }
            sqlite3_finalize(insStmt)
        }
    }

    public func deleteDocument(key: String) {
        queue.sync {
            guard let db else { return }
            let delSQL = "DELETE FROM fts_docs WHERE doc_key = ?;"
            var delStmt: OpaquePointer?
            if sqlite3_prepare_v2(db, delSQL, -1, &delStmt, nil) == SQLITE_OK {
                sqlite3_bind_text(delStmt, 1, (key as NSString).utf8String, -1, nil)
                sqlite3_step(delStmt)
            }
            sqlite3_finalize(delStmt)
        }
    }

    /// Searches both via FTS5 match (fast tokenized) and LIKE fallback (handles arbitrary CJK substrings smoothly).
    public func search(query: String, kindFilter: SearchHit.Kind? = nil, limit: Int = 40) -> [SearchHit] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        return queue.sync {
            guard let db else { return [] }
            var results: [SearchHit] = []
            var seenKeys = Set<String>()

            // 1. Try FTS5 query first
            let ftsTokens = trimmed
                .components(separatedBy: .whitespaces)
                .filter { !$0.isEmpty }
                .map { "\"\($0.replacingOccurrences(of: "\"", with: ""))\"*" }
                .joined(separator: " ")

            if !ftsTokens.isEmpty {
                var sql = """
                SELECT doc_key, kind, target_id, title, snippet(fts_docs, 4, '【', '】', '…', 24), meta
                FROM fts_docs
                WHERE fts_docs MATCH ?
                """
                if kindFilter != nil { sql += " AND kind = ?" }
                sql += " LIMIT ?;"

                var stmt: OpaquePointer?
                if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                    sqlite3_bind_text(stmt, 1, (ftsTokens as NSString).utf8String, -1, nil)
                    var nextIdx: Int32 = 2
                    if let kindFilter {
                        sqlite3_bind_text(stmt, nextIdx, (kindFilter.rawValue as NSString).utf8String, -1, nil)
                        nextIdx += 1
                    }
                    sqlite3_bind_int(stmt, nextIdx, Int32(limit))

                    while sqlite3_step(stmt) == SQLITE_ROW {
                        let key = columnString(stmt, 0)
                        let kindRaw = columnString(stmt, 1)
                        let targetId = columnString(stmt, 2)
                        let title = columnString(stmt, 3)
                        let snippet = columnString(stmt, 4)
                        let meta = columnString(stmt, 5)
                        if let kind = SearchHit.Kind(rawValue: kindRaw), !seenKeys.contains(key) {
                            seenKeys.insert(key)
                            results.append(SearchHit(id: key, kind: kind, targetId: targetId, title: title, snippet: snippet, domainOrTag: meta))
                        }
                    }
                }
                sqlite3_finalize(stmt)
            }

            // 2. CJK substring fallback via LIKE (ensures Chinese mid-word queries always hit!)
            if results.count < limit {
                let likePattern = "%\(trimmed)%"
                var sql = """
                SELECT doc_key, kind, target_id, title, body, meta
                FROM fts_docs
                WHERE (title LIKE ? OR body LIKE ? OR meta LIKE ?)
                """
                if kindFilter != nil { sql += " AND kind = ?" }
                sql += " LIMIT ?;"

                var stmt: OpaquePointer?
                if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                    sqlite3_bind_text(stmt, 1, (likePattern as NSString).utf8String, -1, nil)
                    sqlite3_bind_text(stmt, 2, (likePattern as NSString).utf8String, -1, nil)
                    sqlite3_bind_text(stmt, 3, (likePattern as NSString).utf8String, -1, nil)
                    var nextIdx: Int32 = 4
                    if let kindFilter {
                        sqlite3_bind_text(stmt, nextIdx, (kindFilter.rawValue as NSString).utf8String, -1, nil)
                        nextIdx += 1
                    }
                    sqlite3_bind_int(stmt, nextIdx, Int32(limit - results.count))

                    while sqlite3_step(stmt) == SQLITE_ROW {
                        let key = columnString(stmt, 0)
                        if seenKeys.contains(key) { continue }
                        let kindRaw = columnString(stmt, 1)
                        let targetId = columnString(stmt, 2)
                        let title = columnString(stmt, 3)
                        let body = columnString(stmt, 4)
                        let meta = columnString(stmt, 5)
                        if let kind = SearchHit.Kind(rawValue: kindRaw) {
                            seenKeys.insert(key)
                            let snippet = Self.makeSnippet(from: body, keyword: trimmed)
                            results.append(SearchHit(id: key, kind: kind, targetId: targetId, title: title, snippet: snippet, domainOrTag: meta))
                        }
                    }
                }
                sqlite3_finalize(stmt)
            }

            return results
        }
    }

    private func columnString(_ stmt: OpaquePointer?, _ index: Int32) -> String {
        guard let cStr = sqlite3_column_text(stmt, index) else { return "" }
        return String(cString: cStr)
    }

    private static func makeSnippet(from body: String, keyword: String) -> String {
        let compact = body.replacingOccurrences(of: "\n", with: " ")
        if let range = compact.range(of: keyword, options: .caseInsensitive) {
            let start = compact.index(range.lowerBound, offsetBy: -35, limitedBy: compact.startIndex) ?? compact.startIndex
            let end = compact.index(range.upperBound, offsetBy: 65, limitedBy: compact.endIndex) ?? compact.endIndex
            let prefix = start > compact.startIndex ? "…" : ""
            let suffix = end < compact.endIndex ? "…" : ""
            return prefix + String(compact[start..<end]) + suffix
        }
        return String(compact.prefix(110))
    }
}
