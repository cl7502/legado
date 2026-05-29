import SwiftUI
import Combine

/// 书架业务逻辑
@MainActor
class BookshelfViewModel: ObservableObject {
    @Published var books: [Book] = []
    @Published var isLoading = false

    // P2-C: 排序方式
    enum SortOrder: String, CaseIterable {
        case recentRead = "最近阅读"
        case nameAsc    = "书名 A-Z"
        case author     = "作者"
    }

    @Published var sortOrder: SortOrder = .recentRead

    /// 排序后的书籍列表
    var sortedBooks: [Book] {
        switch sortOrder {
        case .recentRead:
            return books.sorted { $0.durChapterTime > $1.durChapterTime }
        case .nameAsc:
            return books.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
        case .author:
            return books.sorted { ($0.author ?? "").localizedCompare($1.author ?? "") == .orderedAscending }
        }
    }

    private let db = DatabaseManager.shared

    /// 加载书架书籍
    func loadBooks() async {
        isLoading = true
        defer { isLoading = false }

        do {
            self.books = try await db.getBookshelf()
        } catch {
            print("❌ [UI Error]: Failed to load bookshelf: \(error)")
        }
    }

    /// 更新书籍最后阅读时间并保存
    func updateBookProgress(_ book: Book) async {
        var updatedBook = book
        updatedBook.durChapterTime = Int64(Date().timeIntervalSince1970)
        try? await db.saveBook(updatedBook)
        await loadBooks()
    }

    /// 从书架删除书籍（同时清除章节缓存）
    func deleteBook(_ book: Book) async {
        try? await db.deleteBook(book)
        books.removeAll { $0.bookUrl == book.bookUrl }
    }
}
