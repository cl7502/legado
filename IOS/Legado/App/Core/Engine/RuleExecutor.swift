import Foundation

/// 规则执行器 (列表支持版)
class RuleExecutor {
    static let shared = RuleExecutor()
    
    private let jsEngine = LegadoJSEngine.shared
    private let htmlParser = HTMLParser.shared
    private let jsonEngine = JSONPathEngine.shared
    
    /// 执行解析逻辑（单条结果）
    func execute(_ rule: String, in context: inout AnalyzeContext) -> String? {
        let ruleInfo = RuleParser.shared.parse(rule)
        guard let input = context.result as? String else { return nil }
        
        switch ruleInfo.type {
        case .js:
            return jsEngine.evaluateRule(ruleInfo.content, in: &context)
        case .json:
            let jsonResult = jsonEngine.extract(json: input, path: ruleInfo.content)
            return "\(jsonResult ?? "")"
        case .xpath, .defaultRule:
            return htmlParser.text(input, query: ruleInfo.content)
        case .regex:
            return applyRegex(input, pattern: ruleInfo.content)
        }
    }
    
    /// 执行解析逻辑（列表结果）
    /// 目标：支持搜索列表和目录列表的提取
    func executeList(_ rule: String, in context: inout AnalyzeContext) -> [String] {
        let ruleInfo = RuleParser.shared.parse(rule)
        guard let input = context.result as? String else { return [] }
        
        switch ruleInfo.type {
        case .js:
            // TODO: JS 引擎需要支持返回数组
            let result = jsEngine.evaluateRule(ruleInfo.content, in: &context)
            return result?.components(separatedBy: ",") ?? []
        case .json:
            let jsonResult = jsonEngine.extract(json: input, path: ruleInfo.content)
            if let array = jsonResult as? [Any] {
                return array.map { "\($0)" }
            }
            return []
        case .xpath, .defaultRule:
            return htmlParser.cssList(input, query: ruleInfo.content)
        case .regex:
            // 正则暂不支持直接返回列表，通常在 JS 中处理
            return []
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
