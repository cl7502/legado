import Foundation

/// 书籍模型
/// 目标：100% 对标 Android 版 Book.kt
struct Book: Codable, Identifiable, Equatable {
    var id: String { bookUrl }
    
    var bookUrl: String = ""
    var name: String = ""
    var author: String = ""
    var kind: String?
    var wordCount: String?
    var intro: String?
    var coverUrl: String?
    var tocUrl: String?
    
    // 归属信息
    var origin: String = "" // 书源 URL
    var originName: String = ""
    
    // 解析中间变量
    var variable: String?
    var infoHtml: String?
    
    // 阅读进度
    var totalChapterNum: Int = 0
    var latestChapterTitle: String?
    var latestChapterUrl: String?
    var durChapterTitle: String?
    var durChapterIndex: Int = 0
    var durChapterTime: Int64 = 0
    var durChapterPos: Int = 0
    
    var lastCheckTime: Int64 = 0
    var canUpdate: Bool = true
    var useReplaceRule: Bool = true
    
    enum CodingKeys: String, CodingKey {
        case bookUrl, name, author, kind, wordCount, intro, coverUrl, tocUrl
        case origin, originName, variable, infoHtml
        case totalChapterNum, latestChapterTitle, latestChapterUrl
        case durChapterTitle, durChapterIndex, durChapterTime, durChapterPos
        case lastCheckTime, canUpdate, useReplaceRule
    }
}
