import SwiftUI

/// 高性能沉浸式阅读器
struct ReaderView: View {
    @StateObject var viewModel: ReaderViewModel
    @StateObject var settings = ReaderSettings.shared
    
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        ZStack {
            // 1. 背景层
            settings.currentTheme.backgroundColor
                .ignoresSafeArea()
            
            // 2. 正文层
            ScrollView {
                VStack(alignment: .leading, spacing: settings.lineSpacing) {
                    // 章节标题
                    if viewModel.currentChapterIndex < viewModel.chapters.count {
                        Text(viewModel.chapters[viewModel.currentChapterIndex].title)
                            .font(.system(size: settings.fontSize + 4, weight: .bold))
                            .foregroundColor(settings.currentTheme.textColor)
                            .padding(.bottom, 20)
                    }
                    
                    // 正文内容
                    Text(viewModel.currentContent)
                        .font(.system(size: settings.fontSize))
                        .lineSpacing(settings.lineSpacing)
                        .foregroundColor(settings.currentTheme.textColor)
                }
                .padding(.horizontal, settings.sideMargin)
                .padding(.vertical, 40)
            }
            
            // 3. 透明点击层 (三段式分区交互)
            HStack(spacing: 0) {
                // 左侧 1/3: 上一页/章
                Color.clear.contentShape(Rectangle())
                    .onTapGesture { viewModel.prevChapter() }
                
                // 中间 1/3: 菜单
                Color.clear.contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation { viewModel.showingMenu.toggle() }
                    }
                
                // 右侧 1/3: 下一页/章
                Color.clear.contentShape(Rectangle())
                    .onTapGesture { viewModel.nextChapter() }
            }
            .ignoresSafeArea()
            
            // 4. 菜单层
            if viewModel.showingMenu {
                ReaderMenuView(viewModel: viewModel, settings: settings) {
                    dismiss()
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .navigationBarHidden(true)
        .statusBar(hidden: !viewModel.showingMenu)
        .task {
            await viewModel.setup()
        }
    }
}

/// 阅读器菜单组件
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
                        Image(systemName: "chevron.left")
                            .font(.title2)
                    }
                    Spacer()
                    Text(viewModel.book.name)
                        .font(.headline)
                    Spacer()
                    Button(action: { /* 更多设置 */ }) {
                        Image(systemName: "ellipsis")
                            .font(.title2)
                    }
                }
                .padding()
            }
            .background(Color(UIColor.systemBackground).opacity(0.95))
            
            Spacer()
            
            // 底部控制面板
            VStack(spacing: 20) {
                // 进度滑动条
                HStack {
                    Text("上一章").font(.caption)
                    Slider(value: Binding(
                        get: { Double(viewModel.currentChapterIndex) },
                        set: { viewModel.jumpToChapter(Int($0)) }
                    ), in: 0...Double(max(0, viewModel.chapters.count - 1)))
                    Text("下一章").font(.caption)
                }
                .padding(.horizontal)
                
                // 功能按钮
                HStack(spacing: 40) {
                    Button(action: { showingTOC = true }) {
                        VStack {
                            Image(systemName: "list.bullet")
                            Text("目录").font(.caption2)
                        }
                    }
                    
                    Button(action: { /* 夜间模式切换 */ }) {
                        VStack {
                            Image(systemName: "moon")
                            Text("夜间").font(.caption2)
                        }
                    }
                    
                    Button(action: { showingSettings = true }) {
                        VStack {
                            Image(systemName: "textformat.size")
                            Text("设置").font(.caption2)
                        }
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
