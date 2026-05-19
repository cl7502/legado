import Foundation

/// 增强型规则执行器 (V2.0 终极版)
/// 目标：100% 还原 Android 版链式解析逻辑
class RuleExecutor {
    static let shared = RuleExecutor()
    
    private let jsEngine = LegadoJSEngine.shared
    private let htmlParser = HTMLParser.shared
    private let jsonEngine = JSONPathEngine.shared
    
    /// 执行解析逻辑（单条结果，支持链式）
    func execute(_ rule: String, in context: inout AnalyzeContext) -> String? {
        let segments = RuleParser.shared.parseChain(rule)
        guard !segments.isEmpty else { return nil }
        
        var currentInput: Any? = context.result
        
        for segment in segments {
            guard let input = currentInput as? String else { break }
            var tempContext = context
            tempContext.result = input
            
            switch segment.type {
            case .js:
                currentInput = jsEngine.evaluateRule(segment.content, in: &tempContext)
            case .json:
                currentInput = jsonEngine.extract(json: input, path: segment.content)
            case .xpath:
                currentInput = htmlParser.xpathText(input, xpath: segment.content)
            case .defaultRule:
                currentInput = htmlParser.text(input, query: segment.content)
            case .regex:
                currentInput = applyRegex(input, pattern: segment.content)
            }
            
            context.variables = tempContext.variables
        }
        
        return currentInput as? String
    }
    
    /// 执行解析逻辑（列表版，支持链式）
    func executeList(_ rule: String, in context: inout AnalyzeContext) -> [String] {
        let segments = RuleParser.shared.parseChain(rule)
        guard !segments.isEmpty else { return [] }
        
        var currentInputs: [String] = [context.result as? String].compactMap { $0 }
        
        for (index, segment) in segments.enumerated() {
            var nextInputs: [String] = []
            
            for input in currentInputs {
                var tempContext = context
                tempContext.result = input
                
                if index == segments.count - 1 {
                    // 最后一节，尝试产生列表
                    switch segment.type {
                    case .xpath:
                        nextInputs.append(contentsOf: htmlParser.xpathList(input, xpath: segment.content))
                    case .defaultRule:
                        nextInputs.append(contentsOf: htmlParser.cssList(input, query: segment.content))
                    case .json:
                        if let array = jsonEngine.extract(json: input, path: segment.content) as? [Any] {
                            nextInputs.append(contentsOf: array.map { "\($0)" })
                        }
                    case .js:
                        let jsResult = jsEngine.evaluateRule(segment.content, in: &tempContext)
                        nextInputs.append(contentsOf: jsResult?.components(separatedBy: ",") ?? [])
                    default:
                        if let single = executeSegment(segment, input: input, context: &tempContext) {
                            nextInputs.append(single)
                        }
                    }
                } else {
                    // 中间节，保持单条流转
                    if let single = executeSegment(segment, input: input, context: &tempContext) {
                        nextInputs.append(single)
                    }
                }
                context.variables = tempContext.variables
            }
            currentInputs = nextInputs
        }
        
        return currentInputs
    }
    
    private func executeSegment(_ segment: RuleSegment, input: String, context: inout AnalyzeContext) -> String? {
        switch segment.type {
        case .js: return jsEngine.evaluateRule(segment.content, in: &context)
        case .json: return "\(jsonEngine.extract(json: input, path: segment.content) ?? "")"
        case .xpath: return htmlParser.xpathText(input, xpath: segment.content)
        case .regex: return applyRegex(input, pattern: segment.content)
        default: return htmlParser.text(input, query: segment.content)
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
