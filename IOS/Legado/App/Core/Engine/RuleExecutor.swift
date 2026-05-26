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
        let segments = RuleParser.shared.parseChain(rule)
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
            let html = asString(current)
            result = htmlParser.text(html, query: coreRule)

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
                if let match = regex.firstMatch(in: text, range: range) {
                    let matched = (text as NSString).substring(with: match.range)
                    let replaced = regex.stringByReplacingMatches(
                        in: matched, range: NSRange(matched.startIndex..., in: matched),
                        withTemplate: replacement)
                    return (text as NSString).replacingCharacters(in: match.range, with: replaced)
                }
                return replacement
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
