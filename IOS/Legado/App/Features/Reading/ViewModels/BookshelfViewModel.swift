import SwiftUI
import Combine

/// 书架业务逻辑
@MainActor
class BookshelfViewModel: ObservableObject {
    @Published var books: [Book] = []
    @Published var isLoading = false
    
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
}
