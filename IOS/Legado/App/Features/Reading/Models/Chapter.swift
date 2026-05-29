import Foundation

/// 章节模型
/// 目标：100% 对标 Android 版 BookChapter.kt
struct Chapter: Codable, Identifiable, Equatable {
    var id: String { url }

    var url: String = ""
    var title: String = ""
    var index: Int = 0

    var tag: String?
    var volume: String?
    var resourceUrl: String?
    var isPay: Bool = false
    var isVip: Bool = false

    var updateTime: Int64 = 0
    var bookUrl: String = "" // 关联书籍

    /// 缓存的正文内容（DB 持久化，避免每次重进阅读器重新网络请求）
    var content: String? = nil

    enum CodingKeys: String, CodingKey {
        case url, title, index, tag, volume, resourceUrl, bookUrl, content
        case isPay = "pay"
        case isVip = "vip"
        case updateTime
    }
}
