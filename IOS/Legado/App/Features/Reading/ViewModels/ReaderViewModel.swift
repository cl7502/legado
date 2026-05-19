import SwiftUI
import Combine

/// 阅读器核心业务逻辑
@MainActor
class ReaderViewModel: ObservableObject {
    @Published var book: Book
    @Published var chapters: [Chapter] = []
    @Published var currentContent: String = "正在加载内容..."
    @Published var isLoading = false
    @Published var showingMenu = false
    
    // 进度信息
    @Published var currentChapterIndex: Int
    
    private let db = DatabaseManager.shared
    private let network = NetworkManager.shared
    private let contentParser = BookContentParser.shared
    
    init(book: Book) {
        self.book = book
        self.currentChapterIndex = book.durChapterIndex
    }
    
    /// 初始化加载
    func setup() async {
        await loadChapters()
        await loadCurrentChapter()
    }
    
    /// 加载目录
    private func loadChapters() async {
        do {
            self.chapters = try await db.getChapters(for: book.bookUrl)
            
            // 如果本地没有目录，则需要从书源抓取 (此处暂略，阶段 8 深度整合时补全)
            if chapters.isEmpty {
                print("⚠️ [Reader]: Local TOC empty, fetching from source...")
            }
        } catch {
            print("❌ [Reader Error]: Failed to load chapters: \(error)")
        }
    }
    
    /// 加载当前章节内容
    func loadCurrentChapter() async {
        guard currentChapterIndex < chapters.count else { return }
        let chapter = chapters[currentChapterIndex]
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            // 1. 获取书源
            let sources = try await db.getAllBookSources()
            guard let source = sources.first(where: { $0.bookSourceUrl == book.origin }) else {
                self.currentContent = "未找到关联书源"
                return
            }
            
            // 2. 发起请求
            var context = AnalyzeContext(source: source, baseUrl: chapter.url)
            let html = try await network.request(chapter.url, source: source, context: &context)
            
            // 3. 解析并净化
            let content = contentParser.parseContent(
                html,
                rule: source.ruleContent ?? "",
                context: &context,
                replaceRules: [] // TODO: 注入全局净化规则
            )
            
            self.currentContent = content
            
            // 4. 同步进度到数据库
            await syncProgress(chapter: chapter)
            
            // 5. 预加载下一章
            prefetchNextChapter()
            
        } catch {
            self.currentContent = "加载失败: \(error.localizedDescription)"
        }
    }
    
    /// 同步进度
    private func syncProgress(chapter: Chapter) async {
        var updatedBook = book
        updatedBook.durChapterIndex = currentChapterIndex
        updatedBook.durChapterTitle = chapter.title
        updatedBook.durChapterTime = Int64(Date().timeIntervalSince1970)
        
        self.book = updatedBook
        try? await db.saveBook(updatedBook)
    }
    
    /// 预加载 (GSD 强化：异步后台任务)
    private func prefetchNextChapter() {
        let nextIndex = currentChapterIndex + 1
        guard nextIndex < chapters.count else { return }
        
        Task.detached(priority: .background) {
            // 预取逻辑... (阶段 6 补砖后的后台任务集成)
        }
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
