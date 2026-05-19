import Foundation

/// 规则类型
enum RuleType {
    case defaultRule // 默认 (CSS)
    case xpath       // @XPath:
    case json        // @Json:
    case regex       // : (正则)
    case js          // <js>
}

/// 规则片段
struct RuleSegment {
    let type: RuleType
    let content: String
}

/// 增强型规则解析器
/// 目标：支持链式解析 (rule1 @ rule2 @ rule3)
class RuleParser {
    static let shared = RuleParser()
    
    /// 将复合规则解析为片段数组
    func parseChain(_ rule: String) -> [RuleSegment] {
        let trimmed = rule.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        
        // 1. 处理特殊情况：整个规则是 JS
        if (trimmed.hasPrefix("<js>") && trimmed.hasSuffix("</js>")) || trimmed.hasPrefix("javascript:") {
            return [parseSingle(trimmed)]
        }
        
        // 2. 按 @ 符号分割，但要忽略 JS 内部或正则内部的 @
        // 简单处理：目前先支持标准的 @ 分割
        let segments = trimmed.components(separatedBy: "@")
        return segments.map { parseSingle($0) }
    }
    
    /// 解析单个规则片段
    private func parseSingle(_ rule: String) -> RuleSegment {
        let trimmed = rule.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if (trimmed.hasPrefix("<js>") && trimmed.hasSuffix("</js>")) || trimmed.hasPrefix("javascript:") {
            let content = trimmed.hasPrefix("javascript:") ? String(trimmed.dropFirst(11)) : String(trimmed.dropFirst(4).dropLast(5))
            return RuleSegment(type: .js, content: content)
        }
        
        if trimmed.lowercased().hasPrefix("xpath:") || trimmed.lowercased().hasPrefix("@xpath:") {
            let content = trimmed.hasPrefix("@") ? String(trimmed.dropFirst(7)) : String(trimmed.dropFirst(6))
            return RuleSegment(type: .xpath, content: content)
        }
        
        if trimmed.lowercased().hasPrefix("json:") || trimmed.lowercased().hasPrefix("@json:") {
            let content = trimmed.hasPrefix("@") ? String(trimmed.dropFirst(6)) : String(trimmed.dropFirst(5))
            return RuleSegment(type: .json, content: content)
        }
        
        if trimmed.hasPrefix(":") {
            return RuleSegment(type: .regex, content: String(trimmed.dropFirst(1)))
        }
        
        return RuleSegment(type: .defaultRule, content: trimmed)
    }
}
