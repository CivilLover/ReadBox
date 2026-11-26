import Foundation

/// Standard Obsidian-compatible YAML Frontmatter serializer & parser for `.md` files.
public enum FrontmatterParser {
    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    public static func renderKnowledgeMarkdown(doc: KnowledgeDoc) -> String {
        var lines: [String] = ["---"]
        lines.append("id: \(escapeYAML(doc.id))")
        lines.append("title: \(escapeYAML(doc.title))")
        lines.append("created: \(isoFormatter.string(from: doc.createdAt))")
        lines.append("updated: \(isoFormatter.string(from: doc.updatedAt))")
        if let model = doc.generatedByModel, !model.isEmpty {
            lines.append("generated_by: \(escapeYAML(model))")
        }
        if !doc.tags.isEmpty {
            lines.append("tags:")
            for tag in doc.tags {
                lines.append("  - \(escapeYAML(tag))")
            }
        }
        if !doc.sourceClipIds.isEmpty {
            lines.append("source_clip_ids:")
            for cid in doc.sourceClipIds {
                lines.append("  - \(escapeYAML(cid))")
            }
        }
        if !doc.sourceLinks.isEmpty {
            lines.append("sources:")
            for link in doc.sourceLinks {
                lines.append("  - \(escapeYAML(link))")
            }
        }
        lines.append("---")
        lines.append("")
        lines.append(doc.content)
        return lines.joined(separator: "\n")
    }

    public static func parseKnowledgeMarkdown(_ raw: String, fileName: String, fallbackDate: Date = Date()) -> KnowledgeDoc {
        var meta: [String: String] = [:]
        var listMeta: [String: [String]] = [:]
        var body = raw

        if raw.hasPrefix("---\n") || raw.hasPrefix("---\r\n") {
            let lines = raw.components(separatedBy: .newlines)
            var endIdx: Int?
            var currentListKey: String?

            for i in 1..<lines.count {
                let line = lines[i]
                if line.trimmingCharacters(in: .whitespaces) == "---" {
                    endIdx = i
                    break
                }
                if line.hasPrefix("  - ") || line.hasPrefix("- ") {
                    if let key = currentListKey {
                        let item = line
                            .trimmingCharacters(in: .whitespaces)
                            .dropFirst(2)
                            .trimmingCharacters(in: .whitespaces)
                        listMeta[key, default: []].append(unescapeYAML(String(item)))
                    }
                    continue
                }
                currentListKey = nil
                if let colonIdx = line.firstIndex(of: ":") {
                    let key = String(line[..<colonIdx]).trimmingCharacters(in: .whitespaces)
                    let value = String(line[line.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)
                    if value.isEmpty {
                        currentListKey = key
                    } else {
                        meta[key] = unescapeYAML(value)
                    }
                }
            }

            if let endIdx {
                let remaining = lines.dropFirst(endIdx + 1)
                body = remaining.joined(separator: "\n").trimmingCharacters(in: CharacterSet(charactersIn: "\n"))
            }
        }

        let defaultTitle = (fileName as NSString).deletingPathExtension
        let title = meta["title"].flatMap { $0.isEmpty ? nil : $0 } ?? defaultTitle
        let id = meta["id"].flatMap { $0.isEmpty ? nil : $0 } ?? UUID().uuidString
        let created = meta["created"].flatMap { isoFormatter.date(from: $0) } ?? fallbackDate
        let updated = meta["updated"].flatMap { isoFormatter.date(from: $0) } ?? fallbackDate

        return KnowledgeDoc(
            id: id,
            fileName: fileName,
            title: title,
            tags: listMeta["tags"] ?? [],
            sourceClipIds: listMeta["source_clip_ids"] ?? [],
            sourceLinks: listMeta["sources"] ?? [],
            content: body,
            createdAt: created,
            updatedAt: updated,
            generatedByModel: meta["generated_by"]
        )
    }

    public static func renderClipArticleMarkdown(clip: ClipItem, bodyMarkdown: String) -> String {
        var lines: [String] = ["---"]
        lines.append("id: \(escapeYAML(clip.id))")
        lines.append("title: \(escapeYAML(clip.title))")
        if !clip.url.isEmpty { lines.append("source: \(escapeYAML(clip.url))") }
        if !clip.author.isEmpty { lines.append("author: \(escapeYAML(clip.author))") }
        lines.append("type: \(clip.sourceType.rawValue)")
        lines.append("saved: \(isoFormatter.string(from: clip.createdAt))")
        if !clip.tags.isEmpty {
            lines.append("tags:")
            for t in clip.tags {
                lines.append("  - \(escapeYAML(t))")
            }
        }
        lines.append("---")
        lines.append("")
        lines.append("# \(clip.title)")
        lines.append("")
        lines.append(bodyMarkdown)
        return lines.joined(separator: "\n")
    }

    private static func escapeYAML(_ text: String) -> String {
        let cleaned = text.replacingOccurrences(of: "\n", with: " ")
        if cleaned.contains(":") || cleaned.contains("#") || cleaned.contains("\"") || cleaned.contains("'") || cleaned.hasPrefix("[") || cleaned.hasPrefix("{") {
            let escaped = cleaned.replacingOccurrences(of: "\"", with: "\\\"")
            return "\"\(escaped)\""
        }
        return cleaned
    }

    private static func unescapeYAML(_ text: String) -> String {
        var s = text.trimmingCharacters(in: .whitespaces)
        if (s.hasPrefix("\"") && s.hasSuffix("\"")) || (s.hasPrefix("'") && s.hasSuffix("'")), s.count >= 2 {
            s = String(s.dropFirst().dropLast())
            s = s.replacingOccurrences(of: "\\\"", with: "\"")
        }
        return s
    }
}
