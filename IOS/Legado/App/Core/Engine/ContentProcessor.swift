import Foundation

/// 内容净化处理器
/// 目标：根据 ReplaceRule 对正文进行清洗，去除广告和乱码
class ContentProcessor {
    static let shared = ContentProcessor()
    
    /// 执行净化逻辑
    /// - Parameters:
    ///   - content: 原始正文内容
    ///   - rules: 适用的净化规则列表
    /// - Returns: 清洗后的正文
    func process(_ content: String, with rules: [ReplaceRule]) -> String {
        var processedContent = content
        
        // 1. 过滤掉未启用的规则
        let enabledRules = rules.filter { $0.isEnabled }.sorted { $0.order < $1.order }
        
        // 2. 依次应用规则
        for rule in enabledRules {
            guard let pattern = rule.pattern, !pattern.isEmpty else { continue }
            
            if rule.isRegex {
                processedContent = applyRegexReplacement(
                    content: processedContent,
                    pattern: pattern,
                    replacement: rule.replacement
                )
            } else {
                processedContent = processedContent.replacingOccurrences(
                    of: pattern,
                    with: rule.replacement
                )
            }
        }
        
        // 3. 基础格式化 (对标 Android 的默认净化)
        processedContent = basicFormat(processedContent)
        
        return processedContent
    }
    
    /// 正则替换实现
    private func applyRegexReplacement(content: String, pattern: String, replacement: String) -> String {
        do {
            let regex = try NSRegularExpression(
                pattern: pattern,
                options: [.caseInsensitive, .dotMatchesLineSeparators]
            )
            let range = NSRange(location: 0, length: content.utf16.count)
            return regex.stringByReplacingMatches(
                in: content,
                options: [],
                range: range,
                withTemplate: replacement
            )
        } catch {
            print("❌ [Purify Error]: Regex pattern invalid: \(pattern)")
            return content
        }
    }
    
    /// 基础格式化：去除多余空行，处理首行缩进
    private func basicFormat(_ content: String) -> String {
        var lines = content.components(separatedBy: .newlines)
        lines = lines.map { $0.trimmingCharacters(in: .whitespaces) }
        lines = lines.filter { !$0.isEmpty }
        
        // Android 版 Legado 习惯在每段开头加两个空格
        return lines.map { "　　" + $0 }.joined(separator: "\n\n")
    }
}
