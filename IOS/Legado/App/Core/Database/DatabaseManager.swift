import Foundation
import GRDB

/// 数据库管理器 (V2.0 强化版)
class DatabaseManager {
    static let shared = DatabaseManager()
    
    var dbPool: DatabasePool!
    
    private init() {
        setupDatabase()
    }
    
    private func setupDatabase() {
        do {
            let databaseURL = try FileManager.default
                .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("legado_v2.sqlite")
            
            var config = Configuration()
            config.prepareDatabase { db in
                try db.execute(sql: "PRAGMA foreign_keys = ON")
            }
            
            dbPool = try DatabasePool(path: databaseURL.path, configuration: config)
            
            // 执行迁移
            try migrator.migrate(dbPool)
        } catch {
            fatalError("❌ [DB Error]: Failed to initialize database: \(error)")
        }
    }
    
    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        
        migrator.registerMigration("v1-initial") { db in
            // 1. 书源表
            try db.create(table: "book_source") { t in
                t.column("bookSourceUrl", .text).primaryKey()
                t.column("bookSourceName", .text).notNull()
                t.column("bookSourceGroup", .text)
                t.column("bookSourceType", .integer).defaults(to: 0)
                t.column("customOrder", .integer).defaults(to: 0)
                t.column("enabled", .boolean).defaults(to: true).indexed()
                t.column("lastUpdateTime", .integer).defaults(to: 0)
                t.column("header", .text)
                t.column("searchUrl", .text)
                t.column("ruleSearchUrl", .text)
                t.column("ruleBookInfo", .text)
                t.column("ruleToc", .text)
                t.column("ruleContent", .text)
                t.column("exploreUrl", .text)
            }
            
            // 2. 书籍表
            try db.create(table: "book") { t in
                t.column("bookUrl", .text).primaryKey()
                t.column("name", .text).notNull().indexed()
                t.column("author", .text).notNull().indexed()
                t.column("coverUrl", .text)
                t.column("origin", .text).notNull().indexed() // 书源 URL
                t.column("durChapterIndex", .integer).defaults(to: 0)
                t.column("durChapterPos", .integer).defaults(to: 0)
                t.column("durChapterTime", .integer).defaults(to: 0).indexed()
            }
            
            // 3. 章节表
            try db.create(table: "book_chapter") { t in
                t.column("url", .text).primaryKey()
                t.column("title", .text).notNull()
                t.column("index", .integer).notNull()
                t.column("bookUrl", .text).notNull()
                    .references("book", column: "bookUrl", onDelete: .cascade)
                t.index(["bookUrl", "index"])
            }
            
            // 4. 净化规则表
            try db.create(table: "replace_rule") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull()
                t.column("pattern", .text).notNull()
                t.column("replacement", .text).defaults(to: "")
                t.column("isEnabled", .boolean).defaults(to: true)
                t.column("order", .integer).defaults(to: 0)
            }
        }
        
        return migrator
    }
}

// MARK: - 数据访问扩展 (DAO)

extension DatabaseManager {
    
    // --- 书源操作 ---
    
    func saveBookSources(_ sources: [BookSource]) async throws {
        try await dbPool.write { db in
            for source in sources {
                try source.save(db)
            }
        }
    }
    
    func getAllBookSources() async throws -> [BookSource] {
        try await dbPool.read { db in
            try BookSource.order(Column("customOrder").asc).fetchAll(db)
        }
    }
    
    func getEnabledBookSources() async throws -> [BookSource] {
        try await dbPool.read { db in
            try BookSource.filter(Column("enabled") == true)
                .order(Column("customOrder").asc)
                .fetchAll(db)
        }
    }
    
    // --- 书架操作 ---
    
    func getBookshelf() async throws -> [Book] {
        try await dbPool.read { db in
            try Book.order(Column("durChapterTime").desc).fetchAll(db)
        }
    }
    
    func saveBook(_ book: Book) async throws {
        try await dbPool.write { db in
            try book.save(db)
        }
    }
    
    // --- 章节操作 ---
    
    func saveChapters(_ chapters: [Chapter], for bookUrl: String) async throws {
        try await dbPool.write { db in
            // 批量保存，使用事务加速
            for chapter in chapters {
                var c = chapter
                c.bookUrl = bookUrl
                try c.save(db)
            }
        }
    }
    
    func getChapters(for bookUrl: String) async throws -> [Chapter] {
        try await dbPool.read { db in
            try Chapter.filter(Column("bookUrl") == bookUrl)
                .order(Column("index").asc)
                .fetchAll(db)
        }
    }
}
