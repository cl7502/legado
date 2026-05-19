import Foundation
import GRDB

// 使模型符合 GRDB 协议

extension BookSource: FetchableRecord, PersistableRecord {
    static var databaseTableName = "book_source"
}

extension Book: FetchableRecord, PersistableRecord {
    static var databaseTableName = "book"
}

extension Chapter: FetchableRecord, PersistableRecord {
    static var databaseTableName = "book_chapter"
}

extension ReplaceRule: FetchableRecord, PersistableRecord {
    static var databaseTableName = "replace_rule"
}
