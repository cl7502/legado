import Foundation

/// Rule executor — mirrors Android AnalyzeRule.getString() / getStringList() / getElements()
///
/// Key behaviors preserved from Android:
///   • Rule chain: JS blocks split the chain; each non-JS part is one segment
///   • ## inside a segment: "rule##matchPattern##replacement[##replaceFirst]"
///   • @put:{} / @get:{} variable storage (pre-parsed by RuleParser — not split on @)
///   • Intermediate result stays as Any? through the chain (JSON arrays, HTML elements)
///   • Last segment in executeList() returns a list; intermediate segments reduce to single value
class RuleExecutor {
    static let shared = RuleExecutor()

    private let jsEngine = LegadoJSEngine.shared
    private let htmlParser = HTMLParser.shared
    private let jsonEngine = JSONPathEngine.shared

    // MARK: - Public API

    /// Execute rule, return single string result.
    func execute(_ rule: String, in context: inout AnalyzeContext) -> String? {
        let segments = RuleParser.shared.parseChain(rule)
        guard !segments.isEmpty else { return nil }

        var current: Any? = context.result

        for segment in segments {
            var tmp = context
            tmp.result = current
            current = applySegment(segment, current: current, context: &tmp)
            context.variables = tmp.variables
        }

        return stringify(current)
    }

    /// Execute rule, return list of strings (used for book/chapter lists).
    func executeList(_ rule: String, in context: inout AnalyzeContext) -> [String] {
        let segments = RuleParser.shared.parseChain(rule)
        guard !segments.isEmpty else { return [] }

        var current: Any? = context.result

        for (idx, segment) in segments.enumerated() {
            let isLast = idx == segments.count - 1
            var tmp = context
            tmp.result = current

            if isLast {
                // Last segment — produce a list
                current = applySegmentList(segment, current: current, context: &tmp)
            } else {
                // Intermediate — reduce to single value
                current = applySegment(segment, current: current, context: &tmp)
            }
            context.variables = tmp.variables
        }

        return toStringArray(current)
    }

    // MARK: - Internal segment execution

    private func applySegment(_ seg: RuleSegment, current: Any?, context: inout AnalyzeContext) -> Any? {
        let (coreRule, replacePattern, replacement, replaceFirst) = splitHashHash(seg.content)
        var result: Any?

        switch seg.type {
        case .js:
            context.result = current
            result = jsEngine.evaluateRule(coreRule, in: &context)

        case .json:
            let jsonStr = asString(current)
            result = jsonEngine.extract(json: jsonStr, path: coreRule)

        case .xpath:
            let html = asString(current)
            result = htmlParser.xpathText(html, xpath: coreRule)

        case .defaultRule:
            let html = asString(current)
            result = htmlParser.text(html, query: coreRule)

        case .regex:
            let str = asString(current)
            result = applyRegexExtract(str, pattern: coreRule)
        }

        // Apply ## regex replacement if present
        if !replacePattern.isEmpty, let str = stringify(result) {
            result = applyHashHashReplace(str, pattern: replacePattern,
                                          replacement: replacement, replaceFirst: replaceFirst)
        }
        return result
    }

    private func applySegmentList(_ seg: RuleSegment, current: Any?, context: inout AnalyzeContext) -> Any? {
        let (coreRule, replacePattern, replacement, replaceFirst) = splitHashHash(seg.content)
        var result: Any?

        switch seg.type {
        case .js:
            context.result = current
            let jsResult = jsEngine.evaluateRule(coreRule, in: &context)
            // JS may return comma-separated string or an array — try to preserve list
            if let str = jsResult {
                result = str.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            } else {
                result = []
            }

        case .json:
            let jsonStr = asString(current)
            result = jsonEngine.extract(json: jsonStr, path: coreRule)
            // If result is a single value wrap in array; if already array keep it
            if let arr = result as? [Any] {
                result = arr
            } else if let val = result {
                result = [val]
            }

        case .xpath:
            let html = asString(current)
            result = htmlParser.xpathList(html, xpath: coreRule)

        case .defaultRule:
            let html = asString(current)
            result = htmlParser.cssList(html, query: coreRule)

        case .regex:
            let str = asString(current)
            if let match = applyRegexExtract(str, pattern: coreRule) {
                result = [match]
            } else {
                result = []
            }
        }

        // Apply ## replacement to each list element
        if !replacePattern.isEmpty {
            let arr = toStringArray(result)
            result = arr.map {
                applyHashHashReplace($0, pattern: replacePattern,
                                     replacement: replacement, replaceFirst: replaceFirst)
            }
        }
        return result
    }

    // MARK: - ## regex replacement (Android SourceRule.makeUpRule split logic)

    /// Split "rule##matchPattern##replacement[##replaceFirst]"
    private func splitHashHash(_ rule: String) -> (core: String, pattern: String, replacement: String, replaceFirst: Bool) {
        let parts = rule.components(separatedBy: "##")
        let core        = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern     = parts.count > 1 ? parts[1] : ""
        let replacement = parts.count > 2 ? parts[2] : ""
        let replaceFirst = parts.count > 3
        return (core, pattern, replacement, replaceFirst)
    }

    private func applyHashHashReplace(_ text: String, pattern: String,
                                      replacement: String, replaceFirst: Bool) -> String {
        guard !pattern.isEmpty else { return text }
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
            let range = NSRange(text.startIndex..., in: text)
            if replaceFirst {
                // replaceFirst: find first match, replace within that match only
                if let match = regex.firstMatch(in: text, range: range) {
                    let matched = (text as NSString).substring(with: match.range)
                    let replaced = regex.stringByReplacingMatches(
                        in: matched, range: NSRange(matched.startIndex..., in: matched),
                        withTemplate: replacement)
                    return (text as NSString).replacingCharacters(in: match.range, with: replaced)
                }
                return replacement  // no match → return replacement literal
            } else {
                return regex.stringByReplacingMatches(in: text, range: range, withTemplate: replacement)
            }
        } catch {
            return text.replacingOccurrences(of: pattern, with: replacement)
        }
    }

    // MARK: - Regex extraction (: prefix)

    private func applyRegexExtract(_ text: String, pattern: String) -> String? {
        guard !pattern.isEmpty else { return text }
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
            let range = NSRange(text.startIndex..., in: text)
            if let match = regex.firstMatch(in: text, range: range) {
                // Prefer capture group 1 if present
                if match.numberOfRanges > 1, let r = Range(match.range(at: 1), in: text) {
                    return String(text[r])
                }
                if let r = Range(match.range, in: text) {
                    return String(text[r])
                }
            }
        } catch {
            print("❌ [Regex]: \(error)")
        }
        return nil
    }

    // MARK: - Helpers

    private func asString(_ value: Any?) -> String {
        switch value {
        case let s as String: return s
        case let v?:          return "\(v)"
        default:              return ""
        }
    }

    private func stringify(_ value: Any?) -> String? {
        switch value {
        case nil:             return nil
        case let s as String: return s.isEmpty ? nil : s
        case let arr as [Any]:
            let joined = arr.map { "\($0)" }.joined(separator: "\n")
            return joined.isEmpty ? nil : joined
        case let v?:          return "\(v)"
        }
    }

    private func toStringArray(_ value: Any?) -> [String] {
        switch value {
        case nil:               return []
        case let arr as [Any]:  return arr.map { "\($0)" }
        case let s as String:   return s.isEmpty ? [] : [s]
        case let v?:            return ["\(v)"]
        }
    }
}
