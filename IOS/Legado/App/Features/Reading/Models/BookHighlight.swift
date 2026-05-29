import Foundation
import UIKit
import GRDB

/// 高亮/划线模型（对应 Android BookChapterReview）
struct BookHighlight: Codable, Identifiable, Equatable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "book_highlights"

    var id: Int64?
    var bookUrl:      String
    var chapterIndex: Int
    var startOffset:  Int       // 在完整章节文本中的起始字符偏移
    var endOffset:    Int       // 结束字符偏移
    var selectedText: String    // 高亮文字内容（冗余存储，便于列表展示）
    var color:        Int       // 0=黄 1=绿 2=蓝 3=粉
    var note:         String?   // 可选用户笔记
    var createdAt:    Date

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

extension BookHighlight {
    static let colors: [UIColor] = [
        UIColor.systemYellow.withAlphaComponent(0.45),
        UIColor.systemGreen.withAlphaComponent(0.35),
        UIColor.systemBlue.withAlphaComponent(0.25),
        UIColor.systemPink.withAlphaComponent(0.35),
    ]
    var uiColor: UIColor { Self.colors[min(color, Self.colors.count - 1)] }
}
