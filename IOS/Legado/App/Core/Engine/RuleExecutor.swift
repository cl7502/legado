import Foundation

/// 规则执行器 (解析大脑)
/// 目标：调度 JS、HTML、JSON 解析引擎，实现流式解析
class RuleExecutor {
    static let shared = RuleExecutor()
    
    private let jsEngine = LegadoJSEngine.shared
    private let htmlParser = HTMLParser.shared
    private let jsonEngine = JSONPathEngine.shared
    
    /// 执行解析逻辑
    /// - Parameters:
    ///   - rule: 原始规则字符串
    ///   - context: 当前解析上下文 (包含 source, result, variables 等)
    /// - Returns: 解析后的字符串结果
    func execute(_ rule: String, in context: inout AnalyzeContext) -> String? {
        let ruleInfo = RuleParser.shared.parse(rule)
        
        switch ruleInfo.type {
        case .js:
            // 1. 调用 JS 引擎执行脚本
            return jsEngine.evaluateRule(ruleInfo.content, in: &context)
            
        case .json:
            // 2. 调用 JSONPath 解析
            guard let jsonStr = context.result as? String else { return nil }
            let jsonResult = jsonEngine.extract(json: jsonStr, path: ruleInfo.content)
            return "\(jsonResult ?? "")"
            
        case .xpath, .defaultRule:
            // 3. 调用 HTML/CSS 解析
            guard let html = context.result as? String else { return nil }
            // 暂时统一使用 CSS 逻辑，后续通过 JS 引擎增强真正的 XPath
            return htmlParser.text(html, query: ruleInfo.content)
            
        case .regex:
            // 4. 正则提取逻辑
            guard let text = context.result as? String else { return nil }
            return applyRegex(text, pattern: ruleInfo.content)
        }
    }
    
    private func applyRegex(_ text: String, pattern: String) -> String? {
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
            let range = NSRange(location: 0, length: text.utf16.count)
            if let match = regex.firstMatch(in: text, options: [], range: range) {
                if match.numberOfRanges > 1 {
                    return (text as NSString).substring(with: match.range(at: 1))
                }
                return (text as NSString).substring(with: match.range(at: 0))
            }
        } catch {
            print("❌ [Regex Error]: \(error)")
        }
        return nil
    }
}
