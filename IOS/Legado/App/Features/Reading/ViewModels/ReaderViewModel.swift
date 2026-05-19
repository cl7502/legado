import SwiftUI
import Combine

/// 阅读器核心业务逻辑 (V2.0 完美整合版)
@MainActor
class ReaderViewModel: ObservableObject {
    @Published var book: Book
    @Published var chapters: [Chapter] = []
    @Published var currentContent: String = "正在加载内容..."
    @Published var isLoading = false
    @Published var showingMenu = false
    
    @Published var currentChapterIndex: Int
    
    private let db = DatabaseManager.shared
    private let network = NetworkManager.shared
    private let ruleExecutor = RuleExecutor.shared
    private let contentParser = BookContentParser.shared
    
    init(book: Book) {
        self.book = book
        self.currentChapterIndex = book.durChapterIndex
    }
    
    func setup() async {
        await loadChapters()
        if !chapters.isEmpty {
            await loadCurrentChapter()
        }
    }
    
    /// 加载目录 (支持从网络抓取)
    private func loadChapters() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            // 1. 先查本地
            let localChapters = try await db.getChapters(for: book.bookUrl)
            if !localChapters.isEmpty {
                self.chapters = localChapters
                return
            }
            
            // 2. 本地没有，从网络抓取
            print("🌐 [Reader]: Fetching TOC from network...")
            let sources = try await db.getAllBookSources()
            guard let source = sources.first(where: { $0.bookSourceUrl == book.origin }) else { return }
            
            // 使用 tocUrl 或 bookUrl 作为目录页
            let tocUrl = book.tocUrl ?? book.bookUrl
            var context = AnalyzeContext(source: source, baseUrl: tocUrl)
            let html = try await network.request(tocUrl, source: source)
            context.result = html
            
            // 执行目录列表规则
            if let listRule = source.ruleTocList {
                let items = ruleExecutor.executeList(listRule, in: &context)
                var newChapters: [Chapter] = []
                
                for (index, item) in items.enumerated() {
                    var itemContext = context
                    itemContext.result = item
                    
                    let title = ruleExecutor.execute(source.ruleChapterName ?? "", in: &itemContext) ?? "第\(index + 1)章"
                    let url = ruleExecutor.execute(source.ruleChapterUrl ?? "", in: &itemContext) ?? tocUrl
                    
                    newChapters.append(Chapter(
                        url: url,
                        title: title,
                        index: index,
                        bookUrl: book.bookUrl
                    ))
                }
                
                // 3. 持久化并更新 UI
                try await db.saveChapters(newChapters, for: book.bookUrl)
                self.chapters = newChapters
            }
        } catch {
            print("❌ [Reader Error]: Failed to fetch TOC: \(error)")
        }
    }
    
    func loadCurrentChapter() async {
        guard currentChapterIndex < chapters.count else { return }
        let chapter = chapters[currentChapterIndex]
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            let sources = try await db.getAllBookSources()
            guard let source = sources.first(where: { $0.bookSourceUrl == book.origin }) else {
                self.currentContent = "未找到关联书源"
                return
            }
            
            var context = AnalyzeContext(source: source, baseUrl: chapter.url)
            let html = try await network.request(chapter.url, source: source)
            
            let content = contentParser.parseContent(
                html,
                rule: source.ruleContent ?? "",
                context: &context,
                replaceRules: []
            )
            
            self.currentContent = content
            await syncProgress(chapter: chapter)
            
        } catch {
            self.currentContent = "加载失败: \(error.localizedDescription)"
        }
    }
    
    private func syncProgress(chapter: Chapter) async {
        var updatedBook = book
        updatedBook.durChapterIndex = currentChapterIndex
        updatedBook.durChapterTitle = chapter.title
        updatedBook.durChapterTime = Int64(Date().timeIntervalSince1970)
        self.book = updatedBook
        try? await db.saveBook(updatedBook)
    }
    
    // MARK: - 交互接口
    func nextChapter() {
        guard currentChapterIndex < chapters.count - 1 else { return }
        currentChapterIndex += 1
        Task { await loadCurrentChapter() }
    }
    
    func prevChapter() {
        guard currentChapterIndex > 0 else { return }
        currentChapterIndex -= 1
        Task { await loadCurrentChapter() }
    }
    
    func jumpToChapter(_ index: Int) {
        currentChapterIndex = index
        showingMenu = false
        Task { await loadCurrentChapter() }
    }
}
