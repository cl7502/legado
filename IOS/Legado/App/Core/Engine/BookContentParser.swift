import Foundation

/// 正文解析调度器
/// 目标：协调 获取 -> CSS 净化 -> 正则净化 -> 格式化 的全流程
class BookContentParser {
    static let shared = BookContentParser()
    
    private let ruleExecutor = RuleExecutor.shared
    private let htmlParser = HTMLParser.shared
    private let contentProcessor = ContentProcessor.shared
    
    /// 解析并净化章节内容
    /// - Parameters:
    ///   - rawHtml: 网页源码
    ///   - rule: 书源的正文规则
    ///   - context: 解析上下文
    ///   - replaceRules: 净化规则列表
    /// - Returns: 最终可阅读的正文
    func parseContent(
        _ rawHtml: String,
        rule: String,
        context: inout AnalyzeContext,
        replaceRules: [ReplaceRule] = []
    ) -> String {
        // 1. 设置当前结果
        context.result = rawHtml
        
        // 2. 提取正文 (初步提取，通常返回 HTML 片段)
        // 注意：Legado 的正文规则可能包含需要删除的选择器，例如 "id.content@html"
        guard let extractedHtml = ruleExecutor.execute(rule, in: &context) else {
            return "正文解析失败"
        }
        
        // 3. CSS 级别净化 (根据书源定义的待删除规则，此逻辑常在规则字符串中以 - 开头)
        // 这里我们先实现基础的全局净化
        var cleanedHtml = extractedHtml
        
        // 4. 将 HTML 转换为纯文本，并保留换行
        // 模拟 Android 的逻辑，将 <p>, <br> 转换为换行符
        let textContent = htmlToPlainText(cleanedHtml)
        
        // 5. 正则净化与格式化
        return contentProcessor.process(textContent, with: replaceRules)
    }
    
    /// 简易 HTML 转纯文本 (处理换行)
    private func htmlToPlainText(_ html: String) -> String {
        // 简单粗暴但有效的方法：处理 <br> 和 <p>
        var text = html.replacingOccurrences(of: "<br/?>", with: "\n", options: .regularExpression, range: nil)
        text = text.replacingOccurrences(of: "</p>", with: "\n", options: .caseInsensitive, range: nil)
        text = text.replacingOccurrences(of: "<p>", with: "", options: .caseInsensitive, range: nil)
        
        // 使用 SwiftSoup 去除剩余所有标签
        do {
            return try SwiftSoup.clean(text, .none()) ?? ""
        } catch {
            return text
        }
    }
}
