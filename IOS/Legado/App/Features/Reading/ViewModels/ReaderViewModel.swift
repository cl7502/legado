import SwiftUI
import Combine

/// 阅读器核心业务逻辑 (V2.0 完美整合版)
@MainActor
class ReaderViewModel: ObservableObject {
    @Published var book: Book
    @Published var chapters: [Chapter] = []
    @Published var chapterContents: [Int: String] = [:] // index -> content
    @Published var isLoading = false
    @Published var showingMenu = false
    @Published var isTTSEnabled = false
    
    @Published var currentChapterIndex: Int
    
    private let db = DatabaseManager.shared
    private let network = NetworkManager.shared
    private let ruleExecutor = RuleExecutor.shared
    private let contentParser = BookContentParser.shared
    private let ttsManager = TTSManager.shared
    
    init(book: Book) {
        self.book = book
        self.currentChapterIndex = book.durChapterIndex
    }
    
    // MARK: - TTS 控制
    
    func toggleTTS() {
        if isTTSEnabled {
            ttsManager.stop()
            isTTSEnabled = false
        } else {
            startTTS()
        }
    }
    
    func startTTS() {
        guard let content = chapterContents[currentChapterIndex] else { return }
        isTTSEnabled = true
        
        ttsManager.speak(content, bookName: book.name, chapterTitle: chapters[currentChapterIndex].title) { [weak self] in
            // 连读逻辑：章节结束自动下一章
            self?.nextChapter()
            self?.startTTS()
        }
    }
    
    func setup() async {
        await loadChapters()
        if !chapters.isEmpty {
            await loadChapterContent(at: currentChapterIndex)
            // 预加载
            await prefetch(around: currentChapterIndex)
        }
    }
    
    func loadChapterContent(at index: Int) async {
        guard index < chapters.count else { return }
        if chapterContents[index] != nil { return } // 已加载
        
        let chapter = chapters[index]
        
        do {
            let sources = try await db.getAllBookSources()
            guard let source = sources.first(where: { $0.bookSourceUrl == book.origin }) else { return }
            
            var context = AnalyzeContext(source: source, baseUrl: chapter.url)
            let html = try await network.request(chapter.url, source: source)
            
            let replaceRules = try await db.getReplaceRules()
            let content = contentParser.parseContent(
                html,
                rule: source.ruleContent ?? "",
                context: &context,
                replaceRules: replaceRules
            )
            
            self.chapterContents[index] = content
            
            if index == currentChapterIndex {
                await syncProgress(chapter: chapter)
            }
        } catch {
            self.chapterContents[index] = "加载失败: \(error.localizedDescription)"
        }
    }
    
    private func prefetch(around index: Int) async {
        let nextIndex = index + 1
        if nextIndex < chapters.count {
            await loadChapterContent(at: nextIndex)
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
        Task { 
            await loadChapterContent(at: currentChapterIndex) 
            await prefetch(around: currentChapterIndex)
        }
    }
    
    func prevChapter() {
        guard currentChapterIndex > 0 else { return }
        currentChapterIndex -= 1
        Task { await loadChapterContent(at: currentChapterIndex) }
    }
    
    func jumpToChapter(_ index: Int) {
        currentChapterIndex = index
        showingMenu = false
        Task { 
            await loadChapterContent(at: currentChapterIndex)
            await prefetch(around: currentChapterIndex)
        }
    }
}
