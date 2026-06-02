import Foundation

enum RuleType {
    case defaultRule  // CSS selector (may include @attr suffix)
    case xpath
    case json
    case regex
    case js
}

struct RuleSegment {
    let type: RuleType
    let content: String
    // @put:{key:subRule} blocks extracted from this segment (ISSUE-013)
    let putMap: [String: String]

    init(type: RuleType, content: String, putMap: [String: String] = [:]) {
        self.type = type
        self.content = content
        self.putMap = putMap
    }
}

/// Rule chain parser — mirrors Android AnalyzeRule.splitSourceRule()
/// Splits ONLY on JS block boundaries (<js>...</js> / javascript:...\n).
/// The @ character is NOT a chain separator; it is handled internally by
/// each analyzer (CSS @attr, XPath /@attr) or used as a mode prefix (@XPath: etc.).
class RuleParser {
    static let shared = RuleParser()

    // Matches JS blocks: <js>...</js>, javascript:..., or @js:...
    // Android JS_PATTERN includes @js: which runs to end of string.
    // This split boundary allows rule chains like: "$.path@js:decrypt(result)"
    private let jsPattern = try! NSRegularExpression(
        pattern: #"@js:[\w\W]+|javascript:.+?(?:\n|$)|<js>[\w\W]+?</js>"#,
        options: []
    )

    // Matches @put:{key:subRule} blocks — extracted before type detection (ISSUE-013)
    private static let putPattern = try! NSRegularExpression(
        pattern: #"@put:\{[^}]+?\}"#,
        options: [.caseInsensitive]
    )

    func parseChain(_ rule: String) -> [RuleSegment] {
        let trimmed = rule.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        // Pure JS fast path
        if isWholeJS(trimmed) {
            return [parseSingle(trimmed)]
        }

        // Split on JS block boundaries — identical to Android JS_PATTERN logic
        var segments: [RuleSegment] = []
        let ns = trimmed as NSString
        let fullRange = NSRange(location: 0, length: ns.length)
        let matches = jsPattern.matches(in: trimmed, range: fullRange)

        var lastEnd = 0
        for match in matches {
            if match.range.location > lastEnd {
                let pre = ns.substring(with: NSRange(location: lastEnd,
                                                     length: match.range.location - lastEnd))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !pre.isEmpty { segments.append(parseSingle(pre)) }
            }
            segments.append(parseSingle(ns.substring(with: match.range)))
            lastEnd = match.range.location + match.range.length
        }
        if lastEnd < ns.length {
            let tail = ns.substring(from: lastEnd)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !tail.isEmpty { segments.append(parseSingle(tail)) }
        }
        return segments.isEmpty ? [parseSingle(trimmed)] : segments
    }

    // MARK: - Private

    private func isWholeJS(_ s: String) -> Bool {
        s.hasPrefix("javascript:") ||
        s.hasPrefix("@js:") ||
        (s.hasPrefix("<js>") && s.hasSuffix("</js>"))
    }

    /// Extract @put:{key:subRule} blocks from rule string.
    /// 用括号深度计数而非正则匹配，支持子规则中含 } 的情况（如 @js: 块、JSON 访问器）。
    /// Returns (cleanedRule, putMap).
    private func extractPutMap(from rule: String) -> (String, [String: String]) {
        var putMap: [String: String] = [:]
        var cleaned = rule
        var searchFrom = cleaned.startIndex

        while let putRange = cleaned.range(of: "@put:{", range: searchFrom..<cleaned.endIndex) {
            // 从 { 开始用深度计数找对应的闭合 }
            var depth = 0
            var endIdx: String.Index? = nil
            var i = cleaned.index(before: putRange.upperBound) // 指向 {
            while i < cleaned.endIndex {
                if cleaned[i] == "{" { depth += 1 }
                else if cleaned[i] == "}" {
                    depth -= 1
                    if depth == 0 { endIdx = i; break }
                }
                i = cleaned.index(after: i)
            }
            guard let closingIdx = endIdx else { break }

            let fullMatch = String(cleaned[putRange.lowerBound...closingIdx])
            let jsonStr   = String(fullMatch.dropFirst(5)) // drop "@put:" → {key:rule}
            let parsed    = parsePutContent(jsonStr)
            putMap.merge(parsed) { _, new in new }
            cleaned.removeSubrange(putRange.lowerBound...closingIdx)
            searchFrom = putRange.lowerBound < cleaned.endIndex ? putRange.lowerBound : cleaned.endIndex
        }
        return (cleaned.trimmingCharacters(in: .whitespacesAndNewlines), putMap)
    }

    /// Lenient JSON-like parser for @put content: {key:rule} or {"key":"rule"}
    private func parsePutContent(_ jsonStr: String) -> [String: String] {
        var s = jsonStr.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.hasPrefix("{") && s.hasSuffix("}") else { return [:] }

        // Try standard JSON first (fully-quoted format)
        if let data = s.data(using: .utf8),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
            return dict
        }

        // Lenient: split the inner content by top-level commas, then split each chunk by first colon.
        // This correctly handles {id:id,name:name,author:author} with multiple unquoted pairs.
        let inner = String(s.dropFirst().dropLast())
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !inner.isEmpty else { return [:] }

        var result: [String: String] = [:]
        // Split by commas that are NOT inside nested brackets { } [ ]
        var depth = 0
        var current = ""
        var pairs: [String] = []
        for ch in inner {
            if ch == "{" || ch == "[" { depth += 1; current.append(ch) }
            else if ch == "}" || ch == "]" { depth -= 1; current.append(ch) }
            else if ch == "," && depth == 0 { pairs.append(current); current = "" }
            else { current.append(ch) }
        }
        if !current.isEmpty { pairs.append(current) }

        for pair in pairs {
            let trimmed = pair.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let colonIdx = trimmed.firstIndex(of: ":") else { continue }
            let key = trimmed[..<colonIdx]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            let value = String(trimmed[trimmed.index(after: colonIdx)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            if !key.isEmpty { result[key] = value }
        }
        return result
    }

    private func parseSingle(_ rule: String) -> RuleSegment {
        var trimmed = rule.trimmingCharacters(in: .whitespacesAndNewlines)

        // JS — @put has no meaning inside JS blocks
        if isWholeJS(trimmed) {
            let code: String
            if trimmed.hasPrefix("javascript:") {
                code = String(trimmed.dropFirst(11))
            } else if trimmed.hasPrefix("@js:") {
                code = String(trimmed.dropFirst(4))
            } else {
                // <js>...</js>
                code = String(trimmed.dropFirst(4).dropLast(5))
            }
            return RuleSegment(type: .js, content: code)
        }

        // Extract @put:{} blocks before type detection (ISSUE-013)
        let (cleaned, putMap) = extractPutMap(from: trimmed)
        trimmed = cleaned

        let lower = trimmed.lowercased()

        // Explicit XPath prefixes
        if lower.hasPrefix("@xpath:") {
            return RuleSegment(type: .xpath, content: String(trimmed.dropFirst(7)), putMap: putMap)
        }
        if lower.hasPrefix("xpath:") {
            return RuleSegment(type: .xpath, content: String(trimmed.dropFirst(6)), putMap: putMap)
        }

        // Explicit JSON prefixes
        if lower.hasPrefix("@json:") {
            return RuleSegment(type: .json, content: String(trimmed.dropFirst(6)), putMap: putMap)
        }
        if lower.hasPrefix("json:") {
            return RuleSegment(type: .json, content: String(trimmed.dropFirst(5)), putMap: putMap)
        }

        // @@ or @CSS: → force CSS (strip prefix)
        if trimmed.hasPrefix("@@") {
            return RuleSegment(type: .defaultRule, content: String(trimmed.dropFirst(2)), putMap: putMap)
        }
        if lower.hasPrefix("@css:") {
            return RuleSegment(type: .defaultRule, content: String(trimmed.dropFirst(5)), putMap: putMap)
        }

        // Auto-detect JSONPath: $. or $[
        if trimmed.hasPrefix("$.") || trimmed.hasPrefix("$[") {
            return RuleSegment(type: .json, content: trimmed, putMap: putMap)
        }

        // Auto-detect XPath: leading / but not //www (avoid mistaking URLs)
        // Exclude URL templates (containing {{...}}) — those expand to literal URL values,
        // not XPath expressions. e.g. /novel/{{$.novelId}}?isSearch=1 is a URL template.
        if trimmed.hasPrefix("/") && !trimmed.hasPrefix("//www.") && !trimmed.hasPrefix("//m.")
            && !trimmed.contains("{{") {
            return RuleSegment(type: .xpath, content: trimmed, putMap: putMap)
        }

        // Regex prefix :
        if trimmed.hasPrefix(":") {
            return RuleSegment(type: .regex, content: String(trimmed.dropFirst(1)), putMap: putMap)
        }

        return RuleSegment(type: .defaultRule, content: trimmed, putMap: putMap)
    }
}
