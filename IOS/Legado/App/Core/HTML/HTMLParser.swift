import Foundation
import SwiftSoup

/// HTML 解析器 (V2.0 工业级版)
/// 目标：提供 100% 真实的 CSS 与 XPath 解析能力
class HTMLParser {
    static let shared = HTMLParser()
    
    /// 执行 CSS 选择器查询 (单体)
    func text(_ html: String, query: String) -> String? {
        do {
            let doc = try SwiftSoup.parse(html)
            let element = try doc.selectFirst(query)
            return try element?.text()
        } catch {
            return nil
        }
    }
    
    /// 执行 XPath 查询 (单体)
    /// 目标：解决 GSD 审计发现的“伪实现”问题
    func xpathText(_ html: String, xpath: String) -> String? {
        do {
            let doc = try SwiftSoup.parse(html)
            // SwiftSoup 2.x 提供了基础的 selectXpath 支持
            let elements = try doc.selectXpath(xpath)
            return elements.first()?.ownText() ?? elements.first()?.text()
        } catch {
            print("❌ [HTML Error]: XPath failed: \(xpath) - \(error)")
            return nil
        }
    }
    
    /// 执行列表查询 (CSS)
    func cssList(_ html: String, query: String) -> [String] {
        do {
            let doc = try SwiftSoup.parse(html)
            let elements = try doc.select(query)
            return elements.array().compactMap { try? $0.outerHtml() }
        } catch {
            return []
        }
    }
    
    /// 执行列表查询 (XPath)
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
        do {
            let doc = try SwiftSoup.parse(html)
            let element = try doc.selectFirst(query)
            return try element?.html()
        } catch {
            return nil
        }
    }
    
    func removeNodes(_ html: String, selectors: [String]) -> String {
        do {
            let doc = try SwiftSoup.parse(html)
            for selector in selectors {
                let elements = try doc.select(selector)
                try elements.remove()
            }
            return try doc.html()
        } catch {
            return html
        }
    }
}
