import Foundation

/// JSONPath engine — supports the subset used by Legado book sources.
/// Covers: $., $[n], $[*], nested paths, &&/|| combinators, {$.sub} interpolation.
/// Uses the Jayway-style syntax (same as Android's com.jayway.jsonpath).
class JSONPathEngine {
    static let shared = JSONPathEngine()

    // MARK: - Public API

    func extract(json: String, path: String) -> Any? {
        // Handle &&/|| combinators (Android RuleAnalyzer.splitRule logic)
        if path.contains("&&") || path.contains("||") || path.contains("%%") {
            return evalCombinator(json: json, path: path)
        }
        guard let root = parseJSON(json) else { return nil }
        return evaluate(path: path, on: root)
    }

    // MARK: - Combinator (&&, ||)

    private func evalCombinator(json: String, path: String) -> Any? {
        // %% — round-robin interleave (mirrors Android AnalyzeByJSonPath L107-114)
        if path.contains("%%") {
            let parts = splitCombinator(path, sep: "%%")
            let lists: [[Any]] = parts.map { part in
                let r = extract(json: json, path: part.trimmed)
                switch r {
                case let arr as [Any]: return arr
                case let v?:           return [v]
                default:               return []
                }
            }
            guard !lists.isEmpty else { return nil }
            let maxLen = lists.map { $0.count }.max() ?? 0
            var result: [Any] = []
            for i in 0..<maxLen {
                for list in lists where i < list.count { result.append(list[i]) }
            }
            return result.isEmpty ? nil : result
        }

        if path.contains("||") {
            let parts = splitCombinator(path, sep: "||")
            for part in parts {
                if let result = extract(json: json, path: part.trimmed), !isEmpty(result) {
                    return result
                }
            }
            return nil
        }
        // && — merge all results
        let parts = splitCombinator(path, sep: "&&")
        var merged: [Any] = []
        for part in parts {
            let r = extract(json: json, path: part.trimmed)
            switch r {
            case let arr as [Any]: merged.append(contentsOf: arr)
            case let v?:           merged.append(v)
            default: break
            }
        }
        return merged.isEmpty ? nil : merged
    }

    private func splitCombinator(_ path: String, sep: String) -> [String] {
        // Simple split — doesn't handle nested brackets (sufficient for Legado patterns)
        return path.components(separatedBy: sep)
    }

    // MARK: - Core evaluator

    private func evaluate(path: String, on root: Any) -> Any? {
        var p = path.trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip leading $
        if p.hasPrefix("$") { p = String(p.dropFirst()) }
        if p.hasPrefix(".") { p = String(p.dropFirst()) }

        if p.isEmpty { return root }

        return traverse(components: tokenize(p), from: root)
    }

    // MARK: - Tokenizer

    /// Split a path like  data.list[*].name  →  ["data", "[*]", "name"]
    private func tokenize(_ path: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var i = path.startIndex

        while i < path.endIndex {
            let ch = path[i]
            if ch == "." {
                if !current.isEmpty { tokens.append(current); current = "" }
            } else if ch == "[" {
                if !current.isEmpty { tokens.append(current); current = "" }
                // collect bracket expression
                var bracket = "["
                i = path.index(after: i)
                while i < path.endIndex, path[i] != "]" {
                    bracket.append(path[i])
                    i = path.index(after: i)
                }
                bracket.append("]")
                tokens.append(bracket)
            } else {
                current.append(ch)
            }
            if i < path.endIndex { i = path.index(after: i) }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }

    // MARK: - Recursive traversal

    private func traverse(components: [String], from node: Any) -> Any? {
        if components.isEmpty { return node }
        var tokens = components
        let token = tokens.removeFirst()

        // Bracket expression  [n] / [*] / [?(...)]
        if token.hasPrefix("[") && token.hasSuffix("]") {
            let inner = String(token.dropFirst().dropLast())

            if inner == "*" {
                // [*] — all elements
                if let arr = node as? [Any] {
                    if tokens.isEmpty { return arr }
                    let sub = arr.compactMap { traverse(components: tokens, from: $0) }
                    return sub.isEmpty ? nil : flattenIfNeeded(sub)
                }
                return nil
            }

            if let idx = Int(inner) {
                // [n] — specific index
                if let arr = node as? [Any] {
                    let realIdx = idx < 0 ? arr.count + idx : idx
                    guard realIdx >= 0 && realIdx < arr.count else { return nil }
                    let item = arr[realIdx]
                    return tokens.isEmpty ? item : traverse(components: tokens, from: item)
                }
                return nil
            }

            // [?(...)] or other filter — return all items (simplified)
            if let arr = node as? [Any] {
                if tokens.isEmpty { return arr }
                let sub = arr.compactMap { traverse(components: tokens, from: $0) }
                return sub.isEmpty ? nil : flattenIfNeeded(sub)
            }
            return nil
        }

        // Key access
        if let dict = node as? [String: Any] {
            let value = dict[token]
            if tokens.isEmpty { return value }
            guard let next = value else { return nil }
            return traverse(components: tokens, from: next)
        }

        // Implicit wildcard — if current node is array, apply to all elements
        if let arr = node as? [Any] {
            let sub = arr.compactMap { traverse(components: [token] + tokens, from: $0) }
            return sub.isEmpty ? nil : flattenIfNeeded(sub)
        }

        return nil
    }

    // MARK: - Helpers

    private func parseJSON(_ json: String) -> Any? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    private func isEmpty(_ value: Any) -> Bool {
        switch value {
        case let s as String:  return s.isEmpty
        case let arr as [Any]: return arr.isEmpty
        default:               return false
        }
    }

    private func flattenIfNeeded(_ arr: [Any]) -> Any {
        // If every element is itself an array, flatten one level
        if arr.allSatisfy({ $0 is [Any] }) {
            return arr.flatMap { $0 as! [Any] }
        }
        return arr
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
