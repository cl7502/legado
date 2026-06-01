// IOS/Legado/App/Core/Sync/SyncModels.swift
import Foundation

// MARK: - metadata.json

struct SyncMetadata: Codable {
    var version: Int = 1
    var deviceId: String
    var updatedAt: Int64
    var files: [String: Int64]

    static func makeNew() -> SyncMetadata {
        let id = UserDefaults.standard.string(forKey: "sync.deviceId") ?? {
            let newId = UUID().uuidString
            UserDefaults.standard.set(newId, forKey: "sync.deviceId")
            return newId
        }()
        return SyncMetadata(deviceId: id, updatedAt: Date().milliseconds,
                            files: ["books": 0, "reading_progress": 0,
                                    "bookmarks": 0, "highlights": 0])
    }
}

// MARK: - books.json

struct SyncBookEntry: Codable {
    var bookUrl: String
    var name: String
    var author: String
    var origin: String
    var originName: String
    var coverUrl: String?
    var intro: String?
    var tocUrl: String?
    var lastUpdatedAt: Int64

    init(from book: Book) {
        bookUrl       = book.bookUrl
        name          = book.name
        author        = book.author
        origin        = book.origin
        originName    = book.originName
        coverUrl      = book.coverUrl
        intro         = book.intro
        tocUrl        = book.tocUrl
        lastUpdatedAt = book.durChapterTime
    }

    func applyTo(_ book: inout Book) {
        book.name       = name
        book.author     = author
        book.origin     = origin
        book.originName = originName
        book.coverUrl   = coverUrl
        book.intro      = intro
        book.tocUrl     = tocUrl
        book.durChapterTime = lastUpdatedAt
    }
}

// MARK: - reading_progress.json

struct SyncProgressEntry: Codable {
    var bookUrl: String
    var durChapterIndex: Int
    var durChapterPos: Int
    var durChapterTime: Int64

    init(from book: Book) {
        bookUrl         = book.bookUrl
        durChapterIndex = book.durChapterIndex
        durChapterPos   = book.durChapterPos
        durChapterTime  = book.durChapterTime
    }
}

// MARK: - bookmarks.json

struct SyncBookmarkEntry: Codable {
    var bookUrl: String
    var chapterIndex: Int
    var chapterTitle: String
    var chapterPos: Int
    var content: String
    var createdAt: Int64

    init(from bm: Bookmark) {
        bookUrl      = bm.bookUrl
        chapterIndex = bm.chapterIndex
        chapterTitle = bm.chapterTitle
        chapterPos   = bm.chapterPos
        content      = bm.content
        createdAt    = Int64(bm.createdAt.timeIntervalSince1970 * 1000)
    }

    func toBookmark() -> Bookmark {
        Bookmark(bookUrl: bookUrl, chapterIndex: chapterIndex,
                 chapterTitle: chapterTitle, chapterPos: chapterPos,
                 content: content,
                 createdAt: Date(timeIntervalSince1970: Double(createdAt) / 1000))
    }
}

// MARK: - highlights.json

struct SyncHighlightEntry: Codable {
    var bookUrl: String
    var chapterIndex: Int
    var startOffset: Int
    var endOffset: Int
    var color: Int
    var selectedText: String
    var note: String?
    var createdAt: Int64

    init(from h: BookHighlight) {
        bookUrl      = h.bookUrl
        chapterIndex = h.chapterIndex
        startOffset  = h.startOffset
        endOffset    = h.endOffset
        color        = h.color
        selectedText = h.selectedText
        note         = h.note
        createdAt    = Int64(h.createdAt.timeIntervalSince1970 * 1000)
    }

    func toHighlight() -> BookHighlight {
        BookHighlight(bookUrl: bookUrl, chapterIndex: chapterIndex,
                      startOffset: startOffset, endOffset: endOffset,
                      selectedText: selectedText, color: color, note: note,
                      createdAt: Date(timeIntervalSince1970: Double(createdAt) / 1000))
    }
}

// MARK: - Date helper

extension Date {
    var milliseconds: Int64 { Int64(timeIntervalSince1970 * 1000) }
}
