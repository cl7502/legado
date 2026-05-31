import SwiftUI

/// 搜索界面
struct SearchView: View {
    @StateObject private var viewModel = SearchViewModel()
    @State private var searchText = ""

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // 搜索进度条
                if viewModel.isSearching {
                    ProgressView(value: viewModel.searchProgress)
                        .progressViewStyle(LinearProgressViewStyle())
                        .frame(height: 2)
                }

                List {
                    ForEach(viewModel.searchResults) { result in
                        // 使用惰性目标视图：BookInfoViewModel 仅在导航发生时才创建
                        NavigationLink {
                            BookInfoLazyView(result: result)
                        } label: {
                            SearchResultRow(result: result)
                        }
                    }
                }
                .listStyle(PlainListStyle())
            }
            .navigationTitle("搜索书籍")
            .searchable(text: $searchText, prompt: "输入书名或作者...")
            .onSubmit(of: .search) {
                viewModel.search(searchText)
            }
            .overlay {
                if viewModel.searchResults.isEmpty && !viewModel.isSearching {
                    ContentUnavailableView("开始探索", systemImage: "magnifyingglass", description: Text("输入关键词搜索全网书源"))
                }
            }
        }
    }
}

/// 惰性包装：body 在导航时才执行，避免 List 渲染期间大量创建 BookInfoViewModel
private struct BookInfoLazyView: View {
    let result: SearchResult
    var body: some View {
        BookInfoView(viewModel: BookInfoViewModel(searchResult: result))
    }
}

/// 搜索结果行组件
struct SearchResultRow: View {
    let result: SearchResult
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // 简单占位封面
            Rectangle()
                .fill(Color.gray.opacity(0.2))
                .frame(width: 60, height: 80)
                .cornerRadius(4)
                .overlay(Image(systemName: "book").foregroundColor(.gray))
            
            VStack(alignment: .leading, spacing: 4) {
                Text(result.name)
                    .font(.headline)
                
                HStack {
                    Text(result.author)
                    Text("|")
                    Text(result.originName)
                }
                .font(.caption)
                .foregroundColor(.secondary)
                
                if let intro = result.intro {
                    Text(intro)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// 适配 iOS 17 以下的 ContentUnavailableView 模拟
#if !os(iOS) || (os(iOS) && !targetEnvironment(macCatalyst))
@available(iOS, introduced: 13.0, deprecated: 17.0, message: "Use ContentUnavailableView directly in iOS 17+")
struct ContentUnavailableView: View {
    let title: String
    let systemImage: String
    let description: Text
    
    init(_ title: String, systemImage: String, description: Text) {
        self.title = title
        self.systemImage = systemImage
        self.description = description
    }
    
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 60))
                .foregroundColor(.gray)
            Text(title)
                .font(.title2)
                .fontWeight(.bold)
            description
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
}
#endif
