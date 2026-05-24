import SwiftUI

/// 发现（Explore）功能视图 — 三级导航：书源 → 分类 → 书单
struct ExploreView: View {
    @StateObject private var viewModel = ExploreViewModel()

    var body: some View {
        NavigationStack {
            sourceListView
                .navigationTitle("发现")
                .task { await viewModel.loadSources() }
        }
    }

    // MARK: 第一级：书源列表

    private var sourceListView: some View {
        List(viewModel.sources) { source in
            NavigationLink(source.bookSourceName) {
                categoryView(for: source)
                    .task { await viewModel.loadCategories(source: source) }
            }
        }
        .overlay {
            if viewModel.isLoadingSources {
                ProgressView("加载书源...")
            } else if viewModel.sources.isEmpty {
                ContentUnavailableView(
                    "暂无发现书源",
                    systemImage: "safari",
                    description: Text("请先在书源管理中导入支持发现功能的书源")
                )
            }
        }
    }

    // MARK: 第二级：分类列表

    @ViewBuilder
    private func categoryView(for source: BookSource) -> some View {
        List(viewModel.categories) { category in
            NavigationLink(category.title) {
                bookListView(source: source, category: category)
                    .task { await viewModel.loadBooks(source: source, url: category.url) }
            }
        }
        .navigationTitle(source.bookSourceName)
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if viewModel.isLoadingCategories {
                ProgressView("加载分类...")
            } else if viewModel.categories.isEmpty {
                ContentUnavailableView("暂无分类", systemImage: "list.bullet")
            }
        }
    }

    // MARK: 第三级：书单

    @ViewBuilder
    private func bookListView(source: BookSource, category: ExploreCategory) -> some View {
        List(viewModel.books) { book in
            NavigationLink {
                BookInfoView(viewModel: BookInfoViewModel(searchResult: book))
            } label: {
                ExploreBookRow(book: book)
            }
        }
        .navigationTitle(category.title)
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if viewModel.isLoadingBooks {
                ProgressView("加载书单...")
            } else if !viewModel.bookLoadError.isEmpty {
                ContentUnavailableView(
                    "加载失败",
                    systemImage: "exclamationmark.triangle",
                    description: Text(viewModel.bookLoadError)
                )
            } else if viewModel.books.isEmpty {
                ContentUnavailableView("暂无书籍", systemImage: "books.vertical")
            }
        }
    }
}

// MARK: - 书单行

private struct ExploreBookRow: View {
    let book: SearchResult

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: URL(string: book.coverUrl ?? "")) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle().fill(Color.secondary.opacity(0.2))
                    .overlay(Image(systemName: "book.closed").foregroundColor(.secondary))
            }
            .frame(width: 48, height: 64)
            .cornerRadius(4)

            VStack(alignment: .leading, spacing: 4) {
                Text(book.name).font(.headline).lineLimit(1)
                Text(book.author).font(.subheadline).foregroundColor(.secondary).lineLimit(1)
                if let kind = book.kind, !kind.isEmpty {
                    Text(kind).font(.caption).foregroundColor(.accentColor).lineLimit(1)
                }
                if let intro = book.intro, !intro.isEmpty {
                    Text(intro).font(.caption2).foregroundColor(.secondary).lineLimit(2)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - ViewModel

@MainActor
class ExploreViewModel: ObservableObject {
    @Published var sources: [BookSource] = []
    @Published var categories: [ExploreCategory] = []
    @Published var books: [SearchResult] = []

    @Published var isLoadingSources = false
    @Published var isLoadingCategories = false
    @Published var isLoadingBooks = false
    @Published var bookLoadError = ""

    private let db = DatabaseManager.shared
    private let network = NetworkManager.shared
    private let ruleExecutor = RuleExecutor.shared

    // MARK: 加载有发现功能的书源

    func loadSources() async {
        isLoadingSources = true
        defer { isLoadingSources = false }
        do {
            let all = try await db.getAllBookSources()
            sources = all.filter {
                guard let url = $0.exploreUrl else { return false }
                return !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
        } catch {
            print("❌ [ExploreVM] loadSources: \(error)")
        }
    }

    // MARK: 解析书源分类

    func loadCategories(source: BookSource) async {
        isLoadingCategories = true
        categories = []
        defer { isLoadingCategories = false }

        guard let raw = source.exploreUrl,
              !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        // 尝试解析 JSON 数组格式 [{"title":"...","url":"..."}]
        if let data = raw.data(using: .utf8),
           let arr = try? JSONDecoder().decode([ExploreCategory].self, from: data) {
            categories = arr
            return
        }

        // 退化为单一 URL，title = "全部"
        categories = [ExploreCategory(title: "全部", url: raw)]
    }

    // MARK: 加载书单

    func loadBooks(source: BookSource, url: String) async {
        isLoadingBooks = true
        books = []
        bookLoadError = ""
        defer { isLoadingBooks = false }

        do {
            let html = try await network.fetchString(url: url, headers: source.headerDictionary)

            let listRule = source.ruleExploreList ?? ""
            guard !listRule.isEmpty else {
                bookLoadError = "书源未配置 ruleExploreList"
                return
            }

            let context = AnalyzeContext(content: html, baseUrl: url, source: source)
            let items = try await ruleExecutor.getElements(rule: listRule, context: context)

            var results: [SearchResult] = []
            for item in items {
                let itemCtx = AnalyzeContext(content: item, baseUrl: url, source: source)
                let name = (try? await ruleExecutor.getString(
                    rule: source.ruleExploreName ?? "", context: itemCtx)) ?? ""
                let author = (try? await ruleExecutor.getString(
                    rule: source.ruleExploreAuthor ?? "", context: itemCtx)) ?? ""
                let bookUrl = (try? await ruleExecutor.getString(
                    rule: source.ruleExploreNoteUrl ?? "", context: itemCtx)) ?? ""
                let coverUrl = (try? await ruleExecutor.getString(
                    rule: source.ruleExploreCoverUrl ?? "", context: itemCtx))
                let kind = (try? await ruleExecutor.getString(
                    rule: source.ruleExploreKind ?? "", context: itemCtx))

                guard !name.isEmpty, !bookUrl.isEmpty else { continue }

                results.append(SearchResult(
                    name: name,
                    author: author,
                    bookUrl: bookUrl,
                    kind: kind,
                    intro: nil,
                    coverUrl: coverUrl,
                    origin: source.bookSourceUrl,
                    originName: source.bookSourceName
                ))
            }
            books = results
        } catch {
            bookLoadError = error.localizedDescription
            print("❌ [ExploreVM] loadBooks: \(error)")
        }
    }
}

// MARK: - 数据模型

struct ExploreCategory: Codable, Identifiable {
    var id: String { url }
    var title: String
    var url: String
}
