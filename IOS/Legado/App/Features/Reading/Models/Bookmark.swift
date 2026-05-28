import Foundation
import GRDB

/// 书签模型
struct Bookmark: Codable, Identifiable, Equatable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "bookmarks"

    var id: Int64?
    var bookUrl: String          // 对应 Book.bookUrl（外键）
    var chapterIndex: Int        // 章节序号
    var chapterTitle: String     // 章节标题（冗余存储，便于显示）
    var chapterPos: Int          // 页码（章节内页码）
    var content: String          // 正文前 80 字摘要
    var createdAt: Date

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
