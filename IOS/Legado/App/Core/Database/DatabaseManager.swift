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

            // 直接建表：新安装时创建所有表，已存在时 IF NOT EXISTS 是 no-op，无需迁移开销
            try createSchemaIfNeeded()
        } catch {
            fatalError("❌ [DB Error]: Failed to initialize database: \(error)")
        }
    }

    private func createSchemaIfNeeded() throws {
        try dbPool.write { db in
            // ── 书源表 ─────────────────────────────────────────────────────────────
            try db.execute(sql: """
            CREATE TABLE IF NOT EXISTS book_source (
                bookSourceUrl TEXT PRIMARY KEY,
                bookSourceName TEXT NOT NULL,
                bookSourceGroup TEXT,
                bookSourceType INTEGER DEFAULT 0,
                customOrder INTEGER DEFAULT 0,
                enabled INTEGER DEFAULT 1,
                lastUpdateTime INTEGER DEFAULT 0,
                header TEXT, searchUrl TEXT,
                ruleSearchUrl TEXT, ruleBookInfo TEXT, ruleToc TEXT, ruleContent TEXT, exploreUrl TEXT,
                bookSourceComment TEXT, weight INTEGER DEFAULT 0, bookUrlPattern TEXT,
                jsLib TEXT, loginUrl TEXT, loginUi TEXT, loginCheckJs TEXT,
                concurrentRate TEXT, enabledCookieJar INTEGER DEFAULT 0,
                variableComment TEXT, respondTime INTEGER DEFAULT 0,
                ruleSearchList TEXT, ruleSearchName TEXT, ruleSearchAuthor TEXT,
                ruleSearchKind TEXT, ruleSearchLastChapter TEXT, ruleSearchCoverUrl TEXT, ruleSearchNoteUrl TEXT,
                ruleBookInfoInit TEXT, ruleBookName TEXT, ruleBookAuthor TEXT,
                ruleBookIntro TEXT, ruleBookKind TEXT, ruleBookLastChapter TEXT, ruleBookCoverUrl TEXT,
                ruleTocUrl TEXT, ruleTocList TEXT, ruleChapterName TEXT, ruleChapterUrl TEXT,
                ruleChapterVip TEXT, ruleTocNextUrl TEXT, ruleContentNextUrl TEXT, ruleContentReplace TEXT,
                ruleExploreList TEXT, ruleExploreName TEXT, ruleExploreAuthor TEXT,
                ruleExploreKind TEXT, ruleExploreCoverUrl TEXT, ruleExploreNoteUrl TEXT,
                enabledExplore INTEGER DEFAULT 1, coverDecodeJs TEXT, exploreScreen TEXT,
                ruleSearchIntro TEXT, ruleSearchUpdateTime TEXT, ruleSearchWordCount TEXT,
                ruleChapterUpdateTime TEXT, ruleTocPreUpdateJs TEXT, ruleTocFormatJs TEXT,
                checkState INTEGER DEFAULT 0
            )
            """)
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_book_source_enabled ON book_source (enabled)")

            // ── 书籍表 ─────────────────────────────────────────────────────────────
            try db.execute(sql: """
            CREATE TABLE IF NOT EXISTS book (
                bookUrl TEXT PRIMARY KEY,
                name TEXT NOT NULL, author TEXT NOT NULL,
                coverUrl TEXT, origin TEXT NOT NULL,
                durChapterIndex INTEGER DEFAULT 0, durChapterPos INTEGER DEFAULT 0,
                durChapterTime INTEGER DEFAULT 0,
                kind TEXT, wordCount TEXT, intro TEXT, originName TEXT, variable TEXT,
                infoHtml TEXT, totalChapterNum INTEGER DEFAULT 0,
                latestChapterTitle TEXT, latestChapterUrl TEXT, durChapterTitle TEXT,
                lastCheckTime INTEGER DEFAULT 0, canUpdate INTEGER DEFAULT 1,
                useReplaceRule INTEGER DEFAULT 1, tocUrl TEXT
            )
            """)
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_book_name   ON book (name)")
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_book_author ON book (author)")
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_book_origin ON book (origin)")
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_book_time   ON book (durChapterTime)")

            // ── 章节表 ─────────────────────────────────────────────────────────────
            try db.execute(sql: """
            CREATE TABLE IF NOT EXISTS book_chapter (
                url TEXT PRIMARY KEY,
                title TEXT NOT NULL, `index` INTEGER NOT NULL,
                bookUrl TEXT NOT NULL REFERENCES book(bookUrl) ON DELETE CASCADE,
                tag TEXT, volume TEXT, resourceUrl TEXT,
                pay INTEGER DEFAULT 0, vip INTEGER DEFAULT 0,
                updateTime INTEGER DEFAULT 0, content TEXT
            )
            """)
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_chapter_book_index ON book_chapter (bookUrl, `index`)")

            // ── 净化规则表 ────────────────────────────────────────────────────────
            try db.execute(sql: """
            CREATE TABLE IF NOT EXISTS replace_rule (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL, pattern TEXT NOT NULL,
                replacement TEXT DEFAULT '', isEnabled INTEGER DEFAULT 1,
                `order` INTEGER DEFAULT 0, regex INTEGER DEFAULT 1, scope TEXT
            )
            """)

            // ── 书签表 ────────────────────────────────────────────────────────────
            try db.execute(sql: """
            CREATE TABLE IF NOT EXISTS bookmarks (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                bookUrl TEXT NOT NULL, chapterIndex INTEGER NOT NULL,
                chapterTitle TEXT NOT NULL, chapterPos INTEGER DEFAULT 0,
                content TEXT DEFAULT '', createdAt DATETIME NOT NULL
            )
            """)
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_bookmarks_book ON bookmarks (bookUrl)")

            // ── 高亮划线表 ────────────────────────────────────────────────────────
            try db.execute(sql: """
            CREATE TABLE IF NOT EXISTS book_highlights (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                bookUrl TEXT NOT NULL, chapterIndex INTEGER NOT NULL,
                startOffset INTEGER NOT NULL, endOffset INTEGER NOT NULL,
                selectedText TEXT DEFAULT '', color INTEGER DEFAULT 0,
                note TEXT, createdAt DATETIME NOT NULL
            )
            """)
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_highlights_book ON book_highlights (bookUrl)")
        }
    }

    // migrator 属性已删除：不再使用 GRDB 迁移系统，改为 CREATE TABLE IF NOT EXISTS。
    // 如未来需要修改已有表结构，直接在 createSchemaIfNeeded 中用 ALTER TABLE 处理，
    // 并通过 UserDefaults 标记版本号按需执行一次。
}

// MARK: - 数据访问扩展 (DAO)

extension DatabaseManager {
    
    // --- 书源操作 ---
    
    func deleteBookSource(_ source: BookSource) async throws {
        _ = try await dbPool.write { db in
            try BookSource.filter(Column("bookSourceUrl") == source.bookSourceUrl).deleteAll(db)
        }
    }

    func deleteAllBookSources() async throws {
        _ = try await dbPool.write { db in
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
        _ = try await dbPool.write { db in
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
        let bm = bookmark
        _ = try await dbPool.write { db in try bm.save(db) }
    }

    func deleteBookmark(_ bookmark: Bookmark) async throws {
        guard let id = bookmark.id else { return }
        _ = try await dbPool.write { db in
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
        let h = highlight
        _ = try await dbPool.write { db in try h.save(db) }
    }

    func deleteHighlight(_ highlight: BookHighlight) async throws {
        guard let id = highlight.id else { return }
        _ = try await dbPool.write { db in
            try BookHighlight.filter(Column("id") == id).deleteAll(db)
        }
    }
}
