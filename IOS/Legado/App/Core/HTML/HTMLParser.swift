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
        // Handle XPath | union (e.g. //div/a | //span/a) — split before Legado && / ||
        if hasTopLevelPipe(xpath) {
            let parts = splitOnTopLevelPipe(xpath)
            let results = parts.compactMap { xpathText(html, xpath: $0.trimmed) }
            return results.isEmpty ? nil : results.joined(separator: "\n")
        }
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

        // Primary: libxml2 full XPath 1.0
        if let result = LibXMLXPath.shared.evaluateToString(xpath, html: html) {
            return result.isEmpty ? nil : result
        }
        // Fallback: CSS conversion (handles edge cases where libxml2 returns nothing)
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
        // Handle XPath | union
        if hasTopLevelPipe(xpath) {
            let parts = splitOnTopLevelPipe(xpath)
            return parts.flatMap { xpathList(html, xpath: $0.trimmed) }
        }
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

        // Primary: libxml2 full XPath 1.0
        let libxmlResults = LibXMLXPath.shared.evaluateToHTMLList(xpath, html: html)
        if !libxmlResults.isEmpty { return libxmlResults }

        // Fallback: CSS conversion
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
        // Android AnalyzeByJSoup.getResultList():
        // Split rule on @ (respecting brackets) → navigate through CSS selectors,
        // extract content/attribute from the LAST segment.
        // e.g. "div.list@div.item@a@href" → select div.list → within: div.item → a → attr(href)
        let parts = splitOnAt(query)
        guard !parts.isEmpty, !parts[0].isEmpty else { return [] }

        // URL path detection: if the single-part rule looks like a URL/path with a query
        // string, treat it as a literal URL value rather than a CSS selector.
        // This handles URL templates like "/novel/123?isSearch=1" that expand to book URLs.
        if parts.count == 1 {
            let q = parts[0]
            if (q.hasPrefix("/") || q.hasPrefix("http")) && q.contains("?") {
                return [q]
            }
        }

        do {
            let doc = try SwiftSoup.parse(html)

            if parts.count == 1 {
                let elements = try doc.select(parts[0].legadoCSS)
                return elements.array().compactMap { try? $0.text() }.filter { !$0.isEmpty }
            }

            // Navigate through all segments except the last
            var elList: [Element] = (try? doc.select(parts[0].legadoCSS).array()) ?? []
            for i in 1..<(parts.count - 1) {
                var next: [Element] = []
                for el in elList {
                    let sub = (try? el.select(parts[i].legadoCSS)) ?? Elements()
                    next.append(contentsOf: sub.array())
                }
                elList = next
            }

            // Final segment: attribute / content keyword
            let lastRule = parts.last!
            return elList.compactMap { el -> String? in
                let v = try? extractAttr(el, attr: lastRule.isEmpty ? nil : lastRule)
                return v?.isEmpty == false ? v : nil
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
        // Same multi-step @ navigation as getStringListSingle, but returns outerHTML
        // of the final elements (for downstream field-rule parsing).
        // If the last segment is an attribute keyword, extracts attribute strings instead.
        let parts = splitOnAt(query)
        guard !parts.isEmpty, !parts[0].isEmpty else { return [] }

        do {
            let doc = try SwiftSoup.parse(html)

            if parts.count == 1 {
                let elements = try doc.select(parts[0].legadoCSS)
                return elements.array().compactMap { try? $0.outerHtml() }
            }

            // Determine if the last part is attribute extraction or further CSS navigation
            let lastPart = parts.last!
            let extractsAttr = isAttributeKeyword(lastPart)
            let navParts = extractsAttr ? Array(parts.dropLast()) : parts

            var elList: [Element] = (try? doc.select(navParts[0].legadoCSS).array()) ?? []
            for i in 1..<navParts.count {
                var next: [Element] = []
                for el in elList {
                    let sub = (try? el.select(navParts[i].legadoCSS)) ?? Elements()
                    next.append(contentsOf: sub.array())
                }
                elList = next
            }

            if extractsAttr {
                return elList.compactMap { el -> String? in
                    let v = try? extractAttr(el, attr: lastPart)
                    return v?.isEmpty == false ? v : nil
                }
            }
            return elList.compactMap { try? $0.outerHtml() }
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
        path = replaceAllCaptures(path,
            pattern: #"\[starts-with\(\s*@([\w-]+)\s*,\s*['"]([^'"]+)['"]\)\]"#) { "[\($0[0])^='\($0[1])']" }

        // [@class='x y'] → .x.y  (exact class)
        path = replacePattern(path,
            pattern: #"\[@class\s*=\s*['"]([^'"]+)['"]\]"#) { cls in
            "." + cls.components(separatedBy: " ").joined(separator: ".")
        }
        // [@id='x'] → #x
        path = replacePattern(path,
            pattern: #"\[@id\s*=\s*['"]([^'"]+)['"]\]"#) { "#\($0)" }

        // [@attr='val'] → [attr='val']  (any attribute equality)
        path = replaceAllCaptures(path,
            pattern: #"\[@([\w-]+)\s*=\s*['"]([^'"]*)['"]\]"#) { "[\($0[0])='\($0[1])']" }
        // [@attr] → [attr]  (attribute existence check)
        path = path.replacingOccurrences(of: "[@", with: "[")

        // Positional predicates
        path = path.replacingOccurrences(of: "[last()]", with: ":last-child")
        // [n] → :nth-child(n) for any n (1-based, same as CSS)
        path = replaceAllCaptures(path, pattern: #"\[(\d+)\]"#) { ":nth-child(\($0[0]))" }
        // position() predicates — approximate (too complex for full CSS parity, drop)
        path = replacePattern(path, pattern: #"\[position\(\)[^\]]*\]"#) { _ in "" }

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

    /// Returns true if the string contains a `|` that is NOT inside `[]` (XPath union operator).
    private func hasTopLevelPipe(_ s: String) -> Bool {
        var depth = 0
        for ch in s {
            if ch == "[" { depth += 1 }
            else if ch == "]" { depth = max(0, depth - 1) }
            else if ch == "|" && depth == 0 { return true }
        }
        return false
    }

    /// Splits on top-level `|` (XPath union), ignoring `|` inside `[]`.
    private func splitOnTopLevelPipe(_ s: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var depth = 0
        for ch in s {
            if ch == "[" { depth += 1; current.append(ch) }
            else if ch == "]" { depth = max(0, depth - 1); current.append(ch) }
            else if ch == "|" && depth == 0 {
                parts.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(ch)
            }
        }
        if !current.trimmingCharacters(in: .whitespaces).isEmpty {
            parts.append(current.trimmingCharacters(in: .whitespaces))
        }
        return parts
    }

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

    /// Like replacePattern but passes ALL captured groups to the closure.
    private func replaceAllCaptures(_ input: String, pattern: String,
                                    replacement: ([String]) -> String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return input
        }
        var result = input
        let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))
        for match in matches.reversed() {
            guard let range = Range(match.range, in: result) else { continue }
            var groups: [String] = []
            for i in 1..<match.numberOfRanges {
                if let r = Range(match.range(at: i), in: result) {
                    groups.append(String(result[r]))
                } else {
                    groups.append("")
                }
            }
            result.replaceSubrange(range, with: replacement(groups))
        }
        return result
    }

    /// Split on `@` that are NOT inside square brackets `[...]`.
    /// Mirrors Android RuleAnalyzer.splitRule("@") which skips @ inside predicates.
    /// e.g. "div[class*='x']@a@href" → ["div[class*='x']", "a", "href"]
    private func splitOnAt(_ query: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var depth = 0
        for ch in query {
            switch ch {
            case "[": depth += 1; current.append(ch)
            case "]": depth = max(0, depth - 1); current.append(ch)
            case "@" where depth == 0:
                let p = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !p.isEmpty { parts.append(p) }
                current = ""
            default:
                current.append(ch)
            }
        }
        let last = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !last.isEmpty { parts.append(last) }
        return parts
    }

    /// Returns true when the string should be interpreted as an extraction directive
    /// (attribute name or content keyword) rather than a CSS selector.
    /// Mirrors Android AnalyzeByJSoup.getResultLast() known-keyword check.
    private func isAttributeKeyword(_ s: String) -> Bool {
        let knownKeywords: Set<String> = [
            "text", "html", "outerhtml", "textnodes", "all", "raw"
        ]
        if knownKeywords.contains(s.lowercased()) { return true }

        let knownAttrs: Set<String> = [
            "href", "src", "_src", "alt", "title", "class", "id", "name",
            "value", "type", "style", "content", "rel", "action",
            "placeholder", "srcset", "colspan", "rowspan", "target",
            "width", "height", "lang", "tabindex", "aria-label",
        ]
        if knownAttrs.contains(s.lowercased()) { return true }

        // data-* or _-prefixed custom attributes
        if s.hasPrefix("data-") || s.hasPrefix("_") { return true }

        // Anything else (including HTML tag names like li/div/h2) → CSS selector
        return false
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
            "_src",   // Legado lazy-image alias → tries data-src / data-original / src
        ]
        if known.contains(s.lowercased()) { return true }
        if s.hasPrefix("data-") && s.count > 5 { return true }
        // Allow leading underscore (e.g. _src) in addition to ASCII letters
        let cssSpecial = CharacterSet(charactersIn: ".#[]>+~:() ,'\"/\\")
        guard let first = s.unicodeScalars.first else { return false }
        let validStart = CharacterSet.letters.union(CharacterSet(charactersIn: "_"))
        return validStart.contains(first) &&
               s.unicodeScalars.allSatisfy { !cssSpecial.contains($0) }
    }

    private func extractAttr(_ element: Element, attr: String?) throws -> String? {
        guard let attr = attr else { return try element.text() }
        switch attr.lowercased() {
        case "text":      return try element.text()
        case "textnodes": // Android: direct text nodes only (no children)
            let texts = element.textNodes().map { $0.text().trimmingCharacters(in: .whitespaces) }
                                           .filter { !$0.isEmpty }
            return texts.isEmpty ? nil : texts.joined(separator: "\n")
        case "html":      return try element.html()
        case "outerhtml": return try element.outerHtml()
        case "raw":       return try element.outerHtml()
        case "all":       return try element.text()
        case "_src":
            // Legado alias for lazy-loaded image src — tries common lazy-load attribute names
            for name in ["data-src", "data-original", "data-lazy-src", "data-lazyload",
                         "data-echo", "_src", "src"] {
                let v = (try? element.attr(name)) ?? ""
                if !v.isEmpty { return v }
            }
            return nil
        default:
            let v = try element.attr(attr)
            return v.isEmpty ? nil : v
        }
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Android Legado CSS shorthand: "class.xxx" means ".xxx" (elements with CSS class xxx).
    /// Standard CSS has no `class` tag, so convert before passing to SwiftSoup.
    var legadoCSS: String {
        guard contains("class.") else { return self }
        return replacingOccurrences(of: #"\bclass\."#, with: ".", options: .regularExpression)
    }
}
