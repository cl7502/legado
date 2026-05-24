import Foundation
import SwiftSoup

/// HTML 解析器 — 支持 CSS `selector@attr` 属性提取语法
class HTMLParser {
    static let shared = HTMLParser()

    // MARK: - 公开接口

    /// 单条 CSS 查询，支持 "selector@attr" 语法
    func text(_ html: String, query: String) -> String? {
        let (selector, attr) = splitSelectorAttr(query)
        do {
            let doc = try SwiftSoup.parse(html)
            guard let element = try doc.selectFirst(selector) else { return nil }
            return try extractAttr(element, attr: attr)
        } catch {
            return nil
        }
    }

    /// XPath 单条查询
    func xpathText(_ html: String, xpath: String) -> String? {
        do {
            let doc = try SwiftSoup.parse(html)
            let elements = try doc.selectXpath(xpath)
            return elements.first()?.ownText() ?? (try? elements.first()?.text())
        } catch {
            return nil
        }
    }

    /// CSS 列表查询 — 返回各元素 outerHTML（供后续子规则处理）
    /// 若 query 带 @attr 后缀，则直接返回属性值列表
    func cssList(_ html: String, query: String) -> [String] {
        let (selector, attr) = splitSelectorAttr(query)
        do {
            let doc = try SwiftSoup.parse(html)
            let elements = try doc.select(selector)
            if let attr = attr {
                // 有属性后缀 → 直接提取属性值
                return elements.array().compactMap { try? extractAttr($0, attr: attr) }
            } else {
                // 无属性后缀 → 返回 outerHTML 供子规则继续处理
                return elements.array().compactMap { try? $0.outerHtml() }
            }
        } catch {
            return []
        }
    }

    /// XPath 列表查询 — 返回各元素 outerHTML
    func xpathList(_ html: String, xpath: String) -> [String] {
        do {
            let doc = try SwiftSoup.parse(html)
            let elements = try doc.selectXpath(xpath)
            return elements.compactMap { try? $0.outerHtml() }
        } catch {
            return []
        }
    }

    func html(_ html: String, query: String) -> String? {
        let (selector, _) = splitSelectorAttr(query)
        do {
            let doc = try SwiftSoup.parse(html)
            return try doc.selectFirst(selector)?.html()
        } catch {
            return nil
        }
    }

    func removeNodes(_ html: String, selectors: [String]) -> String {
        do {
            let doc = try SwiftSoup.parse(html)
            for selector in selectors {
                try doc.select(selector).remove()
            }
            return try doc.html()
        } catch {
            return html
        }
    }

    // MARK: - Private helpers

    /// 将 "div.title@href" 拆分为 ("div.title", "href")
    /// 若 @ 后不像属性名则返回 (query, nil)
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
            "text", "html", "outerHtml", "href", "src", "alt", "title",
            "class", "id", "name", "value", "type", "style", "content",
            "rel", "action", "placeholder", "srcset", "data", "outerhtml"
        ]
        if known.contains(s) { return true }
        if s.hasPrefix("data-") && s.count > 5 { return true }
        // 纯字母数字连字符（没有 CSS 特殊字符）
        let cssSpecial = CharacterSet(charactersIn: ".#[]>+~:() ,")
        return s.unicodeScalars.allSatisfy { !cssSpecial.contains($0) } &&
               s.unicodeScalars.first.map { CharacterSet.letters.contains($0) } == true
    }

    private func extractAttr(_ element: Element, attr: String?) throws -> String? {
        guard let attr = attr else { return try element.text() }
        switch attr.lowercased() {
        case "text":       return try element.text()
        case "html":       return try element.html()
        case "outerhtml":  return try element.outerHtml()
        default:
            let v = try element.attr(attr)
            return v.isEmpty ? nil : v
        }
    }
}
