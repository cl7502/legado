import Foundation

/// 规则类型
/// 对标 Android 版 AnalyzeRule.Mode
enum RuleType {
    case defaultRule // 默认 (CSS/XPath)
    case xpath       // @XPath:
    case json        // @Json:
    case regex       // : (正则)
    case js          // <js>
}

/// 规则信息结构体
struct RuleInfo {
    let type: RuleType
    let content: String // 去除前缀后的核心规则内容
}

/// 规则解析器
/// 目标：识别规则类型并提取核心指令
class RuleParser {
    static let shared = RuleParser()
    
    /// 解析单个规则字符串
    func parse(_ rule: String) -> RuleInfo {
        let trimmed = rule.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if trimmed.hasPrefix("<js>") && trimmed.hasSuffix("</js>") {
            let start = trimmed.index(trimmed.startIndex, offsetBy: 4)
            let end = trimmed.index(trimmed.endIndex, offsetBy: -5)
            return RuleInfo(type: .js, content: String(trimmed[start..<end]))
        }
        
        if trimmed.lowercased().hasPrefix("@xpath:") {
            let content = String(trimmed.dropFirst(7))
            return RuleInfo(type: .xpath, content: content)
        }
        
        if trimmed.lowercased().hasPrefix("@json:") {
            let content = String(trimmed.dropFirst(6))
            return RuleInfo(type: .json, content: content)
        }
        
        if trimmed.hasPrefix(":") {
            let content = String(trimmed.dropFirst(1))
            return RuleInfo(type: .regex, content: content)
        }
        
        // 默认规则
        return RuleInfo(type: .defaultRule, content: trimmed)
    }
}
