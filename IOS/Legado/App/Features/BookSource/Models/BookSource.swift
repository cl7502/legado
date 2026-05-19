import Foundation

/// 书源模型 (GSD 强化版)
/// 目标：100% 对标 Android 版 BookSource.kt
struct BookSource: Codable, Identifiable, Equatable {
    var id: String { bookSourceUrl }
    
    // 基础信息
    var bookSourceUrl: String = ""
    var bookSourceName: String = ""
    var bookSourceGroup: String?
    var bookSourceType: Int = 0 // 0: 文本, 1: 音频, 2: 图片, 3: 文件
    var bookSourceComment: String?
    var customOrder: Int = 0
    var enabled: Bool = true
    var lastUpdateTime: Int64 = 0
    
    // 登录与并发
    var loginUrl: String?
    var loginUi: String?
    var loginCheckJs: String?
    var concurrentRate: String?
    var header: String? // JSON 格式
    
    // 核心规则
    var searchUrl: String?
    var ruleSearchUrl: String?
    var ruleBookInfo: String?
    var ruleToc: String?
    var ruleContent: String?
    var exploreUrl: String?
    
    // 变量与 Cookie
    var enabledCookieJar: Bool = false
    var variableComment: String?
    var respondTime: Int64 = 0
    
    enum CodingKeys: String, CodingKey {
        case bookSourceUrl, bookSourceName, bookSourceGroup, bookSourceType
        case bookSourceComment, customOrder, enabled, lastUpdateTime
        case loginUrl, loginUi, loginCheckJs, concurrentRate, header
        case searchUrl, ruleSearchUrl, ruleBookInfo, ruleToc, ruleContent, exploreUrl
        case enabledCookieJar, variableComment, respondTime
    }
}

extension BookSource {
    /// 获取请求头字典
    var headerDictionary: [String: String] {
        guard let data = header?.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
            return [:]
        }
        return dict
    }
}
