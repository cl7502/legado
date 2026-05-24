import Foundation

/// 书源模型 — 完整对标 Android BookSource.kt
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
    var weight: Int = 0
    var bookUrlPattern: String?
    var jsLib: String?

    // --- 登录与并发 ---
    var loginUrl: String?
    var loginUi: String?
    var loginCheckJs: String?
    var concurrentRate: String?
    var header: String?

    // --- 搜索规则 ---
    var searchUrl: String?
    var ruleSearchList: String?
    var ruleSearchName: String?
    var ruleSearchAuthor: String?
    var ruleSearchKind: String?
    var ruleSearchLastChapter: String?
    var ruleSearchCoverUrl: String?
    var ruleSearchNoteUrl: String?

    // --- 详情页规则 ---
    var ruleBookInfoInit: String?
    var ruleBookName: String?
    var ruleBookAuthor: String?
    var ruleBookIntro: String?
    var ruleBookKind: String?
    var ruleBookLastChapter: String?
    var ruleBookCoverUrl: String?
    var ruleTocUrl: String?

    // --- 目录规则 ---
    var ruleTocList: String?
    var ruleChapterName: String?
    var ruleChapterUrl: String?
    var ruleChapterVip: String?
    var ruleTocNextUrl: String?

    // --- 正文规则 ---
    var ruleContent: String?
    var ruleContentNextUrl: String?
    var ruleContentReplace: String?

    // --- 发现规则 ---
    var exploreUrl: String?
    var ruleExploreList: String?
    var ruleExploreName: String?
    var ruleExploreAuthor: String?
    var ruleExploreKind: String?
    var ruleExploreCoverUrl: String?
    var ruleExploreNoteUrl: String?

    // --- 其他 ---
    var enabledCookieJar: Bool = false
    var variableComment: String?
    var respondTime: Int64 = 0

    enum CodingKeys: String, CodingKey {
        case bookSourceUrl, bookSourceName, bookSourceGroup, bookSourceType
        case bookSourceComment, customOrder, enabled, lastUpdateTime, weight
        case bookUrlPattern, jsLib
        case loginUrl, loginUi, loginCheckJs, concurrentRate, header
        case searchUrl, exploreUrl, enabledCookieJar, variableComment, respondTime
        case ruleSearchList, ruleSearchName, ruleSearchAuthor, ruleSearchKind
        case ruleSearchLastChapter, ruleSearchCoverUrl, ruleSearchNoteUrl
        case ruleBookInfoInit, ruleBookName, ruleBookAuthor, ruleBookIntro
        case ruleBookKind, ruleBookLastChapter, ruleBookCoverUrl, ruleTocUrl
        case ruleTocList, ruleChapterName, ruleChapterUrl, ruleChapterVip, ruleTocNextUrl
        case ruleContent, ruleContentNextUrl, ruleContentReplace
        case ruleExploreList, ruleExploreName, ruleExploreAuthor
        case ruleExploreKind, ruleExploreCoverUrl, ruleExploreNoteUrl
    }
}

// MARK: - 工具属性
extension BookSource {
    var headerDictionary: [String: String] {
        guard let data = header?.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String]
        else { return [:] }
        return dict
    }
}
