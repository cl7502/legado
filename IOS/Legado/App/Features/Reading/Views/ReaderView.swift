import SwiftUI

/// 高性能沉浸式阅读器 (V2.0 仿真版)
struct ReaderView: View {
    @StateObject var viewModel: ReaderViewModel
    @StateObject var settings = ReaderSettings.shared
    
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        ZStack {
            // 1. 背景层
            settings.currentTheme.backgroundColor
                .ignoresSafeArea()
            
            // 2. 正文层 (仿真分页容器)
            // 使用 TabView 模拟水平翻页体验
            TabView(selection: $viewModel.currentChapterIndex) {
                ForEach(0..<viewModel.chapters.count, id: \.self) { index in
                    ReaderPageContent(content: viewModel.currentContent, chapterTitle: viewModel.chapters[index].title)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .onChange(of: viewModel.currentChapterIndex) { _ in
                Task { await viewModel.loadCurrentChapter() }
            }
            
            // 3. 透明点击层 (三段式分区交互)
            // 注意：在 TabView 模式下，左右点击层可能与滑动冲突，此处优先支持滑动，点击中间唤起菜单
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    Color.clear.contentShape(Rectangle())
                        .onTapGesture { viewModel.prevChapter() }
                        .frame(width: geometry.size.width / 3)
                    
                    Color.clear.contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation { viewModel.showingMenu.toggle() }
                        }
                        .frame(width: geometry.size.width / 3)
                    
                    Color.clear.contentShape(Rectangle())
                        .onTapGesture { viewModel.nextChapter() }
                        .frame(width: geometry.size.width / 3)
                }
            }
            .ignoresSafeArea()
            
            // 4. 菜单层
            if viewModel.showingMenu {
                ReaderMenuView(viewModel: viewModel, settings: settings) {
                    dismiss()
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            
            // 5. 加载状态
            if viewModel.isLoading {
                ProgressView()
                    .padding()
                    .background(Color.black.opacity(0.4))
                    .cornerRadius(10)
                    .foregroundColor(.white)
            }
        }
        .navigationBarHidden(true)
        .statusBar(hidden: !viewModel.showingMenu)
        .task {
            await viewModel.setup()
        }
    }
}

/// 单个页面的渲染组件
struct ReaderPageContent: View {
    let content: String
    let chapterTitle: String
    @StateObject var settings = ReaderSettings.shared
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: settings.lineSpacing) {
                Text(chapterTitle)
                    .font(.system(size: settings.fontSize + 6, weight: .bold))
                    .foregroundColor(settings.currentTheme.textColor)
                    .padding(.bottom, 20)
                
                Text(content)
                    .font(.system(size: settings.fontSize))
                    .lineSpacing(settings.lineSpacing)
                    .foregroundColor(settings.currentTheme.textColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, settings.sideMargin)
            .padding(.vertical, 40)
        }
    }
}

/// 阅读器菜单组件 (保持不变)
struct ReaderMenuView: View {
    @ObservedObject var viewModel: ReaderViewModel
    @ObservedObject var settings: ReaderSettings
    let onBack: () -> Void
    
    @State private var showingTOC = false
    @State private var showingSettings = false
    
    var body: some View {
        VStack(spacing: 0) {
            // 顶部菜单
            VStack {
                Spacer().frame(height: 50)
                HStack {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left").font(.title2)
                    }
                    Spacer()
                    Text(viewModel.book.name).font(.headline)
                    Spacer()
                    Button(action: { }) {
                        Image(systemName: "ellipsis").font(.title2)
                    }
                }
                .padding()
            }
            .background(Color(UIColor.systemBackground).opacity(0.95))
            
            Spacer()
            
            // 底部控制面板
            VStack(spacing: 20) {
                HStack {
                    Text("上一章").font(.caption)
                    Slider(value: Binding(
                        get: { Double(viewModel.currentChapterIndex) },
                        set: { viewModel.jumpToChapter(Int($0)) }
                    ), in: 0...Double(max(0, viewModel.chapters.count - 1)))
                    Text("下一章").font(.caption)
                }
                .padding(.horizontal)
                
                HStack(spacing: 40) {
                    Button(action: { showingTOC = true }) {
                        VStack { Image(systemName: "list.bullet"); Text("目录").font(.caption2) }
                    }
                    Button(action: { }) {
                        VStack { Image(systemName: "moon"); Text("夜间").font(.caption2) }
                    }
                    Button(action: { showingSettings = true }) {
                        VStack { Image(systemName: "textformat.size"); Text("设置").font(.caption2) }
                    }
                }
                .padding(.bottom, 30)
            }
            .background(Color(UIColor.systemBackground).opacity(0.95))
        }
        .foregroundColor(.primary)
        .sheet(isPresented: $showingTOC) {
            TOCView(viewModel: viewModel)
        }
        .sheet(isPresented: $showingSettings) {
            ReaderSettingsSheet()
        }
    }
}
