import Foundation

/// 搜索结果模型
/// 用于展示在搜索列表中的初步书籍信息
struct SearchResult: Codable, Identifiable, Equatable {
    var id: String { bookUrl }
    
    var name: String = ""
    var author: String = ""
    var bookUrl: String = ""
    var kind: String?
    var intro: String?
    var coverUrl: String?
    var wordCount: String?
    var latestChapter: String?
    
    // 归属信息
    var origin: String = "" // 书源 URL
    var originName: String = ""
}
