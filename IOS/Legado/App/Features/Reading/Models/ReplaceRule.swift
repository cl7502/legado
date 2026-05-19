import Foundation

/// 内容净化规则模型
/// 目标：实现正文广告剔除与格式化
struct ReplaceRule: Codable, Identifiable, Equatable {
    var id: String { name + (pattern ?? "") }
    
    var name: String = ""
    var pattern: String?
    var replacement: String = ""
    var scope: String? // 作用范围 (书源 URL 或分组)
    var isRegex: Bool = true
    var isEnabled: Bool = true
    
    // 优先级
    var order: Int = 0
    
    enum CodingKeys: String, CodingKey {
        case name, pattern, replacement, scope
        case isRegex = "regex"
        case isEnabled = "enabled"
        case order
    }
}
