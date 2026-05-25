import Foundation

/// 内容净化规则模型
struct ReplaceRule: Codable, Identifiable, Equatable {
    /// GRDB 自增主键（nil = 新记录，插入后由数据库赋值）
    var id: Int64? = nil

    var name: String = ""
    var pattern: String?
    var replacement: String = ""
    var scope: String?
    var isRegex: Bool = true
    var isEnabled: Bool = true
    var order: Int = 0

    enum CodingKeys: String, CodingKey {
        case id
        case name, pattern, replacement, scope
        case isRegex = "regex"
        case isEnabled = "enabled"
        case order
    }
}
