import Foundation

/// 解析上下文 (Execution Scope)
/// 目标：在多级解析（搜索 -> 详情 -> 目录 -> 正文）中透传状态
/// 对标：Android 版的解析上下文管理
struct AnalyzeContext {
    /// 当前关联的书源
    let source: BookSource
    
    /// 上一级解析的结果 (可能是 HTML 字符串或 JSON 对象)
    var result: Any?
    
    /// 当前请求的基础 URL
    var baseUrl: String
    
    /// 当前请求的 Cookie
    var cookie: String?
    
    /// 用户自定义变量 (用于 @get/@put 规则)
    var variables: [String: Any] = [:]
    
    /// 章节页码 (用于翻页解析)
    var page: Int = 1
    
    init(source: BookSource, baseUrl: String? = nil) {
        self.source = source
        self.baseUrl = baseUrl ?? source.bookSourceUrl
    }
}
