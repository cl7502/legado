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
            }
            try db.create(index: "idx_chapter_book_index", on: "book_chapter", columns: ["bookUrl", "index"])
            
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
        
        // v2: 补充所有规则字段列（v1 只有 JSON blob 列，规则字段全部缺失）
        migrator.registerMigration("v2-rule-columns") { db in
            try db.alter(table: "book_source") { t in
                t.add(column: "bookSourceComment",    .text)
                t.add(column: "weight",               .integer).defaults(to: 0)
                t.add(column: "bookUrlPattern",       .text)
                t.add(column: "jsLib",                .text)
                t.add(column: "loginUrl",             .text)
                t.add(column: "loginUi",              .text)
                t.add(column: "loginCheckJs",         .text)
                t.add(column: "concurrentRate",       .text)
                t.add(column: "enabledCookieJar",     .boolean).defaults(to: false)
                t.add(column: "variableComment",      .text)
                t.add(column: "respondTime",          .integer).defaults(to: 0)
                // 搜索规则
                t.add(column: "ruleSearchList",       .text)
                t.add(column: "ruleSearchName",       .text)
                t.add(column: "ruleSearchAuthor",     .text)
                t.add(column: "ruleSearchKind",       .text)
                t.add(column: "ruleSearchLastChapter",.text)
                t.add(column: "ruleSearchCoverUrl",   .text)
                t.add(column: "ruleSearchNoteUrl",    .text)
                // 详情页规则
                t.add(column: "ruleBookInfoInit",     .text)
                t.add(column: "ruleBookName",         .text)
                t.add(column: "ruleBookAuthor",       .text)
                t.add(column: "ruleBookIntro",        .text)
                t.add(column: "ruleBookKind",         .text)
                t.add(column: "ruleBookLastChapter",  .text)
                t.add(column: "ruleBookCoverUrl",     .text)
                t.add(column: "ruleTocUrl",           .text)
                // 目录规则
                t.add(column: "ruleTocList",          .text)
                t.add(column: "ruleChapterName",      .text)
                t.add(column: "ruleChapterUrl",       .text)
                t.add(column: "ruleChapterVip",       .text)
                t.add(column: "ruleTocNextUrl",       .text)
                // 正文规则（ruleContent 已在 v1，只补其余）
                t.add(column: "ruleContentNextUrl",   .text)
                t.add(column: "ruleContentReplace",   .text)
                // 发现规则
                t.add(column: "ruleExploreList",      .text)
                t.add(column: "ruleExploreName",      .text)
                t.add(column: "ruleExploreAuthor",    .text)
                t.add(column: "ruleExploreKind",      .text)
                t.add(column: "ruleExploreCoverUrl",  .text)
                t.add(column: "ruleExploreNoteUrl",   .text)
            }
        }

        // v3: 书籍表补充缺失列
        migrator.registerMigration("v3-book-columns") { db in
            try db.alter(table: "book") { t in
                t.add(column: "kind",               .text)
                t.add(column: "wordCount",          .text)
                t.add(column: "intro",              .text)
                t.add(column: "originName",         .text)
                t.add(column: "variable",           .text)
                t.add(column: "infoHtml",           .text)
                t.add(column: "totalChapterNum",    .integer).defaults(to: 0)
                t.add(column: "latestChapterTitle", .text)
                t.add(column: "latestChapterUrl",   .text)
                t.add(column: "durChapterTitle",    .text)
                t.add(column: "lastCheckTime",      .integer).defaults(to: 0)
                t.add(column: "canUpdate",          .boolean).defaults(to: true)
                t.add(column: "useReplaceRule",     .boolean).defaults(to: true)
                t.add(column: "tocUrl",             .text)
            }
        }

        // v4: 章节表补充缺失列
        migrator.registerMigration("v4-chapter-columns") { db in
            try db.alter(table: "book_chapter") { t in
                t.add(column: "tag",         .text)
                t.add(column: "volume",      .text)
                t.add(column: "resourceUrl", .text)
                t.add(column: "pay",         .boolean).defaults(to: false)
                t.add(column: "vip",         .boolean).defaults(to: false)
                t.add(column: "updateTime",  .integer).defaults(to: 0)
            }
        }

        // v5: 补充 replace_rule 缺失的 regex / scope 列，以及为 save/delete 所需的正确 id 支持
        migrator.registerMigration("v5-replace-rule-columns") { db in
            try db.alter(table: "replace_rule") { t in
                t.add(column: "regex", .boolean).defaults(to: true)
                t.add(column: "scope", .text)
            }
        }

        // v6: book_source 补充 ISSUE-019 新增字段（enabledExplore / coverDecodeJs 等）
        migrator.registerMigration("v6-book-source-issue019") { db in
            try db.alter(table: "book_source") { t in
                t.add(column: "enabledExplore",       .boolean).defaults(to: true)
                t.add(column: "coverDecodeJs",        .text)
                t.add(column: "exploreScreen",        .text)
                t.add(column: "ruleSearchIntro",      .text)
                t.add(column: "ruleSearchUpdateTime", .text)
                t.add(column: "ruleSearchWordCount",  .text)
                t.add(column: "ruleChapterUpdateTime",.text)
                t.add(column: "ruleTocPreUpdateJs",   .text)
                t.add(column: "ruleTocFormatJs",      .text)
            }
        }

        migrator.registerMigration("v7-check-state") { db in
            try db.alter(table: "book_source") { t in
                // 0=未检测 1=正常 2=慢速 3=失败
                t.add(column: "checkState", .integer).defaults(to: 0)
            }
        }

        migrator.registerMigration("v8-bookmarks") { db in
            try db.create(table: "bookmarks", ifNotExists: true) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("bookUrl",      .text).notNull().indexed()
                t.column("chapterIndex", .integer).notNull()
                t.column("chapterTitle", .text).notNull()
                t.column("chapterPos",   .integer).notNull().defaults(to: 0)
                t.column("content",      .text).notNull().defaults(to: "")
                t.column("createdAt",    .datetime).notNull()
            }
        }

        migrator.registerMigration("v9-highlights") { db in
            try db.create(table: "book_highlights", ifNotExists: true) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("bookUrl",      .text).notNull().indexed()
                t.column("chapterIndex", .integer).notNull()
                t.column("startOffset",  .integer).notNull()
                t.column("endOffset",    .integer).notNull()
                t.column("selectedText", .text).notNull().defaults(to: "")
                t.column("color",        .integer).notNull().defaults(to: 0)
                t.column("note",         .text)
                t.column("createdAt",    .datetime).notNull()
            }
        }

        migrator.registerMigration("v10-chapter-content-cache") { db in
            try db.alter(table: "book_chapter") { t in
                t.add(column: "content", .text)
            }
        }

        return migrator
    }
}

// MARK: - 数据访问扩展 (DAO)

extension DatabaseManager {
    
    // --- 书源操作 ---
    
    func deleteBookSource(_ source: BookSource) async throws {
        try await dbPool.write { db in
            try BookSource.filter(Column("bookSourceUrl") == source.bookSourceUrl).deleteAll(db)
        }
    }

    func deleteAllBookSources() async throws {
        try await dbPool.write { db in
            try BookSource.deleteAll(db)
        }
    }

    /// 保存单个书源的检测结果（checkState / respondTime / lastCheckTime / enabled）
    func saveCheckResult(_ source: BookSource) async throws {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        try await dbPool.write { db in
            try db.execute(
                sql: """
                UPDATE book_source
                SET checkState=:cs, respondTime=:rt, lastCheckTime=:lct, enabled=:en
                WHERE bookSourceUrl=:url
                """,
                arguments: [
                    "cs":  source.checkState,
                    "rt":  source.respondTime,
                    "lct": now,
                    "en":  source.enabled,
                    "url": source.bookSourceUrl,
                ]
            )
        }
    }

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

    /// 从书架删除书籍，同时清除缓存的章节列表和正文内容
    func deleteBook(_ book: Book) async throws {
        try await dbPool.write { db in
            try Book.filter(Column("bookUrl") == book.bookUrl).deleteAll(db)
            try Chapter.filter(Column("bookUrl") == book.bookUrl).deleteAll(db)
        }
    }
    
    // --- 章节操作 ---
    
    func saveChapters(_ chapters: [Chapter], for bookUrl: String) async throws {
        try await dbPool.write { db in
            // 先删本书全部旧章节（URL 可能因书源规则修正而改变，需全量替换）
            try Chapter.filter(Column("bookUrl") == bookUrl).deleteAll(db)
            for chapter in chapters {
                var c = chapter
                c.bookUrl = bookUrl
                // save() = INSERT OR REPLACE，兼容其他残留记录
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

    /// 读取单章节缓存正文（nil = 未缓存或内容为空）
    func getChapterContent(url: String) async -> String? {
        try? await dbPool.read { db in
            let row = try Row.fetchOne(
                db,
                sql: "SELECT content FROM book_chapter WHERE url = ?",
                arguments: [url]
            )
            return row?["content"] as? String
        }
    }

    /// 持久化章节正文到 DB
    func saveChapterContent(_ content: String, for chapterUrl: String) async {
        try? await dbPool.write { db in
            try db.execute(
                sql: "UPDATE book_chapter SET content = ? WHERE url = ?",
                arguments: [content, chapterUrl]
            )
        }
    }
    
    // --- 净化规则操作 ---

    func getReplaceRules() async throws -> [ReplaceRule] {
        try await dbPool.read { db in
            try ReplaceRule.filter(Column("isEnabled") == true)
                .order(Column("order").asc)
                .fetchAll(db)
        }
    }

    func getAllReplaceRules() async throws -> [ReplaceRule] {
        try await dbPool.read { db in
            try ReplaceRule.order(Column("order").asc).fetchAll(db)
        }
    }

    func saveReplaceRule(_ rule: ReplaceRule) async throws {
        try await dbPool.write { db in
            try rule.save(db)
        }
    }

    func deleteReplaceRule(_ rule: ReplaceRule) async throws {
        try await dbPool.write { db in
            if let id = rule.id {
                try ReplaceRule.filter(Column("id") == id).deleteAll(db)
            } else {
                try ReplaceRule.filter(Column("name") == rule.name && Column("pattern") == rule.pattern)
                    .deleteAll(db)
            }
        }
    }

    func saveReplaceRules(_ rules: [ReplaceRule]) async throws {
        try await dbPool.write { db in
            for rule in rules {
                try rule.save(db)
            }
        }
    }

    // MARK: - 书签 DAO

    func getBookmarks(bookUrl: String) async throws -> [Bookmark] {
        try await dbPool.read { db in
            try Bookmark
                .filter(Column("bookUrl") == bookUrl)
                .order(Column("createdAt").desc)
                .fetchAll(db)
        }
    }

    func saveBookmark(_ bookmark: Bookmark) async throws {
        var bm = bookmark
        try await dbPool.write { db in try bm.save(db) }
    }

    func deleteBookmark(_ bookmark: Bookmark) async throws {
        guard let id = bookmark.id else { return }
        try await dbPool.write { db in
            try Bookmark.filter(Column("id") == id).deleteAll(db)
        }
    }

    // MARK: - 高亮/划线 DAO

    func getHighlights(bookUrl: String, chapterIndex: Int) async throws -> [BookHighlight] {
        try await dbPool.read { db in
            try BookHighlight
                .filter(Column("bookUrl") == bookUrl && Column("chapterIndex") == chapterIndex)
                .order(Column("startOffset").asc)
                .fetchAll(db)
        }
    }

    func getAllHighlights(bookUrl: String) async throws -> [BookHighlight] {
        try await dbPool.read { db in
            try BookHighlight
                .filter(Column("bookUrl") == bookUrl)
                .order(Column("chapterIndex").asc, Column("startOffset").asc)
                .fetchAll(db)
        }
    }

    func saveHighlight(_ highlight: BookHighlight) async throws {
        var h = highlight
        try await dbPool.write { db in try h.save(db) }
    }

    func deleteHighlight(_ highlight: BookHighlight) async throws {
        guard let id = highlight.id else { return }
        try await dbPool.write { db in
            try BookHighlight.filter(Column("id") == id).deleteAll(db)
        }
    }
}
