import Foundation
import SwiftSoup

/// HTML parser — mirrors Android AnalyzeByJSoup + AnalyzeByXPath.
/// Supports:
///   • CSS selector with @attr extraction  (div.title@href)
///   • && (combine all), || (first match), %% (round-robin) combinators
///   • XPath-to-CSS conversion for common patterns (full XPath needs libxml2)
class HTMLParser {
    static let shared = HTMLParser()

    // MARK: - CSS single-string query

    func text(_ html: String, query: String) -> String? {
        let list = getStringList(html, query: query)
        if list.isEmpty { return nil }
        return list.count == 1 ? list[0] : list.joined(separator: "\n")
    }

    func cssList(_ html: String, query: String) -> [String] {
        return getElementsList(html, query: query)
    }

    // MARK: - XPath single-string query

    func xpathText(_ html: String, xpath: String) -> String? {
        // Handle && / ||
        if xpath.contains("&&") {
            let parts = xpath.components(separatedBy: "&&")
            let results = parts.compactMap { xpathText(html, xpath: $0.trimmed) }
            return results.isEmpty ? nil : results.joined(separator: "\n")
        }
        if xpath.contains("||") {
            let parts = xpath.components(separatedBy: "||")
            return parts.compactMap { xpathText(html, xpath: $0.trimmed) }.first
        }

        let (css, attrName) = xpathToCSS(xpath)
        guard !css.isEmpty else { return nil }
        do {
            let doc = try SwiftSoup.parse(html)
            guard let element = try doc.select(css).first() else { return nil }
            if let attr = attrName {
                let v = try element.attr(attr)
                return v.isEmpty ? nil : v
            }
            return try element.text()
        } catch { return nil }
    }

    /// XPath list query — returns outerHTML of each matched element.
    func xpathList(_ html: String, xpath: String) -> [String] {
        // Handle && / ||
        if xpath.contains("&&") {
            let parts = xpath.components(separatedBy: "&&")
            return parts.flatMap { xpathList(html, xpath: $0.trimmed) }
        }
        if xpath.contains("||") {
            let parts = xpath.components(separatedBy: "||")
            for part in parts {
                let r = xpathList(html, xpath: part.trimmed)
                if !r.isEmpty { return r }
            }
            return []
        }

        let (css, _) = xpathToCSS(xpath)
        guard !css.isEmpty else { return [] }
        do {
            let doc = try SwiftSoup.parse(html)
            let elements = try doc.select(css)
            return elements.array().compactMap { try? $0.outerHtml() }
        } catch { return [] }
    }

    func html(_ html: String, query: String) -> String? {
        let (selector, _) = splitSelectorAttr(query)
        do {
            let doc = try SwiftSoup.parse(html)
            return try doc.select(selector).first()?.html()
        } catch { return nil }
    }

    func removeNodes(_ html: String, selectors: [String]) -> String {
        do {
            let doc = try SwiftSoup.parse(html)
            for selector in selectors { try doc.select(selector).remove() }
            return try doc.html()
        } catch { return html }
    }

    // MARK: - Multi-rule combinators (&&, ||, %%)

    /// Get list of strings, respecting &&/||/%% combinators.
    private func getStringList(_ html: String, query: String) -> [String] {
        // %% combinator — round-robin merge (less common, handle first)
        if query.contains("%%") {
            let parts = query.components(separatedBy: "%%")
            let lists = parts.map { getStringList(html, query: $0.trimmed) }
            guard !lists.isEmpty else { return [] }
            let maxLen = lists.map { $0.count }.max() ?? 0
            var result: [String] = []
            for i in 0..<maxLen {
                for list in lists where i < list.count { result.append(list[i]) }
            }
            return result
        }

        // || combinator — first non-empty wins
        if query.contains("||") {
            let parts = query.components(separatedBy: "||")
            for part in parts {
                let r = getStringListSingle(html, query: part.trimmed)
                if !r.isEmpty { return r }
            }
            return []
        }

        // && combinator — merge all results in order
        if query.contains("&&") {
            let parts = query.components(separatedBy: "&&")
            return parts.flatMap { getStringListSingle(html, query: $0.trimmed) }
        }

        return getStringListSingle(html, query: query)
    }

    private func getStringListSingle(_ html: String, query: String) -> [String] {
        let (selector, attr) = splitSelectorAttr(query)
        guard !selector.isEmpty else { return [] }
        do {
            let doc = try SwiftSoup.parse(html)
            let elements = try doc.select(selector)
            if elements.isEmpty() { return [] }
            return elements.array().compactMap { el -> String? in
                try? extractAttr(el, attr: attr)
            }
        } catch { return [] }
    }

    /// Get list of elements as outerHTML strings, respecting combinators.
    private func getElementsList(_ html: String, query: String) -> [String] {
        if query.contains("%%") {
            let parts = query.components(separatedBy: "%%")
            let lists = parts.map { getElementsList(html, query: $0.trimmed) }
            guard !lists.isEmpty else { return [] }
            let maxLen = lists.map { $0.count }.max() ?? 0
            var result: [String] = []
            for i in 0..<maxLen {
                for list in lists where i < list.count { result.append(list[i]) }
            }
            return result
        }
        if query.contains("||") {
            let parts = query.components(separatedBy: "||")
            for part in parts {
                let r = getElementsListSingle(html, query: part.trimmed)
                if !r.isEmpty { return r }
            }
            return []
        }
        if query.contains("&&") {
            let parts = query.components(separatedBy: "&&")
            return parts.flatMap { getElementsListSingle(html, query: $0.trimmed) }
        }
        return getElementsListSingle(html, query: query)
    }

    private func getElementsListSingle(_ html: String, query: String) -> [String] {
        let (selector, attr) = splitSelectorAttr(query)
        guard !selector.isEmpty else { return [] }
        do {
            let doc = try SwiftSoup.parse(html)
            let elements = try doc.select(selector)
            if let attr = attr {
                // attr extraction requested → return string values
                return elements.array().compactMap { try? extractAttr($0, attr: attr) }
            }
            // No attr → return outerHTML of each element for downstream parsing
            return elements.array().compactMap { try? $0.outerHtml() }
        } catch { return [] }
    }

    // MARK: - XPath → CSS conversion

    /// Returns (cssSelector, extractAttrName?)
    /// Covers the XPath patterns most commonly found in Legado book sources.
    private func xpathToCSS(_ xpath: String) -> (String, String?) {
        var path = xpath.trimmingCharacters(in: .whitespacesAndNewlines)
        var extractAttr: String? = nil

        // Tail  /@attr  →  attribute extraction
        if let atRange = path.range(of: "/@", options: .backwards) {
            extractAttr = String(path[atRange.upperBound...])
            path = String(path[..<atRange.lowerBound])
        }

        // Remove text() / node() references
        path = path.replacingOccurrences(of: "/text()", with: "")
        path = path.replacingOccurrences(of: "text()", with: "")
        path = path.replacingOccurrences(of: "/node()", with: "")

        // contains(@class,'x') → [class*='x']
        path = replacePattern(path,
            pattern: #"\[contains\(\s*@class\s*,\s*['"](.+?)['"]\)\]"#) {
            "[class*='\($0)']"
        }
        // contains(@id,'x') → [id*='x']
        path = replacePattern(path,
            pattern: #"\[contains\(\s*@id\s*,\s*['"](.+?)['"]\)\]"#) {
            "[id*='\($0)']"
        }
        // starts-with(@attr,'x') → [attr^='x']
        path = replacePattern(path,
            pattern: #"\[starts-with\(\s*@(\w+)\s*,\s*['"](.+?)['"]\)\]"#) { _ in "" }
        // (simplified — can't express in CSS easily, drop predicate)

        // [@class='x y'] → .x.y  (exact class)
        path = replacePattern(path,
            pattern: #"\[@class\s*=\s*['"]([^'"]+)['"]\]"#) { cls in
            "." + cls.components(separatedBy: " ").joined(separator: ".")
        }
        // [@id='x'] → #x
        path = replacePattern(path,
            pattern: #"\[@id\s*=\s*['"]([^'"]+)['"]\]"#) { "#\($0)" }

        // [@attr='val'] → [attr='val']  (any other attribute)
        path = replacePattern(path,
            pattern: #"\[@(\w[\w-]*)\s*=\s*['"]([^'"]*)['"]\]"#) { _ in "" }
        // (Generic attribute equality — keep the bracket without @ for CSS)
        path = path.replacingOccurrences(of: "[@", with: "[")

        // Positional predicates
        path = path.replacingOccurrences(of: "[1]", with: ":first-child")
        path = path.replacingOccurrences(of: "[last()]", with: ":last-child")
        // [n] (n>1) — drop (CSS nth-child is complex, dropping is safer than wrong result)
        path = replacePattern(path, pattern: #"\[\d+\]"#) { _ in "" }

        // Strip leading // and /
        if path.hasPrefix("//") { path = String(path.dropFirst(2)) }
        else if path.hasPrefix("/") { path = String(path.dropFirst()) }

        // * → universal selector  (e.g. //*[@id='x'] → * + id rewrite above → #x)
        // Replace  //  (descendant) with space,  /  (child) with  >
        path = path.replacingOccurrences(of: "//", with: " ")
        path = path.replacingOccurrences(of: "/", with: " > ")

        let css = path.trimmingCharacters(in: .whitespacesAndNewlines)
        return (css, extractAttr)
    }

    // MARK: - Private helpers

    private func replacePattern(_ input: String, pattern: String,
                                 replacement: (String) -> String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return input
        }
        var result = input
        let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))
        for match in matches.reversed() {
            guard let range = Range(match.range, in: result) else { continue }
            let captured: String
            if match.numberOfRanges > 1, let r1 = Range(match.range(at: 1), in: result) {
                captured = String(result[r1])
            } else {
                captured = String(result[range])
            }
            result.replaceSubrange(range, with: replacement(captured))
        }
        return result
    }

    /// Split  "selector@attr"  into  (selector, attr?).
    /// Only splits on the LAST @, and only if what follows looks like an attribute name.
    private func splitSelectorAttr(_ query: String) -> (String, String?) {
        guard let atIdx = query.lastIndex(of: "@") else { return (query, nil) }
        let selector = String(query[..<atIdx])
        let attr     = String(query[query.index(after: atIdx)...])
        guard !selector.isEmpty, looksLikeAttr(attr) else { return (query, nil) }
        return (selector, attr)
    }

    private func looksLikeAttr(_ s: String) -> Bool {
        if s.isEmpty { return false }
        let known: Set<String> = [
            "text", "html", "outerHtml", "outerhtml", "href", "src", "alt",
            "title", "class", "id", "name", "value", "type", "style", "content",
            "rel", "action", "placeholder", "srcset", "data", "src",
        ]
        if known.contains(s.lowercased()) { return true }
        if s.hasPrefix("data-") && s.count > 5 { return true }
        // Pure alphanumeric/hyphen with no CSS special characters
        let cssSpecial = CharacterSet(charactersIn: ".#[]>+~:() ,'\"/\\")
        return s.unicodeScalars.allSatisfy { !cssSpecial.contains($0) } &&
               s.unicodeScalars.first.map { CharacterSet.letters.contains($0) } == true
    }

    private func extractAttr(_ element: Element, attr: String?) throws -> String? {
        guard let attr = attr else { return try element.text() }
        switch attr.lowercased() {
        case "text":      return try element.text()
        case "html":      return try element.html()
        case "outerhtml": return try element.outerHtml()
        default:
            let v = try element.attr(attr)
            return v.isEmpty ? nil : v
        }
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
