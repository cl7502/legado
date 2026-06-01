import SwiftUI
import UIKit
import AVFoundation
import MediaPlayer
import SafariServices

// MARK: - ReaderLayout（全局布局常量，ViewModel 分页器也使用）

enum ReaderLayout {
    /// Header 栏固定高度（含上下内边距）
    static let headerH: CGFloat = 28
    /// Footer 栏固定高度（含上下内边距）
    static let footerH: CGFloat = 22
}

// MARK: - ReaderView

struct ReaderView: View {
    @StateObject var viewModel: ReaderViewModel
    @StateObject var settings  = ReaderSettings.shared
    @Environment(\.dismiss) var dismiss

    // 电量和时间：从 per-page 移到 ReaderView 统一管理，避免翻页时多实例竞争
    @StateObject private var battery = BatteryMonitor.shared
    @State private var footerTime: String = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        return f.string(from: Date())
    }()
    @State private var minuteWorkItem: DispatchWorkItem? = nil

    // 音量键翻页
    @State private var volumeObservation: NSKeyValueObservation? = nil
    @State private var volumeSlider: UISlider? = nil

    // 自动翻页
    @State private var autoScrollTimer: Timer? = nil

    var body: some View {
        ZStack {
            settings.currentTheme.backgroundColor.ignoresSafeArea()

            Group {
                if viewModel.currentPages.isEmpty {
                    if viewModel.isLoading || !viewModel.setupDone {
                        loadingPlaceholder
                    } else {
                        loadFailedView
                    }
                } else if settings.pageMode == .scroll {
                    scrollModeView
                } else {
                    pageModeView
                }
            }

            // 三段式点击区已移入 pageModeView 内部，只覆盖正文区域

            // 菜单层
            if viewModel.showingMenu {
                // B6修复：透明背景捕获点击 → 关菜单
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { withAnimation { viewModel.showingMenu = false } }
                    .ignoresSafeArea()

                ReaderMenuView(viewModel: viewModel, settings: settings) {
                    dismiss()
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if viewModel.isLoading && viewModel.currentPages.isEmpty {
                ProgressView()
                    .padding(20)
                    .background(Color.black.opacity(0.5))
                    .cornerRadius(12)
                    .tint(.white)
            }
        }
        .navigationBarHidden(true)
        .statusBar(hidden: !viewModel.showingMenu)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = settings.keepScreenOn
            battery.enable()
            scheduleNextMinuteUpdate()
            setupVolumePageTurn()
            if settings.autoScrollEnabled { startAutoScroll() }
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            battery.disable()
            minuteWorkItem?.cancel()
            minuteWorkItem = nil
            teardownVolumePageTurn()
            stopAutoScroll()
        }
        // B3修复：排版设置变化 → 重新分页
        .onChange(of: settings.fontSize)          { _ in viewModel.paginateCurrentChapter() }
        .onChange(of: settings.lineSpacing)       { _ in viewModel.paginateCurrentChapter() }
        .onChange(of: settings.letterSpacing)     { _ in viewModel.paginateCurrentChapter() }
        .onChange(of: settings.paragraphSpacing)  { _ in viewModel.paginateCurrentChapter() }
        .onChange(of: settings.sideMargin)        { _ in viewModel.paginateCurrentChapter() }
        .onChange(of: settings.topMargin)         { _ in viewModel.paginateCurrentChapter() }
        .onChange(of: settings.bottomMargin)      { _ in viewModel.paginateCurrentChapter() }
        .onChange(of: settings.fontName)          { _ in viewModel.paginateCurrentChapter() }
        // 自动翻页开关/速度变化
        .onChange(of: settings.autoScrollEnabled) { enabled in
            if enabled { startAutoScroll() } else { stopAutoScroll() }
        }
        .onChange(of: settings.autoScrollInterval) { _ in
            if settings.autoScrollEnabled { startAutoScroll() }
        }
        .task { await viewModel.setup() }
    }

    // MARK: 翻页模式
    private var pageModeView: some View {
        VStack(spacing: 0) {
            // ── 固定 Header 栏（精确高度，不随页面内容变化）──────────────
            readerHeaderBar
                .frame(height: ReaderLayout.headerH)

            // ── 正文 TabView + 三段式点击区（只覆盖正文区域）──────────
            ZStack {
                TabView(selection: $viewModel.currentPageIndex) {
                    ForEach(0..<viewModel.currentPages.count, id: \.self) { idx in
                        ReaderPageView(
                            content: viewModel.currentPages[idx],
                            chapterTitle: currentChapterTitle,
                            sourceOrigin: viewModel.book.origin,
                            pageStartOffset: idx < viewModel.currentPageOffsets.count
                                ? viewModel.currentPageOffsets[idx] : 0,
                            highlights: viewModel.currentHighlights,
                            onHighlight: { localStart, localEnd, text, color in
                                Task { await viewModel.addHighlight(
                                    pageIndex: idx,
                                    pageLocalStart: localStart,
                                    pageLocalEnd: localEnd,
                                    selectedText: text,
                                    color: color
                                )}
                            },
                            isFirstPage: idx == 0
                        )
                        .tag(idx)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .onChange(of: viewModel.currentPageIndex) { newIdx in
                    if newIdx == viewModel.currentPages.count - 1 {
                        viewModel.prefetchNextChapter()
                    }
                }

                // 三段式点击区（仅在菜单隐藏时，且只覆盖正文区域）
                if !viewModel.showingMenu {
                    tapZones
                }
            }

            // ── 固定 Footer 栏（精确高度，不随页面内容变化）──────────────
            readerFooterBar
                .frame(height: ReaderLayout.footerH)
        }
        .ignoresSafeArea()
        // 音量键翻页：隐藏 MPVolumeView 抑制系统音量 HUD，同时保持视图不可见
        .background(
            settings.volumePageTurn
                ? AnyView(HiddenVolumeView(sliderRef: $volumeSlider).frame(width: 1, height: 1))
                : AnyView(EmptyView())
        )
    }

    // MARK: 固定 Header 栏
    private var readerHeaderBar: some View {
        HStack(spacing: 4) {
            Button(action: { dismiss() }) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .medium))
                    // 始终显示当前章节标题（第一页时内容区域顶部也会显示大号标题）
                    Text(currentChapterTitle.isEmpty
                         ? "第\(viewModel.currentChapterIndex + 1)章"
                         : applyTraditional(currentChapterTitle))
                        .font(.system(size: 11))
                        .lineLimit(1)
                }
                .foregroundColor(settings.currentTheme.textColor.opacity(0.5))
            }
            .buttonStyle(.plain)

            Spacer()

            if settings.showHeaderProgress, viewModel.chapters.count > 0 {
                Text("\(viewModel.currentChapterIndex + 1) / \(viewModel.chapters.count)章")
                    .font(.system(size: 11))
                    .foregroundColor(settings.currentTheme.textColor.opacity(0.5))
            }
            if settings.showHeaderBattery {
                Text("\(Int(battery.level * 100))%")
                    .font(.system(size: 11))
                    .foregroundColor(settings.currentTheme.textColor.opacity(0.5))
            }
        }
        // 圆角设备：计算 header 中线处被圆弧遮蔽的水平宽度，并留出舒适边距
        .padding(.horizontal, headerCornerAwarePad)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(settings.currentTheme.backgroundColor)
    }

    /// 圆角感知的 Header 水平内边距：确保圆角设备上内容不落入弧形遮盖区。
    /// 公式：在 y = headerH/2 处，圆角水平遮盖宽度 = r - sqrt(r² - (r - y)²)
    private var headerCornerAwarePad: CGFloat {
        let r = (UIScreen.main.value(forKey: "displayCornerRadius") as? CGFloat) ?? 0
        guard r > 1 else { return settings.sideMargin }       // 直角设备直接用 sideMargin
        let y = ReaderLayout.headerH / 2                       // header 中线距屏顶高度
        guard y < r else { return settings.sideMargin }
        let arcInset = r - sqrt(r * r - (r - y) * (r - y))   // 该高度处圆角水平遮盖量
        return max(settings.sideMargin, ceil(arcInset) + 10)  // +10pt 舒适边距
    }

    // MARK: 固定 Footer 栏（内容居中显示）
    private var readerFooterBar: some View {
        let pageLabel = viewModel.currentPageIndex < viewModel.currentPages.count
            ? "\(viewModel.currentPageIndex + 1) / \(viewModel.currentPages.count)" : ""
        return HStack(spacing: 8) {
            // 电池图标 + 时间
            HStack(spacing: 0) {
                BatteryIconView(
                    level: battery.level,
                    isCharging: battery.isCharging,
                    textColor: settings.currentTheme.textColor
                )
                Text("\u{2002}\(footerTime)")       // 1 en-space + HH:mm
                    .font(.system(size: 11))
                    .foregroundColor(settings.currentTheme.textColor.opacity(0.5))
            }
            // 分隔点
            Text("·")
                .font(.system(size: 11))
                .foregroundColor(settings.currentTheme.textColor.opacity(0.3))
            // 页码
            Text(pageLabel)
                .font(.system(size: 11))
                .foregroundColor(settings.currentTheme.textColor.opacity(0.5))
        }
        .frame(maxWidth: .infinity, alignment: .center)   // 整体居中
        .background(settings.currentTheme.backgroundColor)
    }

    // MARK: 滚动模式（连续正文 + 章节底部导航按钮）
    private var scrollModeView: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: settings.paragraphSpacing) {
                // 章节标题
                Text(currentChapterTitle)
                    .font(.system(size: settings.fontSize + 6, weight: .bold))
                    .foregroundColor(settings.currentTheme.textColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 8)

                // 正文内容
                let fullContent = viewModel.chapterContents[viewModel.currentChapterIndex] ?? "加载中..."
                ForEach(paragraphs(fullContent), id: \.self) { para in
                    Text(applyTraditional(para))
                        .font(.system(size: settings.fontSize))
                        .kerning(settings.letterSpacing)
                        .lineSpacing(settings.lineSpacing)
                        .foregroundColor(settings.currentTheme.textColor)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                // 章节底部导航（滚动模式专用）
                Divider().padding(.vertical, 16)
                HStack {
                    if viewModel.currentChapterIndex > 0 {
                        Button {
                            viewModel.jumpToChapter(viewModel.currentChapterIndex - 1)
                        } label: {
                            Label("上一章", systemImage: "chevron.left")
                                .font(.system(size: settings.fontSize - 2))
                                .foregroundColor(settings.currentTheme.textColor.opacity(0.7))
                        }
                    }
                    Spacer()
                    Text("\(viewModel.currentChapterIndex + 1) / \(viewModel.chapters.count)章")
                        .font(.system(size: settings.fontSize - 4))
                        .foregroundColor(settings.currentTheme.textColor.opacity(0.5))
                    Spacer()
                    if viewModel.currentChapterIndex < viewModel.chapters.count - 1 {
                        Button {
                            viewModel.jumpToChapter(viewModel.currentChapterIndex + 1)
                        } label: {
                            Label("下一章", systemImage: "chevron.right")
                                .font(.system(size: settings.fontSize - 2))
                                .foregroundColor(settings.currentTheme.textColor.opacity(0.7))
                        }
                    }
                }
                .padding(.bottom, 40)
            }
            .padding(.horizontal, settings.sideMargin)
            .padding(.top, settings.topMargin)
            .padding(.bottom, settings.bottomMargin)
        }
        .ignoresSafeArea()
    }

    private var tapZones: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                Color.clear.contentShape(Rectangle())
                    .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { viewModel.prevPage() } }
                    .frame(width: geo.size.width / 3)
                Color.clear.contentShape(Rectangle())
                    .onTapGesture { withAnimation { viewModel.showingMenu = true } }
                    .frame(width: geo.size.width / 3)
                Color.clear.contentShape(Rectangle())
                    .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { viewModel.nextPage() } }
                    .frame(width: geo.size.width / 3)
            }
        }
        // 不能用 .ignoresSafeArea()：会扩展到全屏并拦截 header 区域的 "<" 按钮
    }

    private var loadingPlaceholder: some View {
        VStack(spacing: 12) {
            ProgressView().tint(settings.currentTheme.textColor)
            Text("加载中...")
                .foregroundColor(settings.currentTheme.textColor)
                .font(.system(size: settings.fontSize))
        }
    }

    private var loadFailedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundColor(.orange)
            Text("加载失败")
                .font(.headline)
                .foregroundColor(settings.currentTheme.textColor)
            if viewModel.chapters.isEmpty {
                Text("未能获取章节列表\n请检查书源是否可用，或重新搜索添加此书")
                    .font(.caption)
                    .foregroundColor(settings.currentTheme.textColor.opacity(0.6))
                    .multilineTextAlignment(.center)
            } else {
                Text("章节内容加载失败\n请尝试刷新")
                    .font(.caption)
                    .foregroundColor(settings.currentTheme.textColor.opacity(0.6))
                    .multilineTextAlignment(.center)
            }
            Button {
                Task { await viewModel.setup() }
            } label: {
                Label("重试", systemImage: "arrow.clockwise")
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.bordered)
            .tint(.orange)
        }
        .padding()
    }

    private var currentChapterTitle: String {
        viewModel.chapters.indices.contains(viewModel.currentChapterIndex)
            ? viewModel.chapters[viewModel.currentChapterIndex].title : ""
    }

    // 把正文按段落分割，用于滚动模式应用段间距
    private func paragraphs(_ text: String) -> [String] {
        text.components(separatedBy: "\n\n")
            .flatMap { $0.components(separatedBy: "\n") }
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private func applyTraditional(_ text: String) -> String {
        guard settings.useTraditionalChinese else { return text }
        return text.applyingTransform(StringTransform("Simplified-Traditional"), reverse: false) ?? text
    }

    /// 在下一个分钟整点更新 footerTime，然后递归调度，确保时间显示始终与系统时钟对齐。
    private func scheduleNextMinuteUpdate() {
        minuteWorkItem?.cancel()
        let now = Date()
        guard let nextMinute = Calendar.current.nextDate(
            after: now, matching: DateComponents(second: 0), matchingPolicy: .nextTime
        ) else { return }
        let delay = nextMinute.timeIntervalSinceNow
        let work = DispatchWorkItem {
            let f = DateFormatter(); f.dateFormat = "HH:mm"
            footerTime = f.string(from: Date())
            scheduleNextMinuteUpdate()
        }
        minuteWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// 启动音量键翻页监听（AVAudioSession KVO）
    private func setupVolumePageTurn() {
        guard settings.volumePageTurn else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(true)
        volumeObservation = session.observe(\.outputVolume, options: [.new, .old]) { _, change in
            guard let newVol = change.newValue, let oldVol = change.oldValue else { return }
            DispatchQueue.main.async {
                guard settings.volumePageTurn else { return }
                if newVol > oldVol + 0.01 {
                    withAnimation(.easeInOut(duration: 0.2)) { viewModel.nextPage() }
                } else if newVol < oldVol - 0.01 {
                    withAnimation(.easeInOut(duration: 0.2)) { viewModel.prevPage() }
                }
                // 恢复音量到中间值，保证两个方向都能继续使用
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    volumeSlider?.setValue(0.5, animated: false)
                }
            }
        }
        // 设初始音量到中间值（留出上下各半格余量）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            volumeSlider?.setValue(0.5, animated: false)
        }
    }

    private func teardownVolumePageTurn() {
        volumeObservation?.invalidate()
        volumeObservation = nil
    }

    // MARK: - 自动翻页

    private func startAutoScroll() {
        autoScrollTimer?.invalidate()
        autoScrollTimer = Timer.scheduledTimer(
            withTimeInterval: settings.autoScrollInterval, repeats: true
        ) { [weak viewModel] _ in
            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: 0.3)) { viewModel?.nextPage() }
            }
        }
    }

    private func stopAutoScroll() {
        autoScrollTimer?.invalidate()
        autoScrollTimer = nil
    }
}

// MARK: - ReaderPageView
// 纯正文渲染，不含 header/footer（已移至 ReaderView.pageModeView 统一管理）

struct ReaderPageView: View {
    let content: String
    let chapterTitle: String
    // 以下参数保留供 SimulationPagingView 兼容，本视图不再使用
    var pageLabel: String = ""
    var totalChapters: Int = 0
    var chapterIndex: Int = 0
    var sourceOrigin: String = ""
    var pageStartOffset: Int = 0
    var highlights: [BookHighlight] = []
    var onHighlight: ((Int, Int, String, Int) -> Void)? = nil
    var onBack: (() -> Void)? = nil
    var isFirstPage: Bool = false

    @StateObject private var settings = ReaderSettings.shared
    @ObservedObject private var ttsManager = TTSManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isFirstPage && !chapterTitle.isEmpty {
                Text(applyTraditional(chapterTitle))
                    .font(.system(size: settings.fontSize + 6, weight: .bold))
                    .foregroundColor(settings.currentTheme.textColor)
                    .padding(.bottom, 20)
            }

            // 混合内容渲染：识别 ⟨IMG:url⟩ 标记行，分别渲染为图片或文字
            MixedContentView(
                content: applyTraditional(content),
                settings: settings,
                sourceOrigin: sourceOrigin,
                pageStartOffset: pageStartOffset,
                highlights: highlights,
                onHighlight: onHighlight,
                ttsSpeakRange: ttsManager.speakingRange
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, settings.sideMargin)
        .padding(.top, settings.topMargin)
        .padding(.bottom, settings.bottomMargin)
        .clipped()  // 防止内容溢出 footer 区域（CoreText/TextKit2 极端误差兜底）
    }

    private func applyTraditional(_ text: String) -> String {
        guard settings.useTraditionalChinese else { return text }
        return text.applyingTransform(StringTransform("Simplified-Traditional"), reverse: false) ?? text
    }
}

// MARK: - ReaderMenuView

struct ReaderMenuView: View {
    @ObservedObject var viewModel: ReaderViewModel
    @ObservedObject var settings: ReaderSettings
    let onBack: () -> Void

    @ObservedObject private var novellaTTSEngine = NovellaTTSEngine.shared

    @State private var showingTOC      = false
    @State private var showingSettings = false
    @State private var showingCacheAlert  = false
    @State private var showingBookmarks   = false
    @State private var showingSearch      = false
    @State private var showingHighlights  = false
    @State private var showingSourceSelection = false
    @State private var bookmarkAdded = false
    @State private var ttsTimerSelection: Int? = nil
    @State private var showCustomTimer = false
    @State private var customTimerInput = ""

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Spacer()   // 透明中间区域由 ReaderView 的 Color.clear 覆盖层处理关闭
            bottomPanel
        }
        .allowsHitTesting(true)   // 菜单本身接受点击，中间 Spacer 不阻断透明区
        .foregroundColor(.primary)
        .sheet(isPresented: $showingTOC)      { TOCView(viewModel: viewModel) }
        .sheet(isPresented: $showingSettings) { ReaderSettingsSheet() }
        .sheet(isPresented: $showingSourceSelection) {
            SourceSelectionView(
                currentSourceUrl: viewModel.book.origin,
                bookName: viewModel.book.name,
                currentChapterIndex: viewModel.currentChapterIndex
            ) { source in
                Task { await viewModel.changeSource(to: source) }
            }
        }
    }

    // MARK: 顶部
    private var topBar: some View {
        HStack {
            Button(action: onBack) {
                Image(systemName: "chevron.left").font(.title2)
            }
            Spacer()
            VStack(spacing: 2) {
                Text(viewModel.book.name).font(.headline).lineLimit(1)
                if !currentChapterTitle.isEmpty {
                    Text(currentChapterTitle).font(.caption).foregroundColor(.secondary).lineLimit(1)
                }
            }
            Spacer()
            // 书签按钮
            Button {
                Task {
                    await addBookmark()
                    withAnimation { bookmarkAdded = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        withAnimation { bookmarkAdded = false }
                    }
                }
            } label: {
                Image(systemName: bookmarkAdded ? "bookmark.fill" : "bookmark")
                    .font(.title2)
                    .foregroundColor(bookmarkAdded ? .yellow : .primary)
            }

            // 换源按钮
            Button {
                showingSourceSelection = true
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath.circle")
                    .font(.title2)
            }

            // F2: 三点菜单
            Menu {
                Button {
                    Task { await viewModel.refreshCurrentChapter() }
                } label: {
                    Label("刷新当前章节", systemImage: "arrow.clockwise")
                }

                Button {
                    showingCacheAlert = true
                } label: {
                    Label(viewModel.isCachingAll
                          ? "缓存中 \(Int(viewModel.cacheProgress * 100))%…"
                          : "缓存全本",
                          systemImage: "arrow.down.circle")
                }
                .disabled(viewModel.isCachingAll)

                if let url = URL(string: viewModel.book.bookUrl) {
                    ShareLink(
                        item: url,
                        subject: Text(viewModel.book.name),
                        message: Text("via Legado")
                    ) {
                        Label("分享", systemImage: "square.and.arrow.up")
                    }
                }

                Divider()

                Button {
                    Task { await addBookmark() }
                } label: {
                    Label("添加书签", systemImage: "bookmark.fill")
                }

                Button { showingBookmarks = true } label: {
                    Label("书签列表", systemImage: "bookmark")
                }

                Button { showingSearch = true } label: {
                    Label("搜索本书", systemImage: "magnifyingglass")
                }

                Button { showingHighlights = true } label: {
                    Label("高亮列表", systemImage: "highlighter")
                }            } label: {
                Image(systemName: "ellipsis").font(.title2)
            }
            .alert("缓存全本", isPresented: $showingCacheAlert) {
                Button("开始下载", role: .none) { viewModel.cacheAllChapters() }
                Button("取消", role: .cancel) { }
            } message: {
                Text("将重新下载全部 \(viewModel.chapters.count) 章节，可能需要较长时间，建议在 WiFi 下进行。")
            }
            .sheet(isPresented: $showingBookmarks) {
                BookmarkListView(bookUrl: viewModel.book.bookUrl) { chapterIdx, pos in
                    viewModel.jumpToChapter(chapterIdx)
                }
            }
            .sheet(isPresented: $showingSearch) {
                BookSearchView(
                    bookUrl: viewModel.book.bookUrl,
                    chapterContents: viewModel.chapterContents,
                    chapters: viewModel.chapters
                ) { chapterIdx in
                    viewModel.jumpToChapter(chapterIdx)
                }
            }
            .sheet(isPresented: $showingHighlights) {
                HighlightListView(
                    bookUrl: viewModel.book.bookUrl,
                    chapters: viewModel.chapters
                ) { chapterIdx in
                    viewModel.jumpToChapter(chapterIdx)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(
            Color(UIColor.systemBackground).opacity(0.95)
                .ignoresSafeArea(edges: .top)
        )
    }

    // MARK: 添加书签
    private func addBookmark() async {
        let idx   = viewModel.currentChapterIndex
        let title = idx < viewModel.chapters.count ? viewModel.chapters[idx].title : "第\(idx+1)章"
        let snippet = viewModel.currentPages.indices.contains(viewModel.currentPageIndex)
            ? String(viewModel.currentPages[viewModel.currentPageIndex].prefix(80))
            : ""
        let bm = Bookmark(
            bookUrl: viewModel.book.bookUrl,
            chapterIndex: idx,
            chapterTitle: title,
            chapterPos: viewModel.currentPageIndex,
            content: snippet,
            createdAt: Date()
        )
        try? await DatabaseManager.shared.saveBookmark(bm)
    }

    // MARK: 底部
    private var bottomPanel: some View {
        VStack(spacing: 12) {
            // 章节进度条 + B5修复：上一章/下一章做成真正的 Button
            HStack(spacing: 8) {
                Button {
                    viewModel.jumpToChapter(max(0, viewModel.currentChapterIndex - 1),
                                            keepMenuOpen: true)
                } label: {
                    Text("上一章").font(.subheadline).foregroundColor(.blue)
                }

                Slider(
                    value: Binding(
                        get: { Double(viewModel.currentChapterIndex) },
                        set: { viewModel.jumpToChapter(Int($0)) }
                    ),
                    in: 0...Double(max(0, viewModel.chapters.count - 1)),
                    step: 1
                )

                Button {
                    guard !viewModel.chapters.isEmpty else { return }
                    let last = viewModel.chapters.count - 1
                    viewModel.jumpToChapter(min(last, viewModel.currentChapterIndex + 1),
                                            keepMenuOpen: true)
                } label: {
                    Text("下一章").font(.subheadline).foregroundColor(.blue)
                }
            }
            .padding(.horizontal)

            if viewModel.isTTSEnabled {
                // ── TTS 控制面板（激活朗读时取代功能按钮行）──────────
                ttsPanelView
            } else {
                // ── 原有五功能按钮行 ─────────────────────────────────
                HStack(spacing: 0) {
                    menuButton(icon: "headphones", label: "朗读") {
                        viewModel.toggleTTS()
                    }
                    menuButton(icon: "list.bullet", label: "目录") { showingTOC = true }
                    menuButton(icon: settings.pageMode == .scroll ? "book" : "scroll",
                               label: settings.pageMode == .scroll ? "翻页" : "滚动") {
                        settings.pageMode = settings.pageMode == .scroll ? .page : .scroll
                    }
                    menuButton(icon: settings.currentTheme.id == "dark" ? "sun.max" : "moon",
                               label: settings.currentTheme.id == "dark" ? "白天" : "夜间") {
                        if settings.currentTheme.id == "dark" {
                            settings.themeId = settings.preNightThemeId.isEmpty ? "parchment" : settings.preNightThemeId
                        } else {
                            settings.preNightThemeId = settings.themeId
                            settings.themeId = "dark"
                        }
                    }
                    menuButton(icon: "textformat.size", label: "设置") { showingSettings = true }
                }

                if viewModel.chapters.count > 0 {
                    Text("第\(viewModel.currentChapterIndex + 1)章 / 共\(viewModel.chapters.count)章")
                        .font(.caption2).foregroundColor(.secondary)
                }
            }
        }
        .padding(.top, 12)
        .background(
            Color(UIColor.systemBackground).opacity(0.95)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private var currentChapterTitle: String {
        viewModel.chapters.indices.contains(viewModel.currentChapterIndex)
            ? viewModel.chapters[viewModel.currentChapterIndex].title : ""
    }

    private func menuButton(icon: String, label: String, tint: Color = .primary, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.title3).foregroundColor(tint)
                Text(label).font(.caption2).foregroundColor(.primary)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: TTS 控制面板

    @ViewBuilder
    private var ttsPanelView: some View {
        VStack(spacing: 10) {

            // 语速（rate: 0.1-1.0 对应 iOS AVSpeechUtterance 有效范围；
            //        显示为 rate/0.5 倍速，0.5=1.0x 正常语速，1.0=2.0x 最快）
            HStack(spacing: 8) {
                Text("语速").font(.caption).foregroundColor(.secondary).frame(width: 36, alignment: .leading)
                Text("慢").font(.caption2).foregroundColor(.secondary)
                Slider(
                    value: Binding(
                        get: { Double(settings.ttsRate) },
                        set: { settings.ttsRate = Float($0) }
                    ),
                    in: 0.1...1.0,
                    onEditingChanged: { editing in
                        if !editing { viewModel.ttsManager.restartForSettingChange() }
                    }
                )
                Text("快").font(.caption2).foregroundColor(.secondary)
                Text(String(format: "%.1fx", settings.ttsRate / 0.5))
                    .font(.caption).frame(width: 36, alignment: .trailing)
                    .monospacedDigit()
            }
            .padding(.horizontal)

            // 音色选择
            HStack(alignment: .center) {
                Text("音色").font(.caption).foregroundColor(.secondary).frame(width: 36, alignment: .leading)
                if settings.useNovellaTTS {
                    // ZipVoice 预设音色（逐句合成，下句自动生效）
                    Picker("音色", selection: Binding(
                        get: { novellaTTSEngine.selectedVoiceId },
                        set: { novellaTTSEngine.selectVoice(id: $0) }
                    )) {
                        ForEach(novellaTTSEngine.availableVoices, id: \.id) { voice in
                            Text(voice.displayName).tag(voice.id)
                        }
                    }
                    .pickerStyle(.menu)
                    Spacer()
                    Text("下句生效").font(.caption2).foregroundColor(.secondary)
                } else {
                    // 系统 AVSpeech 声音（下次朗读生效）
                    Picker("发音", selection: Binding(
                        get: { viewModel.ttsManager.selectedVoice?.identifier ?? "" },
                        set: { id in
                            viewModel.ttsManager.selectedVoice = id.isEmpty
                                ? nil
                                : AVSpeechSynthesisVoice(identifier: id)
                        }
                    )) {
                        Text("系统默认").tag("")
                        ForEach(chineseVoices, id: \.identifier) { voice in
                            Text(voiceDisplayName(voice)).tag(voice.identifier)
                        }
                    }
                    .pickerStyle(.menu)
                    Spacer()
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Text("下载更多 →").font(.caption2).foregroundColor(.blue)
                    }
                }
            }
            .padding(.horizontal)

            // 定时
            HStack(spacing: 6) {
                Text("定时").font(.caption).foregroundColor(.secondary).frame(width: 36, alignment: .leading)
                ForEach([5, 15, 30, 60], id: \.self) { min in
                    timerButton(minutes: min)
                }
                Button {
                    showCustomTimer = true
                } label: {
                    let isCustomActive = ttsTimerSelection != nil && ![5,15,30,60].contains(ttsTimerSelection!)
                    Text(isCustomActive ? "\(ttsTimerSelection!)分" : "自定义")
                        .font(.caption)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(isCustomActive ? Color.blue : Color(.systemGray5))
                        .foregroundColor(isCustomActive ? .white : .primary)
                        .cornerRadius(6)
                }
                if let remaining = viewModel.ttsRemainingSeconds {
                    Text(formatRemaining(remaining))
                        .font(.caption2).foregroundColor(.secondary)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal)

            // 退出 + 暂停/继续
            HStack(spacing: 16) {
                Button(role: .destructive) {
                    viewModel.stopTTS()
                    ttsTimerSelection = nil
                } label: {
                    Text("退出朗读")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color(.systemGray5))
                        .foregroundColor(.red)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)

                Button {
                    if viewModel.ttsIsPlaying { viewModel.ttsManager.pause() } else { viewModel.ttsManager.resume() }
                } label: {
                    HStack {
                        Image(systemName: viewModel.ttsIsPlaying ? "pause.circle.fill" : "play.circle.fill")
                        Text(viewModel.ttsIsPlaying ? "暂停" : "继续")
                    }
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 8)
        .alert("自定义定时（分钟）", isPresented: $showCustomTimer) {
            TextField("输入分钟数", text: $customTimerInput)
                .keyboardType(.numberPad)
            Button("确定") {
                if let min = Int(customTimerInput), min > 0, min <= 999 {
                    ttsTimerSelection = min
                    viewModel.ttsManager.startTimer(minutes: min)
                }
                customTimerInput = ""
            }
            Button("取消", role: .cancel) { customTimerInput = "" }
        }
    }

    private var chineseVoices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("zh") }
            .sorted { $0.language < $1.language }
    }

    private func voiceDisplayName(_ voice: AVSpeechSynthesisVoice) -> String {
        let langMap = ["zh-CN": "普通话", "zh-HK": "粤语", "zh-TW": "台湾中文"]
        let lang = langMap[voice.language] ?? voice.language
        let quality: String
        switch voice.quality {
        case .enhanced: quality = "增强版"
        case .premium:  quality = "高级版"
        default:        quality = "标准"
        }
        return "\(lang) - \(voice.name) (\(quality))"
    }

    @ViewBuilder
    private func timerButton(minutes: Int) -> some View {
        let isSelected = ttsTimerSelection == minutes
        Button {
            if isSelected {
                ttsTimerSelection = nil
                viewModel.ttsManager.cancelTimer()
            } else {
                ttsTimerSelection = minutes
                viewModel.ttsManager.startTimer(minutes: minutes)
            }
        } label: {
            Text("\(minutes)分")
                .font(.caption)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(isSelected ? Color.blue : Color(.systemGray5))
                .foregroundColor(isSelected ? .white : .primary)
                .cornerRadius(6)
        }
    }

    private func formatRemaining(_ seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

// MARK: - ReaderSettingsSheet

struct ReaderSettingsSheet: View {
    @StateObject private var settings = ReaderSettings.shared
    @StateObject private var fontManager = FontManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showPreferences = false
    @State private var brightness: Double = Double(UIScreen.main.brightness)
    @State private var showFontImporter = false

    var body: some View {
        NavigationView {
            Form {
                // ── 亮度 ─────────────────────────────────────
                Section("亮度") {
                    HStack(spacing: 8) {
                        Image(systemName: "sun.min").font(.caption).foregroundColor(.secondary)
                        Slider(value: $brightness, in: 0.05...1.0) { _ in
                            UIScreen.main.brightness = CGFloat(brightness)
                        }
                        Image(systemName: "sun.max").font(.caption).foregroundColor(.secondary)
                    }
                }

                // ── 字体排版 ─────────────────────────────────
                Section("字体排版") {
                    stepperRow(title: "字号",   value: $settings.fontSize,        range: 12...40, step: 1)
                    stepperRow(title: "行高",   value: $settings.lineSpacing,      range: 0...30,  step: 1)
                    stepperRow(title: "字间距", value: $settings.letterSpacing,    range: -3...10, step: 0.5)
                    stepperRow(title: "段间距", value: $settings.paragraphSpacing, range: 0...50,  step: 2)

                    Picker("字体", selection: $settings.fontName) {
                        Text("系统默认").tag("")
                        ForEach(fontManager.importedFonts) { entry in
                            Text(entry.displayName).tag(entry.psName)
                        }
                    }

                    Button {
                        showFontImporter = true
                    } label: {
                        Label("导入字体文件（TTF/OTF）", systemImage: "plus.circle")
                    }
                    .fileImporter(
                        isPresented: $showFontImporter,
                        allowedContentTypes: [.font],
                        allowsMultipleSelection: false
                    ) { result in
                        guard let url = try? result.get().first else { return }
                        let accessing = url.startAccessingSecurityScopedResource()
                        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                        if let entry = fontManager.importFont(from: url) {
                            settings.fontName = entry.psName
                        }
                    }
                }

                // ── 主题 ─────────────────────────────────────
                Section("主题") {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible()), count: 5),
                        spacing: 12
                    ) {
                        ForEach(ReaderTheme.builtinThemes) { theme in
                            themeCircle(theme: theme)
                        }
                        customThemeCircle
                    }
                    .padding(.vertical, 4)

                    if settings.themeId == "custom" {
                        VStack(spacing: 8) {
                            ColorPicker("背景色", selection: Binding(
                                get: { settings.customBgColor },
                                set: { settings.customBgColor = $0 }
                            ), supportsOpacity: false)
                            ColorPicker("文字颜色", selection: Binding(
                                get: { settings.customTextColor },
                                set: { settings.customTextColor = $0 }
                            ), supportsOpacity: false)
                        }
                        .padding(.top, 4)
                    }
                }

                // ── 更多设置入口 ──────────────────────────────
                Section {
                    Button {
                        showPreferences = true
                    } label: {
                        HStack {
                            Text("更多阅读设置")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .foregroundColor(.primary)
                }
            }
            .navigationTitle("阅读设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .onAppear { brightness = Double(UIScreen.main.brightness) }
            .sheet(isPresented: $showPreferences) {
                ReadingPreferencesView()
            }
        }
    }

    // MARK: - 主题圆

    @ViewBuilder
    private func themeCircle(theme: ReaderTheme) -> some View {
        VStack(spacing: 4) {
            Circle()
                .fill(theme.backgroundColor)
                .frame(width: 44, height: 44)
                .overlay(
                    Circle().stroke(
                        settings.themeId == theme.id ? Color.blue : Color.clear,
                        lineWidth: 2.5
                    )
                )
            Text(theme.name)
                .font(.caption2)
                .foregroundColor(.primary)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if theme.id != "dark" { settings.preNightThemeId = theme.id }
            settings.themeId = theme.id
        }
    }

    @ViewBuilder
    private var customThemeCircle: some View {
        VStack(spacing: 4) {
            ZStack {
                if settings.themeId == "custom" {
                    Circle()
                        .fill(settings.customBgColor)
                        .frame(width: 44, height: 44)
                        .overlay(Circle().stroke(Color.blue, lineWidth: 2.5))
                } else {
                    Circle()
                        .fill(LinearGradient(
                            colors: [.pink, .purple, .blue],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ))
                        .frame(width: 44, height: 44)
                        .overlay(Circle().stroke(Color.clear, lineWidth: 2.5))
                }
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(
                        settings.themeId == "custom" ? settings.customTextColor : .white
                    )
            }
            Text("自定义")
                .font(.caption2)
                .foregroundColor(.primary)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            settings.preNightThemeId = "custom"   // 记录夜间切回时的目标主题
            settings.themeId = "custom"
        }
    }

    // MARK: - Stepper 行

    private func stepperRow(title: String, value: Binding<CGFloat>,
                             range: ClosedRange<CGFloat>, step: CGFloat) -> some View {
        HStack {
            Text(title)
            Spacer()
            Button {
                if value.wrappedValue > range.lowerBound { value.wrappedValue -= step }
            } label: {
                Image(systemName: "minus.circle").foregroundColor(.blue)
            }.buttonStyle(.plain)
            Text(String(format: step < 1 ? "%.1f" : "%.0f", value.wrappedValue))
                .frame(width: 36, alignment: .center)
                .monospacedDigit()
            Button {
                if value.wrappedValue < range.upperBound { value.wrappedValue += step }
            } label: {
                Image(systemName: "plus.circle").foregroundColor(.blue)
            }.buttonStyle(.plain)
        }
    }
}

// MARK: - ReaderPageContent（兼容旧引用）
typealias ReaderPageContent = ReaderPageView

// MARK: - MixedContentView — 混合文本与图片渲染

private struct MixedContentView: View {
    let content: String
    let settings: ReaderSettings
    let sourceOrigin: String
    var pageStartOffset: Int = 0
    var highlights: [BookHighlight] = []
    var onHighlight: ((Int, Int, String, Int) -> Void)? = nil
    /// 当前 TTS 朗读范围（章节绝对偏移），nil = 未朗读
    var ttsSpeakRange: NSRange? = nil

    private static let imgMarker = "⟨IMG:"
    private static let imgEnd    = "⟩"

    var body: some View {
        let segs = segments
        return VStack(alignment: .leading, spacing: settings.lineSpacing) {
            ForEach(Array(segs.enumerated()), id: \.offset) { i, seg in
                if seg.isImage {
                    CoverImageView(url: seg.text, referer: sourceOrigin)
                        .frame(maxWidth: .infinity)
                        .frame(height: 220)
                        .cornerRadius(4)
                } else if !seg.text.isEmpty {
                    let segOffset   = computeSegmentOffset(upTo: i)
                    let absSegStart = pageStartOffset + segOffset
                    TextKit2TextView(
                        text: nsAttributedText(seg.text),
                        backgroundColor: UIColor(settings.currentTheme.backgroundColor),
                        pageStartOffset: absSegStart,
                        highlights: allHighlights(absStart: absSegStart,
                                                   absEnd: absSegStart + (seg.text as NSString).length),
                        onHighlight: onHighlight
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    /// 合并手动高亮 + TTS 朗读高亮，统一转为段内偏移
    private func allHighlights(absStart: Int, absEnd: Int) -> [(range: NSRange, color: UIColor)] {
        var result: [(range: NSRange, color: UIColor)] = []
        for h in highlights {
            let hS = max(h.startOffset, absStart) - absStart
            let hE = min(h.endOffset,   absEnd)   - absStart
            if hE > hS { result.append((NSRange(location: hS, length: hE - hS), h.uiColor)) }
        }
        if let tts = ttsSpeakRange {
            let tS = max(tts.location,              absStart) - absStart
            let tE = min(tts.location + tts.length, absEnd)   - absStart
            if tE > tS {
                result.append((NSRange(location: tS, length: tE - tS),
                               UIColor.systemOrange.withAlphaComponent(0.35)))
            }
        }
        return result
    }

    private struct Segment { let isImage: Bool; let text: String }

    private var segments: [Segment] {
        var result: [Segment] = []
        var textBuffer = ""
        for line in content.components(separatedBy: "\n\n") {
            let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.hasPrefix(Self.imgMarker) && t.hasSuffix(Self.imgEnd) {
                if !textBuffer.isEmpty {
                    result.append(Segment(isImage: false, text: textBuffer))
                    textBuffer = ""
                }
                let url = String(t.dropFirst(Self.imgMarker.count).dropLast(Self.imgEnd.count))
                result.append(Segment(isImage: true, text: url))
            } else {
                textBuffer += (textBuffer.isEmpty ? "" : "\n\n") + t
            }
        }
        if !textBuffer.isEmpty { result.append(Segment(isImage: false, text: textBuffer)) }
        return result
    }

    private func nsAttributedText(_ text: String) -> NSAttributedString {
        let para = NSMutableParagraphStyle()
        let bodyFont = settings.readerFont(size: settings.fontSize)
        let fixedH = bodyFont.lineHeight + settings.lineSpacing
        para.minimumLineHeight  = fixedH
        para.maximumLineHeight  = fixedH
        para.paragraphSpacing   = settings.paragraphSpacing
        return NSAttributedString(string: text, attributes: [
            .font:           bodyFont,
            .foregroundColor: UIColor(settings.currentTheme.textColor),
            .paragraphStyle: para,
            .kern:           settings.letterSpacing,
        ])
    }

    /// 计算 segments[0..<upTo] 中文字段的累积字符数（段间用 \n\n 分隔）
    private func computeSegmentOffset(upTo idx: Int) -> Int {
        var offset = 0
        for i in 0..<min(idx, segments.count) {
            if !segments[i].isImage {
                offset += (segments[i].text as NSString).length + 2 // +2 for \n\n
            }
        }
        return offset
    }

    private func attributedText(_ text: String) -> AttributedString {
        let ns = nsAttributedText(text)
        return (try? AttributedString(ns, including: \.uiKit)) ?? AttributedString(text)
    }
}

// MARK: - ReadingPreferencesView（阅读偏好）

struct ReadingPreferencesView: View {
    @StateObject private var settings = ReaderSettings.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Form {
                // ── 布局预设 ──────────────────────────────────
                Section("布局预设") {
                    HStack(spacing: 12) {
                        presetButton(label: "正常",  fontSize: 18, lineSpacing: 8,  sideMargin: 20)
                        presetButton(label: "舒适",  fontSize: 19, lineSpacing: 12, sideMargin: 24)
                        presetButton(label: "紧凑",  fontSize: 17, lineSpacing: 6,  sideMargin: 16)
                    }
                    .padding(.vertical, 4)
                }

                // ── 页眉信息 ──────────────────────────────────
                Section("页眉信息") {
                    Toggle("显示章节进度", isOn: $settings.showHeaderProgress)
                    Toggle("显示右上电量", isOn: $settings.showHeaderBattery)
                }

                // ── 高级 ──────────────────────────────────────
                Section("高级") {
                    Toggle("屏幕常亮", isOn: $settings.keepScreenOn)
                        .onChange(of: settings.keepScreenOn) { val in
                            UIApplication.shared.isIdleTimerDisabled = val
                        }
                    Toggle("繁体中文", isOn: $settings.useTraditionalChinese)
                    Toggle("音量键翻页", isOn: $settings.volumePageTurn)
                    if ModelManager.isAvailable(.zipVoiceDistillInt8) {
                        Toggle("高质量TTS（ZipVoice）", isOn: $settings.useNovellaTTS)
                    }
                }

                // ── 自动翻页 ──────────────────────────────────
                Section("自动翻页") {
                    Toggle("启用自动翻页", isOn: $settings.autoScrollEnabled)
                    if settings.autoScrollEnabled {
                        HStack {
                            Text("翻页间隔")
                            Slider(value: $settings.autoScrollInterval, in: 3...120)
                            Text("\(Int(settings.autoScrollInterval))秒")
                                .monospacedDigit()
                                .frame(width: 44, alignment: .trailing)
                        }
                    }
                }

                // ── 文字颜色 ──────────────────────────────────
                Section("文字颜色") {
                    Toggle("自定义文字颜色", isOn: Binding(
                        get:  { settings.textColorOverrideHex.isEmpty == false },
                        set:  { on in
                            if on { settings.textColorOverride = settings.currentTheme.textColor }
                            else  { settings.textColorOverrideHex = "" }
                        }
                    ))
                    if settings.textColorOverrideHex.isEmpty == false {
                        ColorPicker("文字颜色", selection: Binding(
                            get: { settings.textColorOverride ?? settings.currentTheme.textColor },
                            set: { settings.textColorOverride = $0 }
                        ), supportsOpacity: false)
                        Button("恢复主题默认") {
                            settings.textColorOverrideHex = ""
                        }
                        .foregroundColor(.red)
                    }
                }

                // ── 缓存 ──────────────────────────────────────
                Section("缓存") {
                    HStack {
                        Text("预缓存章节数")
                        Spacer()
                        Button {
                            settings.prefetchCount = max(1, settings.prefetchCount - 1)
                        } label: {
                            Image(systemName: "minus.circle")
                        }.buttonStyle(.plain)
                        Text("\(settings.prefetchCount)章")
                            .frame(width: 40, alignment: .center)
                            .monospacedDigit()
                        Button {
                            settings.prefetchCount = min(50, settings.prefetchCount + 1)
                        } label: {
                            Image(systemName: "plus.circle")
                        }.buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("阅读偏好")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private func presetButton(label: String, fontSize: CGFloat,
                               lineSpacing: CGFloat, sideMargin: CGFloat) -> some View {
        let isActive = abs(settings.fontSize - fontSize) < 0.5
                    && abs(settings.lineSpacing - lineSpacing) < 0.5
                    && abs(settings.sideMargin - sideMargin) < 0.5
        return Button {
            settings.fontSize    = fontSize
            settings.lineSpacing = lineSpacing
            settings.sideMargin  = sideMargin
        } label: {
            Text(label)
                .font(.subheadline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(isActive ? Color.blue : Color(.systemGray5))
                .foregroundColor(isActive ? .white : .primary)
                .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - HiddenVolumeView — 抑制系统音量 HUD，暴露 UISlider 用于复位音量

private struct HiddenVolumeView: UIViewRepresentable {
    @Binding var sliderRef: UISlider?

    func makeUIView(context: Context) -> MPVolumeView {
        let v = MPVolumeView()
        v.alpha = 0.001
        v.isUserInteractionEnabled = false
        DispatchQueue.main.async {
            sliderRef = v.subviews.first(where: { $0 is UISlider }) as? UISlider
        }
        return v
    }

    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}

// MARK: - TextKit2TextView — UITextView with TextKit 2 backend

/// UIViewRepresentable wrapping UITextView(usingTextLayoutManager: true).
/// 与 ChapterPaginator 使用相同的 NSTextLayoutManager 引擎，确保测量与渲染一致。
private struct TextKit2TextView: UIViewRepresentable {
    let text: NSAttributedString
    let backgroundColor: UIColor
    /// 该页在完整章节文本中的起始偏移（用于将页内选区映射到章节偏移）
    var pageStartOffset: Int = 0
    /// 当前页关联的高亮（range 是页内偏移）
    var highlights: [(range: NSRange, color: UIColor)] = []
    /// 用户选中文字后触发：(pageLocalStart, pageLocalEnd, selectedText)
    var onHighlight: ((Int, Int, String, Int) -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator(onHighlight: onHighlight) }

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView(usingTextLayoutManager: true)
        tv.isEditable               = false
        tv.isSelectable             = true
        tv.isUserInteractionEnabled = true
        tv.backgroundColor          = .clear
        tv.textContainerInset       = .zero
        tv.textContainer.lineFragmentPadding = 0
        tv.dataDetectorTypes        = .link   // 自动检测 URL，点击跳转
        tv.delegate                 = context.coordinator
        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        context.coordinator.onHighlight = onHighlight
        // 将高亮背景色叠加到 NSAttributedString
        let mutable = NSMutableAttributedString(attributedString: text)
        for h in highlights {
            let safe = NSRange(
                location: min(h.range.location, mutable.length),
                length: min(h.range.length, mutable.length - min(h.range.location, mutable.length))
            )
            if safe.length > 0 {
                mutable.addAttribute(.backgroundColor, value: h.color, range: safe)
            }
        }
        if tv.attributedText != mutable { tv.attributedText = mutable }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView tv: UITextView, context: Context) -> CGSize? {
        let w = proposal.width ?? UIScreen.main.bounds.width
        let size = tv.sizeThatFits(CGSize(width: w, height: .greatestFiniteMagnitude))
        return CGSize(width: w, height: size.height)
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, UITextViewDelegate {
        var onHighlight: ((Int, Int, String, Int) -> Void)?
        init(onHighlight: ((Int, Int, String, Int) -> Void)?) { self.onHighlight = onHighlight }

        // 链接点击：在 SFSafariViewController 中打开
        func textView(_ textView: UITextView,
                      shouldInteractWith URL: URL,
                      in characterRange: NSRange,
                      interaction: UITextItemInteraction) -> Bool {
            if interaction == .invokeDefaultAction {
                let safari = SFSafariViewController(url: URL)
                UIApplication.shared.connectedScenes
                    .compactMap { ($0 as? UIWindowScene)?.windows.first?.rootViewController }
                    .first?
                    .present(safari, animated: true)
                return false
            }
            return true
        }
    }
}

@available(iOS 16.0, *)
extension TextKit2TextView.Coordinator {
    func textView(_ textView: UITextView,
                  editMenuForTextIn range: UITextRange,
                  suggestedActions: [UIMenuElement]) -> UIMenu? {
        let colors: [(String, Int)] = [("黄色高亮", 0), ("绿色高亮", 1), ("蓝色高亮", 2), ("粉色高亮", 3)]
        let hlItems = colors.map { (title, colorIdx) -> UIAction in
            UIAction(title: title) { [weak textView, weak self] _ in
                guard let tv = textView,
                      let sel = tv.selectedTextRange, !sel.isEmpty else { return }
                let s = tv.offset(from: tv.beginningOfDocument, to: sel.start)
                let e = tv.offset(from: tv.beginningOfDocument, to: sel.end)
                let text = tv.text(in: sel) ?? ""
                self?.onHighlight?(s, e, text, colorIdx)
            }
        }
        let highlightMenu = UIMenu(title: "高亮", image: UIImage(systemName: "highlighter"),
                                   children: hlItems)
        return UIMenu(children: [highlightMenu] + suggestedActions)
    }
}
