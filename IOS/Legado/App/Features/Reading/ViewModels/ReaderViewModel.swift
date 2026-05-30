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
    /// 每页在完整章节文本中的起始字符偏移（用于高亮定位）
    @Published var currentPageOffsets: [Int] = []
    /// 当前章节内的页码（0-based）
    @Published var currentPageIndex: Int = 0
    /// 当前章节的高亮列表
    @Published var currentHighlights: [BookHighlight] = []

    // 预缓存 Task 追踪：切章时取消旧 Task，当前章节优先
    private var prefetchTasks: [Int: Task<Void, Never>] = [:]

    private let db = DatabaseManager.shared
    private let network = NetworkManager.shared
    private let ruleExecutor = RuleExecutor.shared
    private let contentParser = BookContentParser.shared
    let ttsManager = TTSManager.shared
    private var cancellables = Set<AnyCancellable>()

    init(book: Book) {
        self.book = book
        self.currentChapterIndex = book.durChapterIndex
        subscribeToTTSSpeakingRange()
    }

    // TTS 朗读推进时自动翻页
    private func subscribeToTTSSpeakingRange() {
        ttsManager.$speakingRange
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] range in
                guard let self, self.isTTSEnabled else { return }
                let speakEnd = range.location + range.length
                for (idx, pageStart) in self.currentPageOffsets.enumerated() {
                    let pageEnd = idx + 1 < self.currentPageOffsets.count
                        ? self.currentPageOffsets[idx + 1]
                        : Int.max
                    if pageStart <= speakEnd && speakEnd <= pageEnd {
                        if self.currentPageIndex != idx { self.currentPageIndex = idx }
                        break
                    }
                }
            }
            .store(in: &cancellables)
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

    /// 停止朗读（用于朗读面板"退出朗读"按钮）
    func stopTTS() {
        ttsManager.stop()
        isTTSEnabled = false
    }

    /// 切换书源后重新加载目录和章节内容，保留当前章节索引
    /// 若换源后目录为空则回滚到原书源（CR-04）
    func changeSource(to source: BookSource) async {
        let savedChapterIndex = currentChapterIndex
        let savedOrigin = book.origin
        let savedOriginName = book.originName

        book.origin = source.bookSourceUrl
        book.originName = source.bookSourceName
        try? await DatabaseManager.shared.saveBook(book)

        chapterContents.removeAll()
        currentPages = []
        currentPageOffsets = []
        currentPageIndex = 0
        currentHighlights = []
        await loadChapters()

        guard !chapters.isEmpty else {
            // 换源失败，回滚到原书源
            book.origin = savedOrigin
            book.originName = savedOriginName
            try? await DatabaseManager.shared.saveBook(book)
            await loadChapters()
            return
        }
        let target = max(0, min(savedChapterIndex, chapters.count - 1))
        jumpToChapter(target)
    }
    
    func startTTS() {
        guard let rawContent = chapterContents[currentChapterIndex],
              currentChapterIndex < chapters.count else { return }
        isTTSEnabled = true

        // 与分页器保持相同的文本规范化，确保 speakingRange 偏移和 pageStartOffset 对齐
        let normalizedContent = rawContent.replacingOccurrences(of: "\n\n", with: "\n")
        let title = chapters[currentChapterIndex].title

        ttsManager.speak(normalizedContent, bookName: book.name, chapterTitle: title) { [weak self] in
            guard let self, self.isTTSEnabled else { return }  // 已停止则不连读
            self.nextChapterOnly()
            self.startTTS()
        }
    }
    
    /// setup() 完成后设为 true，区分"正在加载"与"加载失败"
    @Published var setupDone = false

    func setup() async {
        isLoading = true
        defer { isLoading = false; setupDone = true }
        await loadChapters()
        if !chapters.isEmpty {
            await loadChapterContent(at: currentChapterIndex)
            prefetch(around: currentChapterIndex)  // fire-and-forget，不阻塞
        }
    }

    // MARK: - 目录加载

    func loadChapters() async {
        do {
            // 1. 优先从数据库读缓存
            let cached = try await db.getChapters(for: book.bookUrl)
            if !cached.isEmpty {
                // 检测章节 URL 是否存在明显的空参数（如 bookId=&），若有则强制重新加载
                let hasBrokenUrl = cached.contains { ch in
                    ch.url.contains("bookId=&") || ch.url.contains("bookId= &")
                }
                if !hasBrokenUrl {
                    self.chapters = cached
                    return
                }
                print("⚠️ [loadChapters] 检测到章节 URL 中 bookId 为空，强制重新加载目录")
            }

            // 2. 缓存为空 — 先刷新 BookInfo 以执行 ruleBookInfoInit 并获取最新 tocUrl (ISSUE-021)
            //    对标 Android WebBook.getChapterListAwait() 前置 getBookInfoAwait() 步骤
            let sources = try await db.getAllBookSources()
            guard let source = sources.first(where: { $0.bookSourceUrl == book.origin }) else { return }

            if source.ruleBookInfoInit != nil || source.ruleTocUrl != nil {
                await refreshBookInfoForChapters(source: source)
            }

            // 3. 通过书源抓取目录
            // Android convention: if tocUrl is absent, the book detail page is also the TOC page.
            // Covers books saved before the loadDetails() tocUrl-fallback fix was applied.
            var effectiveTocUrl: String
            if let tocUrl = book.tocUrl, !tocUrl.isEmpty {
                effectiveTocUrl = tocUrl
            } else if !book.bookUrl.isEmpty {
                effectiveTocUrl = book.bookUrl
                book.tocUrl = book.bookUrl
            } else {
                return
            }

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
            context.result = html

            // 将 tocUrl 和 bookUrl 的 URL 参数注入 context.variables（大小写均存），
            // 使 ruleChapterUrl 中的 @get:{bookid} 等变量引用能正确取值
            for urlStr in [effectiveTocUrl, book.bookUrl] {
                if let comps = URLComponents(string: urlStr) {
                    for item in comps.queryItems ?? [] {
                        let v = item.value ?? ""
                        context.variables[item.name]            = v   // 原始大小写
                        context.variables[item.name.lowercased()] = v // 全小写兼容
                    }
                }
            }
            // 同时存入 bookId 的常见别名，供不同书源使用
            if let bId = (context.variables["bookId"] ?? context.variables["bookid"]) as? String, !bId.isEmpty {
                context.variables["bookId"]  = bId
                context.variables["bookid"]  = bId
                context.variables["book_id"] = bId
            }

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
                    fetched.append(Chapter(url: rawUrl, title: title, index: idx, bookUrl: book.bookUrl))
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

            // 持久化章节列表，同步更新 totalChapterNum 避免书架显示异常百分比
            if !fetched.isEmpty {
                try await db.saveChapters(fetched, for: book.bookUrl)
                var updatedBook = book
                updatedBook.totalChapterNum = fetched.count
                self.book = updatedBook
                try? await db.saveBook(updatedBook)
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

    /// Refresh BookInfo page before loading chapters.
    /// Mirrors Android WebBook.getBookInfoAwait() — executes ruleBookInfoInit to set
    /// document root, then refreshes tocUrl so dynamic URLs are not stale.
    private func refreshBookInfoForChapters(source: BookSource) async {
        do {
            let html = try await network.request(book.bookUrl, source: source)
            var context = AnalyzeContext(source: source, baseUrl: book.bookUrl)
            context.result = html

            // ruleBookInfoInit: use result as new content root if non-empty.
            // Many sources use "$.data" here to shift the root for subsequent rules.
            if let initRule = source.ruleBookInfoInit, !initRule.isEmpty {
                if let newRoot = ruleExecutor.execute(initRule, in: &context), !newRoot.isEmpty {
                    context.result = newRoot
                }
            }

            // Refresh tocUrl from detail page
            if let tocRaw = ruleExecutor.execute(source.ruleTocUrl ?? "", in: &context),
               !tocRaw.isEmpty {
                let resolved = resolveUrl(tocRaw, base: book.bookUrl)
                if resolved != book.tocUrl {
                    book.tocUrl = resolved
                    // 持久化到 DB，防止冷启动后再次从旧值读取
                    try? await db.saveBook(book)
                    print("🔗 [loadChapters] tocUrl 已更新并持久化: \(resolved)")
                }
            }
        } catch {
            print("⚠️ [refreshBookInfo]: \(error.localizedDescription)")
        }
    }
    
    func loadChapterContent(at index: Int) async {
        guard index < chapters.count else { return }

        // 内存命中 — 最快路径
        if chapterContents[index] != nil {
            if index == currentChapterIndex && currentPages.isEmpty {
                paginateCurrentChapter()
            }
            return
        }

        let chapter = chapters[index]

        // DB 缓存命中 — 跳过网络请求
        if let cached = await db.getChapterContent(url: chapter.url), !cached.isEmpty {
            chapterContents[index] = cached
            if index == currentChapterIndex {
                paginateCurrentChapter()
                await syncProgress(chapter: chapter)
            }
            return
        }

        // 指数退避重试：最多 3 次，延迟 1s/2s
        let maxAttempts = 3
        var lastError: Error? = nil
        for attempt in 0..<maxAttempts {
            if attempt > 0 {
                try? await Task.sleep(nanoseconds: UInt64(1_000_000_000) << (attempt - 1))
                // 重试前检查是否已被别的路径填充（如跳章节时的直接加载）
                if chapterContents[index] != nil { return }
            }
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

            // 持久化到 DB，下次进入直接从 DB 读取，跳过网络请求
            await db.saveChapterContent(content, for: chapter.url)

            // 内容加载完成后立即分页，不等 SwiftUI onChange 触发
            if index == currentChapterIndex {
                paginateCurrentChapter()
                await syncProgress(chapter: chapter)
            }
            return  // 成功，退出重试循环
        } catch {
            lastError = error
            // 当前章节加载失败时给用户看提示，但仍会重试
            if index == currentChapterIndex && currentPages.isEmpty {
                self.chapterContents[index] = "加载失败（第\(attempt + 1)次），重试中..."
                paginateCurrentChapter()
            }
        }
    }  // end retry loop

    // 所有重试耗尽
    self.chapterContents[index] = "加载失败: \(lastError?.localizedDescription ?? "未知错误")"
    if index == currentChapterIndex && currentPages.isEmpty {
        paginateCurrentChapter()
    }
}
    
    // 预缓存：取消旧 Task，按优先级（近章优先）重新调度
    private func prefetch(around index: Int) {
        let count = ReaderSettings.shared.prefetchCount
        guard count > 0 else { return }
        let start = index + 1
        let end   = min(start + count - 1, chapters.count - 1)
        guard start <= end else { return }
        for i in start...end {
            guard prefetchTasks[i] == nil else { continue }  // 已有 Task 则不重复
            let task = Task(priority: .background) { [weak self] in
                await self?.loadChapterContent(at: i)
                await MainActor.run { [weak self] in
                    self?.prefetchTasks.removeValue(forKey: i)
                }
            }
            prefetchTasks[i] = task
        }
    }

    /// 切章时取消所有预缓存 Task，当前章节优先加载
    private func cancelPrefetchTasks() {
        prefetchTasks.values.forEach { $0.cancel() }
        prefetchTasks.removeAll()
    }

    func prefetchNextChapter() {
        prefetch(around: currentChapterIndex)
    }

    // F2: 刷新当前章节（清除缓存重新拉取）
    func refreshCurrentChapter() async {
        chapterContents.removeValue(forKey: currentChapterIndex)
        currentPages = []
        await loadChapterContent(at: currentChapterIndex)
    }

    // F2: 缓存全本（后台下载全部章节，已有的也重新拉取）
    @Published var isCachingAll = false
    @Published var cacheProgress: Double = 0  // 0.0~1.0

    func cacheAllChapters() {
        guard !isCachingAll, !chapters.isEmpty else { return }
        isCachingAll = true
        cacheProgress = 0
        chapterContents.removeAll()  // 清空已有缓存，全量重新下载
        Task.detached(priority: .background) { [weak self] in
            guard let self else { return }
            let total = await self.chapters.count
            for i in 0..<total {
                await self.loadChapterContent(at: i)
                await MainActor.run {
                    self.cacheProgress = Double(i + 1) / Double(total)
                }
            }
            await MainActor.run {
                self.isCachingAll = false
                self.cacheProgress = 1.0
            }
        }
    }
    
    private func syncProgress(chapter: Chapter) async {
        var updatedBook = book
        updatedBook.durChapterIndex = currentChapterIndex
        updatedBook.durChapterPos   = currentPageIndex      // 保存当前页码
        updatedBook.durChapterTitle = chapter.title
        updatedBook.durChapterTime  = Int64(Date().timeIntervalSince1970)
        self.book = updatedBook
        try? await db.saveBook(updatedBook)
    }

    /// 翻页时轻量保存页码进度（不更新 title/time，减少 DB 写入频率）
    private func savePageProgress() {
        var updatedBook = book
        updatedBook.durChapterIndex = currentChapterIndex
        updatedBook.durChapterPos   = currentPageIndex
        self.book = updatedBook
        Task { try? await db.saveBook(updatedBook) }
    }
    
    // MARK: - 章节内分页

    /// 对当前章节执行分页，结果写入 currentPages / currentPageIndex。
    /// 从 UIScreen.main.bounds 自行计算可用尺寸，不依赖 SwiftUI geometry。
    func paginateCurrentChapter() {
        guard let content = chapterContents[currentChapterIndex],
              currentChapterIndex < chapters.count else { return }

        let settings = ReaderSettings.shared
        let screenSize = UIScreen.main.bounds.size

        let font = UIFont.systemFont(ofSize: settings.fontSize)
        let horizontalPadding = settings.sideMargin * 2
        // 减去 header/footer 高度、上下内边距；
        // 14pt 安全余量：CoreText（分页）与 TextKit 2（渲染）段尾 paragraphSpacing 计算不一致，
        // 差值 ≈ paragraphSpacing(12) + 行高细微误差(~2) = 14pt
        let verticalPadding   = settings.topMargin + settings.bottomMargin
                              + ReaderLayout.headerH + ReaderLayout.footerH + 14
        let usableSize = CGSize(
            width:  max(screenSize.width  - horizontalPadding, 100),
            height: max(screenSize.height - verticalPadding,   100)
        )

        let paginator = ChapterPaginator(
            pageSize: usableSize,
            font: font,
            lineSpacing: settings.lineSpacing,
            letterSpacing: settings.letterSpacing,
            paragraphSpacing: settings.paragraphSpacing  // 同步传入，与渲染保持一致
        )
        let title = chapters[currentChapterIndex].title
        // \n\n 产生的空行高度 = lineHeight + lineSpacing，随字号同比放大，
        // 大字号下每页被空行占用大量空间。统一替换为 \n，
        // 段间距由 paragraphSpacing 独立控制，与字号无关
        let processedContent = content.replacingOccurrences(of: "\n\n", with: "\n")
        let pages = paginator.paginate(text: processedContent, chapterTitle: title)

        currentPages = pages
        // 计算每页在 processedContent 中的起始字符偏移
        var offset = 0
        currentPageOffsets = pages.map { page in
            let start = offset
            offset += (page as NSString).length
            return start
        }
        // 恢复上次阅读位置：初次打开时 durChapterPos 存储上次页码
        let savedPage = book.durChapterPos
        if savedPage > 0 && savedPage < pages.count {
            currentPageIndex = savedPage
        } else {
            currentPageIndex = 0
        }
        // 异步加载当前章节高亮
        Task { await loadHighlights() }
    }

    // MARK: - 高亮操作

    func loadHighlights() async {
        currentHighlights = (try? await db.getHighlights(
            bookUrl: book.bookUrl, chapterIndex: currentChapterIndex)) ?? []
    }

    func addHighlight(pageIndex: Int, pageLocalStart: Int, pageLocalEnd: Int,
                      selectedText: String, color: Int = 0) async {
        guard pageIndex < currentPageOffsets.count else { return }
        let pageOffset = currentPageOffsets[pageIndex]
        let h = BookHighlight(
            bookUrl:      book.bookUrl,
            chapterIndex: currentChapterIndex,
            startOffset:  pageOffset + pageLocalStart,
            endOffset:    pageOffset + pageLocalEnd,
            selectedText: selectedText,
            color:        color,
            createdAt:    Date()
        )
        try? await db.saveHighlight(h)
        await loadHighlights()
    }

    func deleteHighlight(_ highlight: BookHighlight) async {
        try? await db.deleteHighlight(highlight)
        await loadHighlights()
    }

    // MARK: - 页内翻页

    /// 翻到下一页（章节内）；章节末尾则切换下一章
    func nextPage() {
        if currentPageIndex < currentPages.count - 1 {
            currentPageIndex += 1
            savePageProgress()
        } else {
            nextChapterOnly()
        }
    }

    func prevPage() {
        if currentPageIndex > 0 {
            currentPageIndex -= 1
            savePageProgress()
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
        // 切章时 durChapterPos 重置，避免新章节恢复到错误页
        var updatedBook = book; updatedBook.durChapterPos = 0; self.book = updatedBook
        Task {
            await loadChapterContent(at: currentChapterIndex)
            prefetch(around: currentChapterIndex)
        }
    }

    private func prevChapterOnly() {
        guard currentChapterIndex > 0 else { return }
        currentChapterIndex -= 1
        currentPageIndex = 0
        currentPages = []
        var updatedBook = book; updatedBook.durChapterPos = 0; self.book = updatedBook
        Task {
            await loadChapterContent(at: currentChapterIndex)
            prefetch(around: currentChapterIndex)
        }
    }

    func jumpToChapter(_ index: Int, keepMenuOpen: Bool = false) {
        cancelPrefetchTasks()  // 取消旧预缓存，当前章节优先
        currentChapterIndex = index
        currentPageIndex = 0
        currentPages = []
        if !keepMenuOpen { showingMenu = false }
        var updatedBook = book; updatedBook.durChapterPos = 0; self.book = updatedBook
        Task {
            await loadChapterContent(at: currentChapterIndex)
            prefetch(around: currentChapterIndex)
        }
    }
}
