import Foundation
import SwiftSoup

/// HTML 解析器 (增强版)
class HTMLParser {
    static let shared = HTMLParser()
    
    /// 执行 CSS 选择器查询
    func css(_ html: String, query: String) -> [String] {
        do {
            let doc = try SwiftSoup.parse(html)
            let elements = try doc.select(query)
            return elements.array().compactMap { try? $0.outerHtml() }
        } catch {
            print("❌ [HTML Error]: CSS select failed: \(query)")
            return []
        }
    }
    
    /// 获取元素文本
    func text(_ html: String, query: String) -> String? {
        do {
            let doc = try SwiftSoup.parse(html)
            let element = try doc.selectFirst(query)
            return try element?.text()
        } catch {
            return nil
        }
    }
    
    /// 获取带 HTML 标签的内容 (对标 Android 的 innerHtml)
    func html(_ html: String, query: String) -> String? {
        do {
            let doc = try SwiftSoup.parse(html)
            let element = try doc.selectFirst(query)
            return try element?.html()
        } catch {
            return nil
        }
    }
    
    /// 移除指定 CSS 选择器的节点 (用于净化广告)
    /// - Parameters:
    ///   - html: 原始 HTML
    ///   - selectors: 要删除的 CSS 选择器列表
    /// - Returns: 处理后的 HTML
    func removeNodes(_ html: String, selectors: [String]) -> String {
        do {
            let doc = try SwiftSoup.parse(html)
            for selector in selectors {
                let elements = try doc.select(selector)
                try elements.remove()
            }
            return try doc.html()
        } catch {
            print("❌ [HTML Error]: Remove nodes failed")
            return html
        }
    }
}
