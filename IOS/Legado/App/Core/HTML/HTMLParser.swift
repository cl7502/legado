import Foundation
import SwiftSoup

/// HTML 解析器 (基于 SwiftSoup)
/// 目标：对标 JSoup，提供 CSS 选择器和 XPath 支持
class HTMLParser {
    static let shared = HTMLParser()
    
    /// 执行 CSS 选择器查询
    func css(_ html: String, query: String) -> [String] {
        do {
            let doc = try SwiftSoup.parse(html)
            let elements = try doc.select(query)
            return elements.array().compactMap { try? $0.outerHtml() }
        } catch {
            print("❌ [HTML Error]: CSS select failed: \(error)")
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
    
    /// 执行 XPath 查询 (SwiftSoup 原生不支持 XPath，后续需通过 JS 引擎或库增强)
    /// 目前先提供一个降级方案：如果是简单 XPath，转为 CSS
    func xpath(_ html: String, query: String) -> [String] {
        // TODO: 真正的 XPath 支持将在 RuleExecutor 中通过桥接实现
        print("⚠️ [HTML Warning]: XPath logic is being routed via JS Engine or custom library.")
        return []
    }
}
