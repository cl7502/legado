// IOS/Legado/App/Core/Services/ExploreUrlParser.swift
import Foundation

// Moved from ExploreView.swift — same module, ExploreView accesses without import.
struct ExploreCategory: Codable, Identifiable {
    // Use title+url as ID so that two categories with the same URL but different
    // titles are treated as distinct. Prevents the SwiftUI "duplicate ID" warning.
    var id: String { "\(title)|\(url)" }
    var title: String
    var url: String
}

/// Shared exploreUrl parser — used by ExploreCategoryViewModel and DeepCheckPipeline.
struct ExploreUrlParser {

    /// Parse `exploreUrl` string into (title, url) pairs.
    /// Handles: @js: prefix (via AnalyzeUrl.parse), JSON array, newline+:: format, plain URL.
    static func parse(_ exploreUrl: String, context: AnalyzeContext) -> [ExploreCategory] {
        var raw = exploreUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return [] }

        // @js: / javascript: — evaluate via AnalyzeUrl.parse (mirrors existing ExploreView logic)
        if raw.hasPrefix("@js:") || raw.lowercased().hasPrefix("javascript:") {
            var ctx = context
            let parsed = AnalyzeUrl.parse(raw, context: ctx)
            if parsed.url.lowercased().hasPrefix("http") {
                raw = parsed.url
            } else {
                // Fallback: try LegadoJSEngine direct evaluation
                let code = raw.hasPrefix("@js:") ? String(raw.dropFirst(4)) : String(raw.dropFirst(11))
                if let result = LegadoJSEngine.shared.evaluateRule(code, in: &ctx), !result.isEmpty {
                    raw = result
                } else {
                    return []
                }
            }
        }

        // JSON array: [{"title":"...","url":"..."},...]
        // 也处理 JS 对象字面量格式（单引号、无引号 key），通过 JS 引擎规范化为 JSON
        if raw.hasPrefix("[") {
            if let arr = decodeExploreArray(raw) {
                let cats = arr.compactMap { cat -> ExploreCategory? in
                    let u = cat.url.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !u.isEmpty else { return nil }
                    let t = cat.title.trimmingCharacters(in: .whitespacesAndNewlines)
                    return ExploreCategory(title: t.isEmpty ? "全部" : t, url: u)
                }
                if !cats.isEmpty { return deduplicated(cats) }
            }
            // JSON 解析失败时通过 JS 引擎规范化（处理单引号、无引号 key 的 JS 对象字面量）
            var ctx = context
            let jsCode = "JSON.stringify(\(raw))"
            if let jsonStr = LegadoJSEngine.shared.evaluateRule(jsCode, in: &ctx),
               jsonStr.hasPrefix("["),
               let arr = decodeExploreArray(jsonStr) {
                let cats = arr.compactMap { cat -> ExploreCategory? in
                    let u = cat.url.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !u.isEmpty else { return nil }
                    let t = cat.title.trimmingCharacters(in: .whitespacesAndNewlines)
                    return ExploreCategory(title: t.isEmpty ? "全部" : t, url: u)
                }
                if !cats.isEmpty { return deduplicated(cats) }
            }
        }

        // Newline-separated: "名称::URL" | "名称,http://..." | plain URL per line
        let lines = raw.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if lines.count > 1 || lines.first?.contains("::") == true
                             || lines.first?.contains(",http") == true {
            let cats: [ExploreCategory] = lines.compactMap { line in
                if line.contains("::") {
                    let parts = line.components(separatedBy: "::")
                    let title = parts[0].trimmingCharacters(in: .whitespaces)
                    let url   = parts.dropFirst().joined(separator: "::").trimmingCharacters(in: .whitespaces)
                    guard !url.isEmpty else { return nil }
                    return ExploreCategory(title: title.isEmpty ? "全部" : title, url: url)
                } else if let r = line.range(of: ",http") {
                    let title = String(line[line.startIndex..<r.lowerBound]).trimmingCharacters(in: .whitespaces)
                    let url   = "http" + String(line[r.upperBound...]).trimmingCharacters(in: .whitespaces)
                    return ExploreCategory(title: title.isEmpty ? "全部" : title, url: url)
                } else if line.hasPrefix("http") || line.hasPrefix("/") || line.hasPrefix("./") {
                    return ExploreCategory(title: "全部", url: line)
                }
                return nil
            }
            if !cats.isEmpty { return deduplicated(cats) }
        }

        // Fallback: single URL
        return [ExploreCategory(title: "全部", url: raw)]
    }

    private static func deduplicated(_ cats: [ExploreCategory]) -> [ExploreCategory] {
        var seen = Set<String>()
        return cats.filter { seen.insert($0.id).inserted }
    }

    /// 解码 explore JSON 数组，忽略书源中额外的 style 等字段
    private static func decodeExploreArray(_ json: String) -> [ExploreCategory]? {
        guard let data = json.data(using: .utf8) else { return nil }
        // 先尝试直接解码（标准 JSON）
        if let arr = try? JSONDecoder().decode([ExploreCategory].self, from: data) { return arr }
        // 尝试宽松解码：只提取 title/url，忽略 style 等额外字段
        if let raw = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            return raw.compactMap { dict -> ExploreCategory? in
                let title = dict["title"] as? String ?? ""
                let url   = dict["url"]   as? String ?? ""
                return ExploreCategory(title: title, url: url)
            }
        }
        return nil
    }
}
