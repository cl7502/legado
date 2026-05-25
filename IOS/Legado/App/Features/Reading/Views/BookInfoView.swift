import SwiftUI

/// 书籍详情业务逻辑
@MainActor
class BookInfoViewModel: ObservableObject {
    @Published var book: Book
    @Published var isLoading = false
    @Published var isSaved = false
    
    private let db = DatabaseManager.shared
    private let network = NetworkManager.shared
    private let ruleExecutor = RuleExecutor.shared
    
    init(searchResult: SearchResult) {
        // 从搜索结果初始化初步模型
        self.book = Book(
            bookUrl: searchResult.bookUrl,
            name: searchResult.name,
            author: searchResult.author,
            kind: searchResult.kind,
            intro: searchResult.intro,
            coverUrl: searchResult.coverUrl,
            origin: searchResult.origin,
            originName: searchResult.originName
        )
    }
    
    /// 加载完整书籍详情
    func loadDetails() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let localBooks = try await db.getBookshelf()
            self.isSaved = localBooks.contains { $0.bookUrl == book.bookUrl }

            let sources = try await db.getAllBookSources()
            guard let source = sources.first(where: { $0.bookSourceUrl == book.origin }) else { return }

            // ISSUE-025: ruleBookInfoInit 是初始化 JS（副作用），不是重定向 URL 规则
            // Android BookInfo.analyzeBookInfo() 中此规则只做变量/Cookie 初始化，返回值丢弃
            var detailUrl = book.bookUrl
            var initVariables: [String: Any] = [:]
            if let initRule = source.ruleBookInfoInit, !initRule.isEmpty {
                var ctx = AnalyzeContext(source: source, baseUrl: book.bookUrl)
                _ = ruleExecutor.execute(initRule, in: &ctx)  // 只取副作用（变量/Cookie），忽略返回值
                initVariables = ctx.variables
            }

            var context = AnalyzeContext(source: source, baseUrl: detailUrl)
            context.variables = initVariables
            let html = try await network.request(detailUrl, source: source)
            context.result = html

            // 执行所有详情页规则，有值则覆盖
            if let v = ruleExecutor.execute(source.ruleBookName    ?? "", in: &context), !v.isEmpty { book.name      = v }
            if let v = ruleExecutor.execute(source.ruleBookAuthor  ?? "", in: &context), !v.isEmpty { book.author    = v }
            if let v = ruleExecutor.execute(source.ruleBookIntro   ?? "", in: &context), !v.isEmpty { book.intro     = v }
            if let v = ruleExecutor.execute(source.ruleBookKind    ?? "", in: &context), !v.isEmpty { book.kind      = v }
            if let v = ruleExecutor.execute(source.ruleBookCoverUrl ?? "", in: &context), !v.isEmpty {
                book.coverUrl = resolveUrl(v, base: detailUrl)
            }
            if let v = ruleExecutor.execute(source.ruleBookLastChapter ?? "", in: &context), !v.isEmpty {
                book.latestChapterTitle = v
            }
            if let tocRaw = ruleExecutor.execute(source.ruleTocUrl ?? "", in: &context), !tocRaw.isEmpty {
                book.tocUrl = resolveUrl(tocRaw, base: detailUrl)
            }

        } catch {
            print("❌ [Detail Error]: \(error)")
        }
    }

    private func resolveUrl(_ url: String, base: String) -> String {
        if url.hasPrefix("http") { return url }
        guard let baseURL = URL(string: base),
              let resolved = URL(string: url, relativeTo: baseURL)
        else { return url }
        return resolved.absoluteString
    }
    
    /// 加入书架
    func addToShelf() async {
        do {
            try await db.saveBook(book)
            self.isSaved = true
        } catch {
            print("❌ [DB Error]: \(error)")
        }
    }
}

/// 书籍详情界面
struct BookInfoView: View {
    @StateObject var viewModel: BookInfoViewModel
    @Environment(\.dismiss) var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                // MARK: 顶部信息卡（封面 + 文字信息）
                HStack(alignment: .top, spacing: 15) {
                    AsyncImage(url: URL(string: viewModel.book.coverUrl ?? "")) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Rectangle().fill(Color.gray.opacity(0.2))
                            .overlay(Image(systemName: "book.closed").foregroundColor(.gray))
                    }
                    .frame(width: 100, height: 140)
                    .clipped()
                    .cornerRadius(8)
                    .shadow(radius: 5)

                    // 不使用 Spacer()：ScrollView 提议无限高度，Spacer 扩展至无穷大
                    // 导致 VStack 内容被推到不可见位置（"一片空白"的根因）
                    VStack(alignment: .leading, spacing: 6) {
                        Text(viewModel.book.name)
                            .font(.title3).fontWeight(.bold)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(viewModel.book.author)
                            .font(.subheadline).foregroundColor(.secondary)

                        Text(viewModel.book.originName)
                            .font(.caption)
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(Color.blue.opacity(0.1))
                            .foregroundColor(.blue)
                            .cornerRadius(4)
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)
                .padding(.horizontal)

                // MARK: 加入书架按钮（独占一行，宽度充足，不受 Spacer 影响）
                Button(action: { Task { await viewModel.addToShelf() } }) {
                    Text(viewModel.isSaved ? "已在书架" : "加入书架")
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(viewModel.isSaved ? Color.gray : Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .disabled(viewModel.isSaved)
                .padding(.horizontal)

                // MARK: 简介
                VStack(alignment: .leading, spacing: 8) {
                    Text("简介").font(.headline)
                    Text(viewModel.book.intro ?? "暂无简介")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineSpacing(5)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)
                .padding(.horizontal)

                Spacer(minLength: 20)
            }
            .padding(.top, 12)
        }
        .overlay {
            if viewModel.isLoading {
                VStack {
                    Spacer()
                    ProgressView("加载中...")
                        .padding(20)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(12)
                        .shadow(radius: 4)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .background(Color(.systemBackground).opacity(0.6))
            }
        }
        .navigationTitle(viewModel.book.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadDetails()
        }
    }
}
