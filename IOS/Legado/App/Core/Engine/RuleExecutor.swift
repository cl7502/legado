import Foundation

/// Rule executor — mirrors Android AnalyzeRule.getString() / getStringList() / getElements()
///
/// Key behaviors preserved from Android:
///   • Rule chain: JS blocks split the chain; each non-JS part is one segment
///   • ## inside a segment: "rule##matchPattern##replacement[##replaceFirst]"
///   • @put:{key:subRule} variable store (per-segment, runs against current content)
///   • @get:{varName} / {{jsExpr}} inline substitution before rule execution
///   • Intermediate result stays as Any? through the chain (JSON arrays, HTML elements)
///   • Last segment in executeList() returns a list; intermediate segments reduce to single value
class RuleExecutor {
    static let shared = RuleExecutor()

    private let jsEngine = LegadoJSEngine.shared
    private let htmlParser = HTMLParser.shared
    private let jsonEngine = JSONPathEngine.shared

    // Matches @get:{varName} and {{jsExpr}} — same as Android evalPattern (ISSUE-013/014)
    private static let evalPattern = try! NSRegularExpression(
        pattern: #"@get:\{[^}]+?\}|\{\{[\w\W]*?\}\}"#,
        options: [.caseInsensitive]
    )

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
        // Strip Android-only page-rendering directives that have no lightweight iOS equivalent.
        // #imgload / #webView signal "use a WebView to trigger lazy-load before parsing".
        // Without a full headless browser we can't honour the intent, but stripping the prefix
        // lets the normal HTML parser attempt the rule on the raw response — images may be
        // missing their src but the list structure is still extracted correctly.
        var effectiveRule = rule
        for prefix in ["#imgload", "#webView", "#webview", "#javascript"] {
            if effectiveRule.hasPrefix(prefix) {
                effectiveRule = String(effectiveRule.dropFirst(prefix.count))
                if effectiveRule.hasPrefix("@") { effectiveRule = String(effectiveRule.dropFirst()) }
                break
            }
        }
        let segments = RuleParser.shared.parseChain(effectiveRule)
        guard !segments.isEmpty else { return [] }

        var current: Any? = context.result

        for (idx, segment) in segments.enumerated() {
            let isLast = idx == segments.count - 1
            var tmp = context
            tmp.result = current

            if isLast {
                current = applySegmentList(segment, current: current, context: &tmp)
            } else {
                current = applySegment(segment, current: current, context: &tmp)
            }
            context.variables = tmp.variables
        }

        return toStringArray(current)
    }

    // MARK: - Internal segment execution

    private func applySegment(_ seg: RuleSegment, current: Any?, context: inout AnalyzeContext) -> Any? {
        // ISSUE-013: Execute @put sub-rules against current content, store in variables
        executePutMap(seg.putMap, current: current, context: &context)

        // ISSUE-013/014: Expand @get:{} and {{jsExpr}} in the full content (before ## split)
        let expandedContent = expandEval(seg.content, current: current, context: &context)
        let (coreRule, replacePattern, replacement, replaceFirst) = splitHashHash(expandedContent)
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
            // CSS selectors never start with "/" or "http".
            // When a URL template like "/novel/{{$.novelId}}/chapters" expands to a path,
            // return it directly rather than passing it to the CSS parser (which returns nil).
            if coreRule.hasPrefix("/") || coreRule.hasPrefix("http://") || coreRule.hasPrefix("https://") {
                result = coreRule
            } else {
                let html = asString(current)
                result = htmlParser.text(html, query: coreRule)
            }

        case .regex:
            let str = asString(current)
            result = applyRegexExtract(str, pattern: coreRule)
        }

        if !replacePattern.isEmpty, let str = stringify(result) {
            result = applyHashHashReplace(str, pattern: replacePattern,
                                          replacement: replacement, replaceFirst: replaceFirst)
        }
        return result
    }

    private func applySegmentList(_ seg: RuleSegment, current: Any?, context: inout AnalyzeContext) -> Any? {
        // ISSUE-013: Execute @put sub-rules
        executePutMap(seg.putMap, current: current, context: &context)

        // ISSUE-013/014: Expand @get:{} and {{jsExpr}}
        let expandedContent = expandEval(seg.content, current: current, context: &context)
        let (coreRule, replacePattern, replacement, replaceFirst) = splitHashHash(expandedContent)
        var result: Any?

        switch seg.type {
        case .js:
            context.result = current
            let jsResult = jsEngine.evaluateRule(coreRule, in: &context)
            if let str = jsResult {
                // Android AnalyzeRule.getStringList (L228): splits JS String result on \n.
                // Arrays are already \n-joined by LegadoJSEngine before arriving here.
                result = str.components(separatedBy: "\n")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            } else {
                result = []
            }

        case .json:
            let jsonStr = asString(current)
            result = jsonEngine.extract(json: jsonStr, path: coreRule)
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

        if !replacePattern.isEmpty {
            let arr = toStringArray(result)
            result = arr.map {
                applyHashHashReplace($0, pattern: replacePattern,
                                     replacement: replacement, replaceFirst: replaceFirst)
            }
        }
        return result
    }

    // MARK: - @put execution (ISSUE-013)

    /// Execute each sub-rule in putMap against current content, store results in context.variables.
    /// Mirrors Android AnalyzeRule.putRule().
    private func executePutMap(_ putMap: [String: String], current: Any?, context: inout AnalyzeContext) {
        guard !putMap.isEmpty else { return }
        var tempCtx = context
        tempCtx.result = current
        for (key, subRule) in putMap {
            let value = execute(subRule, in: &tempCtx) ?? ""
            context.variables[key] = value
        }
        // Propagate any variables set by sub-rules' JS
        context.variables.merge(tempCtx.variables) { _, new in new }
    }

    // MARK: - @get:{} / {{jsExpr}} expansion (ISSUE-013/014)

    /// Substitute @get:{varName} and {{jsExpr}} occurrences in a rule string.
    /// Mirrors Android SourceRule.makeUpRule() @get / {{}} handling.
    private func expandEval(_ rule: String, current: Any?, context: inout AnalyzeContext) -> String {
        guard rule.contains("@get:") || rule.contains("{{") else { return rule }

        let matches = Self.evalPattern.matches(in: rule, range: NSRange(rule.startIndex..., in: rule))
        guard !matches.isEmpty else { return rule }

        var output = ""
        var lastEnd = rule.startIndex

        for match in matches {
            guard let matchRange = Range(match.range, in: rule) else { continue }
            output += rule[lastEnd..<matchRange.lowerBound]

            let matchStr = String(rule[matchRange])
            let lower = matchStr.lowercased()

            if lower.hasPrefix("@get:{") && matchStr.hasSuffix("}") {
                // @get:{varName} → context.variables[varName]
                let varName = String(matchStr.dropFirst(6).dropLast(1))
                let value = context.variables[varName]
                output += value.map { "\($0)" } ?? ""

            } else if matchStr.hasPrefix("{{") && matchStr.hasSuffix("}}") {
                // {{jsExpr}} — evaluate expression with current result in scope.
                // Special case: if the expression looks like a JSONPath ($.x / $[x]),
                // evaluate it as JSONPath on current result rather than as JS.
                // This matches Android Legado behavior where {{$.novelId}} in a URL
                // template extracts the field from the current JSON item.
                let expr = String(matchStr.dropFirst(2).dropLast(2))
                if expr.hasPrefix("$.") || expr.hasPrefix("$[") {
                    let jsonStr = asString(current)
                    let extracted = jsonEngine.extract(json: jsonStr, path: expr)
                    output += stringify(extracted) ?? ""
                } else {
                    var tempCtx = context
                    tempCtx.result = current
                    let evaluated = jsEngine.evaluateRule(expr, in: &tempCtx) ?? ""
                    context.variables = tempCtx.variables
                    output += evaluated
                }

            } else {
                output += matchStr
            }

            lastEnd = matchRange.upperBound
        }

        output += rule[lastEnd...]
        return output
    }

    // MARK: - ## regex replacement (Android SourceRule.makeUpRule split logic)

    /// Split "rule##matchPattern##replacement[##^]"
    /// parts[2] is replacement; parts[3] is optional flag ("^" = replaceFirst).
    private func splitHashHash(_ rule: String) -> (core: String, pattern: String, replacement: String, replaceFirst: Bool) {
        let parts       = rule.components(separatedBy: "##")
        let core        = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern     = parts.count > 1 ? parts[1] : ""
        let replacement = parts.count > 2 ? parts[2] : ""
        // Android convention: "^" flag in parts[3] means replaceFirst; anything else means replace all.
        // Trailing "###" in book source rules is a terminator (parts[3]="#"), NOT replaceFirst.
        let replaceFirst = parts.count > 3 && parts[3].trimmingCharacters(in: .whitespaces) == "^"
        return (core, pattern, replacement, replaceFirst)
    }

    private func applyHashHashReplace(_ text: String, pattern: String,
                                      replacement: String, replaceFirst: Bool) -> String {
        guard !pattern.isEmpty else { return text }
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
            let range = NSRange(text.startIndex..., in: text)
            let result: String
            if replaceFirst {
                // 无匹配时返回原文（Android 行为），而非 replacement 本身
                if let match = regex.firstMatch(in: text, range: range) {
                    result = regex.stringByReplacingMatches(in: text, range: match.range, withTemplate: replacement)
                } else {
                    return text
                }
            } else {
                result = regex.stringByReplacingMatches(in: text, range: range, withTemplate: replacement)
            }
            var cleaned = result
            // Fix: when the regex matched a substring INSIDE an absolute URL (e.g. "/101045" inside
            // "https://www.biquge.casa/101045/"), the result may be "https://source.comhttps://cdn.com/...".
            // Detect and strip only when the prefix before the embedded scheme is purely scheme+host
            // (i.e., contains no "/" beyond the "//" in "https://"), to avoid breaking rules like
            // img@src##(.*)##$1,{"headers":{"Referer":"$1"}} where the Referer also contains "https://".
            if cleaned.hasPrefix("http"), cleaned.count > 8 {
                let afterScheme = cleaned.index(cleaned.startIndex, offsetBy: min(8, cleaned.count))
                if let r = cleaned.range(of: "https://", range: afterScheme..<cleaned.endIndex)
                         ?? cleaned.range(of: "http://",  range: afterScheme..<cleaned.endIndex) {
                    let prefix = String(cleaned[..<r.lowerBound])
                    // Only strip when prefix is purely scheme+host: exactly 2 slashes ("https://")
                    // and nothing after host (no path segments like /image/... or /abc.jpg,...).
                    let slashCount = prefix.filter { $0 == "/" }.count
                    if slashCount <= 2 {
                        cleaned = String(cleaned[r.lowerBound...])
                    }
                }
            }
            // Strip trailing slash from image URLs (artifact of regex not consuming the full path
            // including its trailing slash, e.g. ".jpg/" left over from "/101045/").
            if cleaned.hasPrefix("http"), cleaned.hasSuffix("/"),
               let pathExt = URL(string: cleaned)?.pathExtension, !pathExt.isEmpty {
                cleaned = String(cleaned.dropLast())
            }
            return cleaned
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
        case let v? where JSONSerialization.isValidJSONObject(v):
            return (try? JSONSerialization.data(withJSONObject: v))
                .flatMap { String(data: $0, encoding: .utf8) } ?? "\(v)"
        case let v?:          return "\(v)"
        default:              return ""
        }
    }

    private func stringify(_ value: Any?) -> String? {
        switch value {
        case nil:             return nil
        case let s as String: return s.isEmpty ? nil : s
        case let arr as [Any]:
            // Serialize each element to JSON if possible, else string-interpolate
            let joined = arr.map { el -> String in
                if JSONSerialization.isValidJSONObject(el),
                   let d = try? JSONSerialization.data(withJSONObject: el),
                   let j = String(data: d, encoding: .utf8) { return j }
                return "\(el)"
            }.joined(separator: "\n")
            return joined.isEmpty ? nil : joined
        case let v? where JSONSerialization.isValidJSONObject(v):
            return (try? JSONSerialization.data(withJSONObject: v))
                .flatMap { String(data: $0, encoding: .utf8) }
        case let v?:          return "\(v)"
        }
    }

    private func toStringArray(_ value: Any?) -> [String] {
        switch value {
        case nil:               return []
        case let arr as [Any]:
            return arr.map { el -> String in
                if let s = el as? String { return s }
                // Serialize JSON objects/arrays to valid JSON string
                // (not Swift's "\(dict)" which produces invalid JSON notation)
                if JSONSerialization.isValidJSONObject(el),
                   let d = try? JSONSerialization.data(withJSONObject: el),
                   let j = String(data: d, encoding: .utf8) { return j }
                return "\(el)"
            }
        case let s as String:   return s.isEmpty ? [] : [s]
        case let v?:
            if JSONSerialization.isValidJSONObject(v),
               let d = try? JSONSerialization.data(withJSONObject: v),
               let j = String(data: d, encoding: .utf8) { return [j] }
            return ["\(v)"]
        }
    }
}
