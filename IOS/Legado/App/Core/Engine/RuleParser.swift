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
}

/// Rule chain parser — mirrors Android AnalyzeRule.splitSourceRule()
/// Splits ONLY on JS block boundaries (<js>...</js> / javascript:...\n).
/// The @ character is NOT a chain separator; it is handled internally by
/// each analyzer (CSS @attr, XPath /@attr) or used as a mode prefix (@XPath: etc.).
class RuleParser {
    static let shared = RuleParser()

    // Matches <js>...</js> or javascript:... (up to next newline)
    private let jsPattern = try! NSRegularExpression(
        pattern: #"javascript:.+?(?:\n|$)|<js>[\w\W]+?</js>"#,
        options: []
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
        (s.hasPrefix("<js>") && s.hasSuffix("</js>"))
    }

    private func parseSingle(_ rule: String) -> RuleSegment {
        let trimmed = rule.trimmingCharacters(in: .whitespacesAndNewlines)

        // JS
        if isWholeJS(trimmed) {
            let code: String
            if trimmed.hasPrefix("javascript:") {
                code = String(trimmed.dropFirst(11))
            } else {
                // <js>...</js>
                code = String(trimmed.dropFirst(4).dropLast(5))
            }
            return RuleSegment(type: .js, content: code)
        }

        let lower = trimmed.lowercased()

        // Explicit XPath prefixes
        if lower.hasPrefix("@xpath:") {
            return RuleSegment(type: .xpath, content: String(trimmed.dropFirst(7)))
        }
        if lower.hasPrefix("xpath:") {
            return RuleSegment(type: .xpath, content: String(trimmed.dropFirst(6)))
        }

        // Explicit JSON prefixes
        if lower.hasPrefix("@json:") {
            return RuleSegment(type: .json, content: String(trimmed.dropFirst(6)))
        }
        if lower.hasPrefix("json:") {
            return RuleSegment(type: .json, content: String(trimmed.dropFirst(5)))
        }

        // @@ or @CSS: → force CSS (strip prefix)
        if trimmed.hasPrefix("@@") {
            return RuleSegment(type: .defaultRule, content: String(trimmed.dropFirst(2)))
        }
        if lower.hasPrefix("@css:") {
            return RuleSegment(type: .defaultRule, content: String(trimmed.dropFirst(5)))
        }

        // Auto-detect JSONPath: $. or $[
        if trimmed.hasPrefix("$.") || trimmed.hasPrefix("$[") {
            return RuleSegment(type: .json, content: trimmed)
        }

        // Auto-detect XPath: leading / but not //www (avoid mistaking URLs)
        if trimmed.hasPrefix("/") && !trimmed.hasPrefix("//www.") && !trimmed.hasPrefix("//m.") {
            return RuleSegment(type: .xpath, content: trimmed)
        }

        // Regex prefix :
        if trimmed.hasPrefix(":") {
            return RuleSegment(type: .regex, content: String(trimmed.dropFirst(1)))
        }

        return RuleSegment(type: .defaultRule, content: trimmed)
    }
}
