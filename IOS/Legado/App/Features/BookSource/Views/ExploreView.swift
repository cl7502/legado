import SwiftUI

// MARK: - ISSUE-024 修复：三级导航各自持有独立 ViewModel
// 原实现三级视图共用同一 ExploreViewModel，loadBooks() 触发 @Published 变更时，
// 父层 categoryView 的 .task 被重新触发 → categories = [] → 导航栈闪退。
// 修复：每级视图创建独立 @StateObject，互不观察彼此状态。

// MARK: - 第一级：书源列表

struct ExploreView: View {
    @StateObject private var vm = ExploreSourcesViewModel()

    var body: some View {
        NavigationView {
            List(vm.sources) { source in
                NavigationLink(source.bookSourceName) {
                    ExploreCategoryView(source: source)
                }
            }
            .navigationTitle("发现")
            .overlay {
                if vm.isLoading {
                    ProgressView("加载书源...")
                } else if vm.sources.isEmpty {
                    ContentUnavailableView(
                        "暂无发现书源",
                        systemImage: "safari",
                        description: Text("请先在书源管理中导入支持发现功能的书源")
                    )
                }
            }
            .task { await vm.loadSources() }
        }
    }
}

// MARK: - 第二级：分类列表（独立 ViewModel，与书单层解耦）

struct ExploreCategoryView: View {
    let source: BookSource
    @StateObject private var vm = ExploreCategoryViewModel()

    var body: some View {
        List(vm.categories) { category in
            NavigationLink(category.title) {
                ExploreBookListView(source: source, category: category)
            }
        }
        .navigationTitle(source.bookSourceName)
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if vm.isLoading {
                ProgressView("加载分类...")
            } else if vm.categories.isEmpty {
                ContentUnavailableView("暂无分类", systemImage: "list.bullet", description: Text(""))
            }
        }
        .task { await vm.loadCategories(source: source) }
    }
}

// MARK: - 第三级：书单（独立 ViewModel，不影响上两级）

struct ExploreBookListView: View {
    let source: BookSource
    let category: ExploreCategory
    @StateObject private var vm = ExploreBookListViewModel()

    var body: some View {
        List(vm.books) { book in
            NavigationLink {
                BookInfoView(viewModel: BookInfoViewModel(searchResult: book))
            } label: {
                ExploreBookRow(book: book)
            }
        }
        .navigationTitle(category.title)
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if vm.isLoading {
                ProgressView("加载书单...")
            } else if !vm.loadError.isEmpty {
                ContentUnavailableView(
                    "加载失败",
                    systemImage: "exclamationmark.triangle",
                    description: Text(vm.loadError)
                )
            } else if vm.books.isEmpty {
                ContentUnavailableView("暂无书籍", systemImage: "books.vertical", description: Text(""))
            }
        }
        .task { await vm.loadBooks(source: source, url: category.url) }
    }
}

// MARK: - 书单行

private struct ExploreBookRow: View {
    let book: SearchResult

    var body: some View {
        HStack(spacing: 12) {
            CoverImageView(url: book.coverUrl, referer: book.origin)
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

// MARK: - ViewModels（三级各自独立）

@MainActor
class ExploreSourcesViewModel: ObservableObject {
    @Published var sources: [BookSource] = []
    @Published var isLoading = false
    private let db = DatabaseManager.shared

    func loadSources() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let all = try await db.getAllBookSources()
            sources = all.filter {
                guard $0.enabled else { return false }
                let hasUrl  = ($0.exploreUrl ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                let hasRule = ($0.ruleExploreList ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                return hasUrl && hasRule
            }
        } catch {
            print("❌ [ExploreSourcesVM] \(error)")
        }
    }
}

@MainActor
class ExploreCategoryViewModel: ObservableObject {
    @Published var categories: [ExploreCategory] = []
    @Published var isLoading = false

    func loadCategories(source: BookSource) async {
        isLoading = true
        defer { isLoading = false }
        guard !(source.exploreUrl ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let ctx = AnalyzeContext(source: source, baseUrl: source.bookSourceUrl)
        categories = ExploreUrlParser.parse(source.exploreUrl ?? "", context: ctx)
    }
}

@MainActor
class ExploreBookListViewModel: ObservableObject {
    @Published var books: [SearchResult] = []
    @Published var isLoading = false
    @Published var loadError = ""
    private let network = NetworkManager.shared
    private let ruleExecutor = RuleExecutor.shared

    func loadBooks(source: BookSource, url: String) async {
        isLoading = true
        books = []
        loadError = ""
        defer { isLoading = false }

        let listRule = source.ruleExploreList ?? ""
        guard !listRule.isEmpty else {
            loadError = "书源未配置 ruleExploreList"
            return
        }

        do {
            var parseCtx = AnalyzeContext(source: source, baseUrl: source.bookSourceUrl)
            parseCtx.variables["page"] = "1"
            let parsed = AnalyzeUrl.parse(url, variables: ["page": "1"], context: parseCtx)
            let requestUrl = resolveUrl(parsed.url, base: source.bookSourceUrl)

            guard requestUrl.lowercased().hasPrefix("http") else {
                loadError = "无效的发现 URL（非 http 且无法解析）: \(url)"
                return
            }

            // JS-driven list rules (starting with <js> or @js:) perform their own
            // network requests via java.ajax(). Pre-fetching the category URL is not
            // only unnecessary — it can cause early-return on failure and blocks the
            // JS from running at all. Pass the URL as baseUrl and let JS handle it.
            let isJSRule = listRule.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<js>") ||
                           listRule.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("@js:")
            let html: String
            if isJSRule {
                html = ""
            } else if parsed.method == "POST", let body = parsed.body {
                html = try await network.requestPost(requestUrl, body: body, source: source)
            } else {
                html = try await network.request(requestUrl, source: source)
            }

            var htmlCtx = AnalyzeContext(source: source, baseUrl: requestUrl)
            htmlCtx.result = html
            let items = ruleExecutor.executeList(listRule, in: &htmlCtx)

            var results: [SearchResult] = []
            for item in items {
                var itemCtx = AnalyzeContext(source: source, baseUrl: requestUrl)
                itemCtx.result = item

                let name    = ruleExecutor.execute(source.ruleExploreName    ?? "", in: &itemCtx) ?? ""
                let author  = ruleExecutor.execute(source.ruleExploreAuthor  ?? "", in: &itemCtx) ?? ""
                // 剥离 URL options JSON（如 url,{"js":"..."}），只保留纯 URL
                let rawBookUrl = ruleExecutor.execute(source.ruleExploreNoteUrl ?? "", in: &itemCtx) ?? ""
                let bookUrl    = AnalyzeUrl.parse(rawBookUrl, context: itemCtx).url
                let coverUrl = ruleExecutor.execute(source.ruleExploreCoverUrl ?? "", in: &itemCtx)
                let kind    = ruleExecutor.execute(source.ruleExploreKind    ?? "", in: &itemCtx)

                guard !name.isEmpty, !bookUrl.isEmpty else { continue }

                var result = SearchResult()
                result.name = name
                result.author = author
                result.bookUrl = resolveUrl(bookUrl, base: requestUrl)
                result.kind = kind
                result.coverUrl = coverUrl.map { resolveUrl($0, base: requestUrl) }
                result.origin = source.bookSourceUrl
                result.originName = source.bookSourceName
                results.append(result)
            }
            books = results
        } catch {
            loadError = error.localizedDescription
            print("❌ [ExploreBookListVM] \(error)")
        }
    }

    private func resolveUrl(_ path: String, base: String) -> String {
        if path.lowercased().hasPrefix("http") { return path }
        // Protocol-relative: "//example.com/path"
        if path.hasPrefix("//") {
            let scheme = base.hasPrefix("https") ? "https:" : "http:"
            return scheme + path
        }
        guard let baseURL = URL(string: base),
              let resolved = URL(string: path, relativeTo: baseURL)
        else { return path }
        return resolved.absoluteString
    }
}

// ExploreCategory is defined in Core/Services/ExploreUrlParser.swift
