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
                    chapterIndex: viewModel.currentChapterIndex
                )
                .tag(idx)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .ignoresSafeArea()
        .onChange(of: viewModel.currentPageIndex) { newIdx in
            if newIdx == viewModel.currentPages.count - 1 {
                viewModel.prefetchNextChapter()  // 并行后台下载，不需要 Task 包装
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

                // 单个 Text 渲染，与分页器 CoreText 计算保持一致，避免 VStack spacing 造成空白偏大
                Text(attributedContent)
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

    /// 构建与分页器一致的 AttributedString（字体、行距、字间距、段间距、颜色）
    private var attributedContent: AttributedString {
        let text = applyTraditional(content)
        var attr = AttributedString(text)

        // 基础字体与颜色
        attr.font = .system(size: settings.fontSize)
        attr.foregroundColor = settings.currentTheme.textColor

        // 字间距（SwiftUI AttributedString 用 kern）
        if settings.letterSpacing != 0 {
            attr.kern = settings.letterSpacing
        }

        // 段间距：在每个 \n 之后插入段落样式
        // 用 NSAttributedString 处理段落样式再转回
        let nsAttr = NSMutableAttributedString(string: text)
        let para = NSMutableParagraphStyle()
        para.lineSpacing = settings.lineSpacing
        para.paragraphSpacing = settings.paragraphSpacing
        nsAttr.addAttributes([
            .font: UIFont.systemFont(ofSize: settings.fontSize),
            .paragraphStyle: para,
            .foregroundColor: UIColor(settings.currentTheme.textColor),
            .kern: settings.letterSpacing,
        ], range: NSRange(location: 0, length: nsAttr.length))

        return (try? AttributedString(nsAttr, including: \.uiKit)) ?? attr
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
    @State private var showingCacheAlert = false

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
            } label: {
                Image(systemName: "ellipsis").font(.title2)
            }
            .alert("缓存全本", isPresented: $showingCacheAlert) {
                Button("开始下载", role: .none) { viewModel.cacheAllChapters() }
                Button("取消", role: .cancel) { }
            } message: {
                Text("将重新下载全部 \(viewModel.chapters.count) 章节，可能需要较长时间，建议在 WiFi 下进行。")
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(
            Color(UIColor.systemBackground).opacity(0.95)
                .ignoresSafeArea(edges: .top)
        )
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
