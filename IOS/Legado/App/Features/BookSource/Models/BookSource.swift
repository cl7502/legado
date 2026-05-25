import Foundation

/// 书源模型 — 完整对标 Android BookSource.kt
struct BookSource: Identifiable, Equatable {
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
}

// MARK: - Codable（自定义实现，容忍缺失/类型错误的字段）
// JSONDecoder 对 non-optional 字段遇到 keyNotFound 会 throw 导致整批失败。
// 这里用 decodeIfPresent 处理所有业务字段，防止单字段缺失导致整个书源 decode 失败。
extension BookSource: Codable {
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

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        // 必需字段：URL 缺失则整条无效，允许 throw
        bookSourceUrl  = (try? c.decode(String.self, forKey: .bookSourceUrl))  ?? ""
        bookSourceName = (try? c.decode(String.self, forKey: .bookSourceName)) ?? ""

        // 业务整数/布尔 — 用 decodeIfPresent 防止缺失 throw
        bookSourceType  = (try? c.decodeIfPresent(Int.self,   forKey: .bookSourceType))  ?? 0
        customOrder     = (try? c.decodeIfPresent(Int.self,   forKey: .customOrder))     ?? 0
        enabled         = (try? c.decodeIfPresent(Bool.self,  forKey: .enabled))         ?? true
        lastUpdateTime  = (try? c.decodeIfPresent(Int64.self, forKey: .lastUpdateTime))  ?? 0
        weight          = (try? c.decodeIfPresent(Int.self,   forKey: .weight))          ?? 0
        enabledCookieJar = (try? c.decodeIfPresent(Bool.self, forKey: .enabledCookieJar)) ?? false
        respondTime     = (try? c.decodeIfPresent(Int64.self, forKey: .respondTime))     ?? 0

        // 可选字符串字段
        bookSourceGroup   = try? c.decodeIfPresent(String.self, forKey: .bookSourceGroup)
        bookSourceComment = try? c.decodeIfPresent(String.self, forKey: .bookSourceComment)
        bookUrlPattern    = try? c.decodeIfPresent(String.self, forKey: .bookUrlPattern)
        jsLib             = try? c.decodeIfPresent(String.self, forKey: .jsLib)
        loginUrl          = try? c.decodeIfPresent(String.self, forKey: .loginUrl)
        loginUi           = try? c.decodeIfPresent(String.self, forKey: .loginUi)
        loginCheckJs      = try? c.decodeIfPresent(String.self, forKey: .loginCheckJs)
        concurrentRate    = try? c.decodeIfPresent(String.self, forKey: .concurrentRate)
        header            = try? c.decodeIfPresent(String.self, forKey: .header)
        searchUrl         = try? c.decodeIfPresent(String.self, forKey: .searchUrl)
        exploreUrl        = try? c.decodeIfPresent(String.self, forKey: .exploreUrl)
        variableComment   = try? c.decodeIfPresent(String.self, forKey: .variableComment)
        ruleSearchList        = try? c.decodeIfPresent(String.self, forKey: .ruleSearchList)
        ruleSearchName        = try? c.decodeIfPresent(String.self, forKey: .ruleSearchName)
        ruleSearchAuthor      = try? c.decodeIfPresent(String.self, forKey: .ruleSearchAuthor)
        ruleSearchKind        = try? c.decodeIfPresent(String.self, forKey: .ruleSearchKind)
        ruleSearchLastChapter = try? c.decodeIfPresent(String.self, forKey: .ruleSearchLastChapter)
        ruleSearchCoverUrl    = try? c.decodeIfPresent(String.self, forKey: .ruleSearchCoverUrl)
        ruleSearchNoteUrl     = try? c.decodeIfPresent(String.self, forKey: .ruleSearchNoteUrl)
        ruleBookInfoInit      = try? c.decodeIfPresent(String.self, forKey: .ruleBookInfoInit)
        ruleBookName          = try? c.decodeIfPresent(String.self, forKey: .ruleBookName)
        ruleBookAuthor        = try? c.decodeIfPresent(String.self, forKey: .ruleBookAuthor)
        ruleBookIntro         = try? c.decodeIfPresent(String.self, forKey: .ruleBookIntro)
        ruleBookKind          = try? c.decodeIfPresent(String.self, forKey: .ruleBookKind)
        ruleBookLastChapter   = try? c.decodeIfPresent(String.self, forKey: .ruleBookLastChapter)
        ruleBookCoverUrl      = try? c.decodeIfPresent(String.self, forKey: .ruleBookCoverUrl)
        ruleTocUrl            = try? c.decodeIfPresent(String.self, forKey: .ruleTocUrl)
        ruleTocList           = try? c.decodeIfPresent(String.self, forKey: .ruleTocList)
        ruleChapterName       = try? c.decodeIfPresent(String.self, forKey: .ruleChapterName)
        ruleChapterUrl        = try? c.decodeIfPresent(String.self, forKey: .ruleChapterUrl)
        ruleChapterVip        = try? c.decodeIfPresent(String.self, forKey: .ruleChapterVip)
        ruleTocNextUrl        = try? c.decodeIfPresent(String.self, forKey: .ruleTocNextUrl)
        ruleContent           = try? c.decodeIfPresent(String.self, forKey: .ruleContent)
        ruleContentNextUrl    = try? c.decodeIfPresent(String.self, forKey: .ruleContentNextUrl)
        ruleContentReplace    = try? c.decodeIfPresent(String.self, forKey: .ruleContentReplace)
        ruleExploreList       = try? c.decodeIfPresent(String.self, forKey: .ruleExploreList)
        ruleExploreName       = try? c.decodeIfPresent(String.self, forKey: .ruleExploreName)
        ruleExploreAuthor     = try? c.decodeIfPresent(String.self, forKey: .ruleExploreAuthor)
        ruleExploreKind       = try? c.decodeIfPresent(String.self, forKey: .ruleExploreKind)
        ruleExploreCoverUrl   = try? c.decodeIfPresent(String.self, forKey: .ruleExploreCoverUrl)
        ruleExploreNoteUrl    = try? c.decodeIfPresent(String.self, forKey: .ruleExploreNoteUrl)
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
