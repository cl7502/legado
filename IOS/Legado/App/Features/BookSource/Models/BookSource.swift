import Foundation

/// 书源模型 (V2.0 工业级版)
/// 目标：100% 物理与逻辑对标 Android 版 BookSource.kt
struct BookSource: Codable, Identifiable, Equatable {
    var id: String { bookSourceUrl }
    
    // --- 基础信息 ---
    var bookSourceUrl: String = ""
    var bookSourceName: String = ""
    var bookSourceGroup: String?
    var bookSourceType: Int = 0 
    var bookSourceComment: String?
    var customOrder: Int = 0
    var enabled: Bool = true
    var lastUpdateTime: Int64 = 0
    
    // --- 登录与并发 ---
    var loginUrl: String?
    var loginUi: String?
    var loginCheckJs: String?
    var concurrentRate: String?
    var header: String? 
    
    // --- 搜索规则 (Search) ---
    var searchUrl: String?
    var ruleSearchList: String?        // 对应 bookList
    var ruleSearchName: String?        // 对应 name
    var ruleSearchAuthor: String?      // 对应 author
    var ruleSearchKind: String?        // 对应 kind
    var ruleSearchLastChapter: String? // 对应 lastChapter
    var ruleSearchCoverUrl: String?    // 对应 coverUrl
    var ruleSearchNoteUrl: String?     // 对应 bookUrl
    
    // --- 详情页规则 (BookInfo) ---
    var ruleBookInfoInit: String?
    var ruleBookName: String?
    var ruleBookAuthor: String?
    var ruleBookIntro: String?
    var ruleBookKind: String?
    var ruleBookLastChapter: String?
    var ruleBookCoverUrl: String?
    var ruleTocUrl: String?
    
    // --- 目录规则 (TOC) ---
    var ruleTocList: String?
    var ruleChapterName: String?
    var ruleChapterUrl: String?
    var ruleChapterVip: String?
    
    // --- 正文规则 (Content) ---
    var ruleContent: String?
    var ruleContentReplace: String?
    
    // --- 其他 ---
    var exploreUrl: String?
    var enabledCookieJar: Bool = false
    var variableComment: String?
    var respondTime: Int64 = 0

    // 自定义 CodingKeys 处理 Android JSON 的嵌套结构
    enum CodingKeys: String, CodingKey {
        case bookSourceUrl, bookSourceName, bookSourceGroup, bookSourceType
        case bookSourceComment, customOrder, enabled, lastUpdateTime
        case loginUrl, loginUi, loginCheckJs, concurrentRate, header
        case searchUrl, exploreUrl, enabledCookieJar, variableComment, respondTime
        
        // 嵌套的规则字段通常在 JSON 中是扁平的或有前缀
        case ruleSearchList = "ruleSearchList"
        case ruleSearchName = "ruleSearchName"
        case ruleSearchAuthor = "ruleSearchAuthor"
        case ruleSearchKind = "ruleSearchKind"
        case ruleSearchLastChapter = "ruleSearchLastChapter"
        case ruleSearchCoverUrl = "ruleSearchCoverUrl"
        case ruleSearchNoteUrl = "ruleSearchNoteUrl"
        
        case ruleBookName = "ruleBookName"
        case ruleBookAuthor = "ruleBookAuthor"
        case ruleBookIntro = "ruleBookIntro"
        case ruleBookKind = "ruleBookKind"
        case ruleBookCoverUrl = "ruleBookCoverUrl"
        case ruleTocUrl = "ruleTocUrl"
        
        case ruleTocList = "ruleTocList"
        case ruleChapterName = "ruleChapterName"
        case ruleChapterUrl = "ruleChapterUrl"
        
        case ruleContent = "ruleContent"
    }
}

extension BookSource {
    var headerDictionary: [String: String] {
        guard let data = header?.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
            return [:]
        }
        return dict
    }
}
