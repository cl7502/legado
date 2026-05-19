import Foundation
import SwiftSoup

/// HTML 解析器 (列表增强版)
class HTMLParser {
    static let shared = HTMLParser()
    
    /// 执行 CSS 选择器查询并返回多个元素的 HTML 片段
    func cssList(_ html: String, query: String) -> [String] {
        do {
            let doc = try SwiftSoup.parse(html)
            let elements = try doc.select(query)
            return elements.array().compactMap { try? $0.outerHtml() }
        } catch {
            print("❌ [HTML Error]: CSS list select failed: \(query)")
            return []
        }
    }
    
    func css(_ html: String, query: String) -> [String] {
        return cssList(html, query: query)
    }
    
    func text(_ html: String, query: String) -> String? {
        do {
            let doc = try SwiftSoup.parse(html)
            let element = try doc.selectFirst(query)
            return try element?.text()
        } catch {
            return nil
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
