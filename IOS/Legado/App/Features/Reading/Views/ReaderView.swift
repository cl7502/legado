import SwiftUI
import UIKit

// MARK: - ReaderView

struct ReaderView: View {
    @StateObject var viewModel: ReaderViewModel
    @StateObject var settings  = ReaderSettings.shared
    @Environment(\.dismiss) var dismiss

    var body: some View {
        ZStack {
            settings.currentTheme.backgroundColor.ignoresSafeArea()

            Group {
                if viewModel.currentPages.isEmpty {
                    loadingPlaceholder
                } else if settings.pageMode == .scroll {
                    scrollModeView
                } else {
                    pageModeView
                }
            }

            // 三段式点击区（菜单隐藏时）
            if !viewModel.showingMenu {
                tapZones
            }

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
        .onAppear  { UIApplication.shared.isIdleTimerDisabled = settings.keepScreenOn }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        // B3修复：排版设置变化 → 重新分页
        .onChange(of: settings.fontSize)          { _ in viewModel.paginateCurrentChapter() }
        .onChange(of: settings.lineSpacing)       { _ in viewModel.paginateCurrentChapter() }
        .onChange(of: settings.letterSpacing)     { _ in viewModel.paginateCurrentChapter() }
        .onChange(of: settings.paragraphSpacing)  { _ in viewModel.paginateCurrentChapter() }
        .onChange(of: settings.sideMargin)        { _ in viewModel.paginateCurrentChapter() }
        .onChange(of: settings.topMargin)         { _ in viewModel.paginateCurrentChapter() }
        .onChange(of: settings.bottomMargin)      { _ in viewModel.paginateCurrentChapter() }
        .task { await viewModel.setup() }
    }

    // MARK: 翻页模式
    private var pageModeView: some View {
        TabView(selection: $viewModel.currentPageIndex) {
            ForEach(0..<viewModel.currentPages.count, id: \.self) { idx in
                ReaderPageView(
                    content: viewModel.currentPages[idx],
                    chapterTitle: idx == 0 ? currentChapterTitle : "",
                    pageLabel: "\(idx + 1) / \(viewModel.currentPages.count)",
                    totalChapters: viewModel.chapters.count,
                    chapterIndex: viewModel.currentChapterIndex,
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
                    }
                )
                .tag(idx)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .ignoresSafeArea()
        .onChange(of: viewModel.currentPageIndex) { newIdx in
            if newIdx == viewModel.currentPages.count - 1 {
                viewModel.prefetchNextChapter()
            }
        }
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
        .ignoresSafeArea()
    }

    private var loadingPlaceholder: some View {
        VStack(spacing: 12) {
            ProgressView().tint(settings.currentTheme.textColor)
            Text("加载中...")
                .foregroundColor(settings.currentTheme.textColor)
                .font(.system(size: settings.fontSize))
        }
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
}

// MARK: - ReaderPageView

struct ReaderPageView: View {
    let content: String
    let chapterTitle: String
    let pageLabel: String
    let totalChapters: Int
    let chapterIndex: Int
    var sourceOrigin: String = ""
    var pageStartOffset: Int = 0
    var highlights: [BookHighlight] = []
    var onHighlight: ((Int, Int, String, Int) -> Void)? = nil

    @StateObject private var settings = ReaderSettings.shared
    @StateObject private var battery  = BatteryMonitor.shared

    var body: some View {
        ZStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 0) {
                if !chapterTitle.isEmpty {
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
                    onHighlight: onHighlight
                )
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 0)

                HStack {
                    Spacer()
                    Text(pageLabel)
                        .font(.system(size: 11))
                        .foregroundColor(settings.currentTheme.textColor.opacity(0.5))
                }
            }
            .padding(.horizontal, settings.sideMargin)
            .padding(.top, settings.topMargin)
            .padding(.bottom, settings.bottomMargin)

            // 页眉
            if settings.showHeaderTime || settings.showHeaderProgress || settings.showHeaderBattery {
                HStack {
                    if settings.showHeaderTime {
                        Text(currentTime)
                            .font(.system(size: 11))
                            .foregroundColor(settings.currentTheme.textColor.opacity(0.5))
                    }
                    Spacer()
                    if settings.showHeaderProgress, totalChapters > 0 {
                        Text("\(chapterIndex + 1)/\(totalChapters)章")
                            .font(.system(size: 11))
                            .foregroundColor(settings.currentTheme.textColor.opacity(0.5))
                    }
                    if settings.showHeaderBattery {
                        Text("\(Int(battery.level * 100))%")
                            .font(.system(size: 11))
                            .foregroundColor(settings.currentTheme.textColor.opacity(0.5))
                    }
                }
                .padding(.horizontal, settings.sideMargin)
                .padding(.top, 8)
            }
        }
    }

    /// 构建与 ChapterPaginator.makeAttrString 完全相同的 AttributedString，
    /// 确保渲染高度 = 分页器测量高度，消除底部空白偏大
    private func pageAttributedString(_ text: String) -> AttributedString {
        let font     = UIFont.systemFont(ofSize: settings.fontSize)
        let fixedLineH = font.lineHeight + settings.lineSpacing
        let para = NSMutableParagraphStyle()
        para.minimumLineHeight = fixedLineH
        para.maximumLineHeight = fixedLineH
        para.paragraphSpacing  = settings.paragraphSpacing
        let nsAttr = NSMutableAttributedString(string: text, attributes: [
            .font:            font,
            .paragraphStyle:  para,
            .kern:            settings.letterSpacing,
            .foregroundColor: UIColor(settings.currentTheme.textColor),
        ])
        return (try? AttributedString(nsAttr, including: \.uiKit))
               ?? AttributedString(text)
    }

    private func paragraphs(_ text: String) -> [String] {
        text.components(separatedBy: "\n\n")
            .flatMap { $0.components(separatedBy: "\n") }
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private var currentTime: String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f.string(from: Date())
    }

    private func applyTraditional(_ text: String) -> String {
        guard settings.useTraditionalChinese else { return text }
        return text.applyingTransform(StringTransform("Simplified-Traditional"), reverse: false) ?? text
    }
}

// MARK: - BatteryMonitor

final class BatteryMonitor: ObservableObject {
    static let shared = BatteryMonitor()
    @Published var level: Float = 1.0

    private init() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        level = max(UIDevice.current.batteryLevel, 0)
        NotificationCenter.default.addObserver(self, selector: #selector(batteryLevelChanged),
            name: UIDevice.batteryLevelDidChangeNotification, object: nil)
    }
    @objc private func batteryLevelChanged() {
        DispatchQueue.main.async { self.level = max(UIDevice.current.batteryLevel, 0) }
    }
}

// MARK: - ReaderMenuView

struct ReaderMenuView: View {
    @ObservedObject var viewModel: ReaderViewModel
    @ObservedObject var settings: ReaderSettings
    let onBack: () -> Void

    @State private var showingTOC      = false
    @State private var showingSettings = false
    @State private var brightness: Double = Double(UIScreen.main.brightness)
    @State private var showingCacheAlert  = false
    @State private var showingBookmarks   = false
    @State private var showingSearch      = false
    @State private var showingHighlights  = false

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
                    viewModel.jumpToChapter(max(0, viewModel.currentChapterIndex - 1))
                } label: {
                    Text("上一章").font(.caption2).foregroundColor(.blue)
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
                    let last = viewModel.chapters.count - 1
                    viewModel.jumpToChapter(min(last, viewModel.currentChapterIndex + 1))
                } label: {
                    Text("下一章").font(.caption2).foregroundColor(.blue)
                }
            }
            .padding(.horizontal)

            // 亮度条
            HStack(spacing: 8) {
                Image(systemName: "sun.min").font(.caption).foregroundColor(.secondary)
                Slider(value: $brightness, in: 0.05...1.0) { _ in
                    UIScreen.main.brightness = CGFloat(brightness)
                }
                Image(systemName: "sun.max").font(.caption).foregroundColor(.secondary)
            }
            .padding(.horizontal)

            // 功能按钮行
            HStack(spacing: 0) {
                menuButton(icon: viewModel.isTTSEnabled ? "headphones.circle.fill" : "headphones",
                           label: "朗读",
                           tint: viewModel.isTTSEnabled ? .blue : .primary) {
                    viewModel.toggleTTS()
                }
                menuButton(icon: "list.bullet", label: "目录") { showingTOC = true }
                menuButton(icon: settings.pageMode == .scroll ? "book" : "scroll",
                           label: settings.pageMode == .scroll ? "翻页" : "滚动") {
                    settings.pageMode = settings.pageMode == .scroll ? .page : .scroll
                }
                // B2修复：夜间/白天保存切换前的主题
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
        .padding(.top, 12)
        .background(
            Color(UIColor.systemBackground).opacity(0.95)
                .ignoresSafeArea(edges: .bottom)
        )
        .onAppear { brightness = Double(UIScreen.main.brightness) }
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
}

// MARK: - ReaderSettingsSheet

struct ReaderSettingsSheet: View {
    @StateObject private var settings = ReaderSettings.shared

    var body: some View {
        NavigationView {
            Form {
                Section("字体排版") {
                    stepperRow(title: "字号",   value: $settings.fontSize,         range: 12...40, step: 1)
                    stepperRow(title: "行高",   value: $settings.lineSpacing,       range: 0...30,  step: 1)
                    stepperRow(title: "字间距", value: $settings.letterSpacing,     range: -3...10, step: 0.5)
                    stepperRow(title: "段间距", value: $settings.paragraphSpacing,  range: 0...50,  step: 2)
                }
                Section("页面边距") {
                    stepperRow(title: "左右边距", value: $settings.sideMargin,   range: 0...60, step: 4)
                    stepperRow(title: "上边距",   value: $settings.topMargin,    range: 0...80, step: 4)
                    stepperRow(title: "下边距",   value: $settings.bottomMargin, range: 0...80, step: 4)
                }
                Section("主题") {
                    // B7修复：Form 内 Button 的 tap 区域扩展到整行，用 onTapGesture 代替
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 12) {
                        ForEach(ReaderTheme.allThemes) { theme in
                            VStack(spacing: 4) {
                                Circle().fill(theme.backgroundColor)
                                    .frame(width: 44, height: 44)
                                    .overlay(Circle().stroke(
                                        settings.themeId == theme.id ? Color.blue : Color.clear,
                                        lineWidth: 2.5))
                                Text(theme.name).font(.caption2).foregroundColor(.primary)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if theme.id != "dark" { settings.preNightThemeId = theme.id }
                                settings.themeId = theme.id
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                Section("翻页模式") {
                    Picker("模式", selection: $settings.pageMode) {
                        ForEach(PageMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                Section("页眉信息") {
                    Toggle("显示时间",     isOn: $settings.showHeaderTime)
                    Toggle("显示章节进度", isOn: $settings.showHeaderProgress)
                    Toggle("显示电量",     isOn: $settings.showHeaderBattery)
                }
                Section("高级") {
                    Toggle("屏幕常亮", isOn: $settings.keepScreenOn)
                        .onChange(of: settings.keepScreenOn) { UIApplication.shared.isIdleTimerDisabled = $0 }
                    Toggle("繁体中文", isOn: $settings.useTraditionalChinese)
                }
                Section("朗读") {
                    HStack {
                        Text("语速")
                        Slider(value: Binding(
                            get: { Double(settings.ttsRate) },
                            set: { settings.ttsRate = Float($0) }
                        ), in: 0.25...2.0)
                        Text(String(format: "%.1fx", settings.ttsRate))
                            .font(.caption).frame(width: 36)
                    }
                }
                // F1: 预缓存章节数设置
                Section("缓存") {
                    HStack {
                        Text("预缓存章节数")
                        Spacer()
                        Button { settings.prefetchCount = max(1, settings.prefetchCount - 1) }
                            label: { Image(systemName: "minus.circle") }.buttonStyle(.plain)
                        Text("\(settings.prefetchCount)章")
                            .font(.system(.body, design: .monospaced)).frame(minWidth: 44)
                        Button { settings.prefetchCount = min(50, settings.prefetchCount + 1) }
                            label: { Image(systemName: "plus.circle") }.buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("排版设置")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func stepperRow(title: String, value: Binding<CGFloat>, range: ClosedRange<CGFloat>, step: CGFloat) -> some View {
        HStack {
            Text(title)
            Spacer()
            Button { value.wrappedValue = max(range.lowerBound, value.wrappedValue - step) }
                label: { Image(systemName: "minus.circle") }.buttonStyle(.plain)
            Text(String(format: step < 1 ? "%.1f" : "%.0f", Double(value.wrappedValue)))
                .font(.system(.body, design: .monospaced)).frame(minWidth: 44)
            Button { value.wrappedValue = min(range.upperBound, value.wrappedValue + step) }
                label: { Image(systemName: "plus.circle") }.buttonStyle(.plain)
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

    private static let imgMarker = "⟨IMG:"
    private static let imgEnd    = "⟩"

    var body: some View {
        VStack(alignment: .leading, spacing: settings.lineSpacing) {
            ForEach(segments.indices, id: \.self) { i in
                let seg = segments[i]
                if seg.isImage {
                    CoverImageView(url: seg.text, referer: sourceOrigin)
                        .frame(maxWidth: .infinity)
                        .frame(height: 220)
                        .cornerRadius(4)
                } else if !seg.text.isEmpty {
                    let segOffset = computeSegmentOffset(upTo: i)
                    let pageHighlights = highlights.compactMap { h -> (range: NSRange, color: UIColor)? in
                        // 将章节偏移转为页内偏移，再转为段内偏移
                        let pageStart = pageStartOffset + segOffset
                        let pageEnd   = pageStart + (seg.text as NSString).length
                        let hStart    = max(h.startOffset, pageStart) - pageStart
                        let hEnd      = min(h.endOffset,   pageEnd)   - pageStart
                        guard hEnd > hStart else { return nil }
                        return (NSRange(location: hStart, length: hEnd - hStart), h.uiColor)
                    }
                    TextKit2TextView(
                        text: nsAttributedText(seg.text),
                        backgroundColor: UIColor(settings.currentTheme.backgroundColor),
                        pageStartOffset: pageStartOffset + segOffset,
                        highlights: pageHighlights,
                        onHighlight: onHighlight
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
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
        let fixedH = UIFont.systemFont(ofSize: settings.fontSize).lineHeight + settings.lineSpacing
        para.minimumLineHeight  = fixedH
        para.maximumLineHeight  = fixedH
        para.paragraphSpacing   = settings.paragraphSpacing
        return NSAttributedString(string: text, attributes: [
            .font:           UIFont.systemFont(ofSize: settings.fontSize),
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
        tv.isEditable             = false
        tv.isSelectable           = true
        tv.isUserInteractionEnabled = true
        tv.backgroundColor        = .clear
        tv.textContainerInset     = .zero
        tv.textContainer.lineFragmentPadding = 0
        tv.delegate               = context.coordinator
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
}
