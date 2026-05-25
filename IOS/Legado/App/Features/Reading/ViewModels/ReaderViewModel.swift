import SwiftUI
import Combine
import UIKit

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

    // MARK: - 章节内分页
    /// 当前章节分割出的物理页内容列表（按页索引排列）
    @Published var currentPages: [String] = []
    /// 当前章节内的页码（0-based）
    @Published var currentPageIndex: Int = 0
    
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
            // 连读逻辑：章节结束自动切到下一章（不是下一页）
            self?.nextChapterOnly()
            self?.startTTS()
        }
    }
    
    func setup() async {
        isLoading = true
        defer { isLoading = false }
        await loadChapters()
        if !chapters.isEmpty {
            await loadChapterContent(at: currentChapterIndex)
            await prefetch(around: currentChapterIndex)
        }
    }

    // MARK: - 目录加载

    func loadChapters() async {
        do {
            // 1. 优先从数据库读缓存
            let cached = try await db.getChapters(for: book.bookUrl)
            if !cached.isEmpty {
                self.chapters = cached
                return
            }

            // 2. 缓存为空 — 先刷新 BookInfo 以执行 ruleBookInfoInit 并获取最新 tocUrl (ISSUE-021)
            //    对标 Android WebBook.getChapterListAwait() 前置 getBookInfoAwait() 步骤
            let sources = try await db.getAllBookSources()
            guard let source = sources.first(where: { $0.bookSourceUrl == book.origin }) else { return }

            if source.ruleBookInfoInit != nil || source.ruleTocUrl != nil {
                await refreshBookInfoForChapters(source: source)
            }

            // 3. 通过书源抓取目录
            guard let tocUrl = book.tocUrl, !tocUrl.isEmpty else { return }
            var effectiveTocUrl = tocUrl

            // preUpdateJs — execute before TOC fetch; result (if HTTP URL) replaces tocUrl
            // mirrors Android BookChapterList.runPreUpdateJs() L211-223
            if let preUpdateJs = source.ruleTocPreUpdateJs, !preUpdateJs.isEmpty {
                var jsCtx = AnalyzeContext(source: source, baseUrl: effectiveTocUrl)
                jsCtx.book = book
                if let newUrl = ruleExecutor.execute(preUpdateJs, in: &jsCtx),
                   !newUrl.isEmpty, newUrl != effectiveTocUrl {
                    effectiveTocUrl = newUrl
                    book.tocUrl = newUrl
                }
            }

            var context = AnalyzeContext(source: source, baseUrl: effectiveTocUrl)
            context.book = book
            let html = try await network.request(effectiveTocUrl, source: source)
            let html = try await network.request(effectiveTocUrl, source: source)
            context.result = html

            let listRule = source.ruleTocList ?? ""
            guard !listRule.isEmpty else { return }
            let items = ruleExecutor.executeList(listRule, in: &context)

            var fetched: [Chapter] = []

            // 内部工具：将一批列表项追加到 fetched
            func appendChapterItems(_ listItems: [String], baseCtx: AnalyzeContext, pageBaseUrl: String) {
                for (_, item) in listItems.enumerated() {
                    var ctx = baseCtx
                    ctx.result = item
                    let idx = fetched.count
                    let title = ruleExecutor.execute(source.ruleChapterName ?? "", in: &ctx)
                                ?? "第\(idx + 1)章"
                    var rawUrl = ruleExecutor.execute(source.ruleChapterUrl ?? "", in: &ctx) ?? ""
                    rawUrl = resolveUrl(rawUrl, base: pageBaseUrl)
                    fetched.append(Chapter(
                        url: rawUrl, title: title, index: idx,
                        bookUrl: book.bookUrl
                    ))
                }
            }

            // 第一页
            appendChapterItems(items, baseCtx: context, pageBaseUrl: effectiveTocUrl)

            // P1-A: 循环抓取目录后续页 (ruleTocNextUrl)
            if let nextUrlRule = source.ruleTocNextUrl, !nextUrlRule.isEmpty {
                var visitedUrls = Set<String>([effectiveTocUrl])
                var pageHtml = html
                var pageBaseUrl = effectiveTocUrl
                let maxTocPages = 50

                for _ in 0..<maxTocPages {
                    var pageCtx = AnalyzeContext(source: source, baseUrl: pageBaseUrl)
                    pageCtx.result = pageHtml
                    guard let rawNext = ruleExecutor.execute(nextUrlRule, in: &pageCtx),
                          !rawNext.isEmpty else { break }
                    let nextUrl = resolveUrl(rawNext, base: pageBaseUrl)
                    guard !nextUrl.isEmpty, !visitedUrls.contains(nextUrl) else { break }
                    visitedUrls.insert(nextUrl)

                    let nextHtml = try await network.request(nextUrl, source: source)
                    var nextCtx = AnalyzeContext(source: source, baseUrl: nextUrl)
                    nextCtx.result = nextHtml
                    let nextItems = ruleExecutor.executeList(listRule, in: &nextCtx)
                    appendChapterItems(nextItems, baseCtx: nextCtx, pageBaseUrl: nextUrl)

                    pageHtml = nextHtml
                    pageBaseUrl = nextUrl
                }
            }

            // formatJs — apply JS formatter to each chapter title
            // mirrors Android BookChapterList formatJs loop L134-151
            if let formatJs = source.ruleTocFormatJs, !formatJs.isEmpty {
                fetched = fetched.map { chapter in
                    var jsCtx = AnalyzeContext(source: source, baseUrl: chapter.url)
                    jsCtx.result = chapter.title
                    jsCtx.book = book
                    if let formatted = ruleExecutor.execute(formatJs, in: &jsCtx),
                       !formatted.isEmpty {
                        return Chapter(url: chapter.url, title: formatted,
                                       index: chapter.index, bookUrl: chapter.bookUrl)
                    }
                    return chapter
                }
            }

            // 重新连续编号（抓取多页后序号可能不连续）
            fetched = fetched.enumerated().map { idx, ch in
                Chapter(url: ch.url, title: ch.title, index: idx, bookUrl: ch.bookUrl)
            }

            self.chapters = fetched

            // 3. 持久化章节列表
            if !fetched.isEmpty {
                try await db.saveChapters(fetched, for: book.bookUrl)
            }
        } catch {
            print("❌ [loadChapters]: \(error)")
        }
    }

    private func resolveUrl(_ url: String, base: String) -> String {
        if url.hasPrefix("http") { return url }
        guard let baseURL = URL(string: base),
              let resolved = URL(string: url, relativeTo: baseURL)
        else { return url }
        return resolved.absoluteString
    }

    /// ISSUE-021: Refresh BookInfo page before loading chapters.
    /// Mirrors Android WebBook.getBookInfoAwait() — executes ruleBookInfoInit (side-effect JS)
    /// and refreshes tocUrl from the book detail page so that dynamic URLs are not stale.
    private func refreshBookInfoForChapters(source: BookSource) async {
        do {
            var context = AnalyzeContext(source: source, baseUrl: book.bookUrl)

            // Execute ruleBookInfoInit (side-effect only — sets variables/cookies)
            if let initRule = source.ruleBookInfoInit, !initRule.isEmpty {
                var initCtx = context
                _ = ruleExecutor.execute(initRule, in: &initCtx)
                context.variables = initCtx.variables
            }

            let html = try await network.request(book.bookUrl, source: source)
            context.result = html

            // Refresh tocUrl from detail page
            if let tocRaw = ruleExecutor.execute(source.ruleTocUrl ?? "", in: &context),
               !tocRaw.isEmpty {
                let resolved = resolveUrl(tocRaw, base: book.bookUrl)
                book.tocUrl = resolved
            }
        } catch {
            print("⚠️ [refreshBookInfo]: \(error.localizedDescription)")
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
            var content = contentParser.parseContent(
                html,
                rule: source.ruleContent ?? "",
                context: &context,
                replaceRules: replaceRules
            )

            // P1-B: 循环抓取正文后续页 (ruleContentNextUrl)
            if let nextUrlRule = source.ruleContentNextUrl, !nextUrlRule.isEmpty {
                var visitedUrls = Set<String>([chapter.url])
                var pageHtml = html
                var pageBaseUrl = chapter.url
                let maxContentPages = 20

                for _ in 0..<maxContentPages {
                    var pageCtx = AnalyzeContext(source: source, baseUrl: pageBaseUrl)
                    pageCtx.result = pageHtml
                    guard let rawNext = ruleExecutor.execute(nextUrlRule, in: &pageCtx),
                          !rawNext.isEmpty else { break }
                    let nextUrl = resolveUrl(rawNext, base: pageBaseUrl)
                    guard !nextUrl.isEmpty, !visitedUrls.contains(nextUrl) else { break }
                    visitedUrls.insert(nextUrl)

                    let nextHtml = try await network.request(nextUrl, source: source)
                    var nextCtx = AnalyzeContext(source: source, baseUrl: nextUrl)
                    let nextContent = contentParser.parseContent(
                        nextHtml,
                        rule: source.ruleContent ?? "",
                        context: &nextCtx,
                        replaceRules: replaceRules
                    )
                    content += "\n" + nextContent

                    pageHtml = nextHtml
                    pageBaseUrl = nextUrl
                }
            }

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
    
    // MARK: - 章节内分页

    /// 对当前章节执行分页，结果写入 currentPages / currentPageIndex。
    /// 应在章节内容加载完成后，从 ReaderView 传入屏幕可用尺寸后调用。
    func paginateCurrentChapter(screenSize: CGSize, settings: ReaderSettings) {
        guard let content = chapterContents[currentChapterIndex],
              currentChapterIndex < chapters.count else { return }

        let font = UIFont.systemFont(ofSize: settings.fontSize)
        let horizontalPadding = settings.sideMargin * 2
        let verticalPadding: CGFloat = 80 // top 40 + bottom 40
        let usableSize = CGSize(
            width: max(screenSize.width - horizontalPadding, 100),
            height: max(screenSize.height - verticalPadding, 100)
        )

        let paginator = ChapterPaginator(
            pageSize: usableSize,
            font: font,
            lineSpacing: settings.lineSpacing
        )
        let title = chapters[currentChapterIndex].title
        let pages = paginator.paginate(text: content, chapterTitle: title)

        currentPages = pages
        currentPageIndex = 0
    }

    // MARK: - 页内翻页

    /// 翻到下一页（章节内）；章节末尾则切换下一章
    func nextPage() {
        if currentPageIndex < currentPages.count - 1 {
            currentPageIndex += 1
        } else {
            // 章节末 → 切到下一章，分页在 ReaderView 侧监听到内容变化后重新触发
            nextChapterOnly()
        }
    }

    /// 翻到上一页（章节内）；章节首页则切换上一章
    func prevPage() {
        if currentPageIndex > 0 {
            currentPageIndex -= 1
        } else {
            prevChapterOnly()
        }
    }

    // MARK: - 交互接口

    /// 章节级别前进（跳过章节内分页，保留供外部菜单跳章用）
    func nextChapter() {
        if currentPageIndex < currentPages.count - 1 {
            currentPageIndex += 1
            return
        }
        nextChapterOnly()
    }

    func prevChapter() {
        if currentPageIndex > 0 {
            currentPageIndex -= 1
            return
        }
        prevChapterOnly()
    }

    func nextChapterOnly() {
        guard currentChapterIndex < chapters.count - 1 else { return }
        currentChapterIndex += 1
        currentPageIndex = 0
        currentPages = []
        Task {
            await loadChapterContent(at: currentChapterIndex)
            await prefetch(around: currentChapterIndex)
        }
    }

    private func prevChapterOnly() {
        guard currentChapterIndex > 0 else { return }
        currentChapterIndex -= 1
        currentPageIndex = 0
        currentPages = []
        Task { await loadChapterContent(at: currentChapterIndex) }
    }

    func jumpToChapter(_ index: Int) {
        currentChapterIndex = index
        currentPageIndex = 0
        currentPages = []
        showingMenu = false
        Task {
            await loadChapterContent(at: currentChapterIndex)
            await prefetch(around: currentChapterIndex)
        }
    }
}
