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

            // 执行 init 规则（可能跳转到真实详情页 URL）
            var detailUrl = book.bookUrl
            if let initRule = source.ruleBookInfoInit, !initRule.isEmpty {
                var ctx = AnalyzeContext(source: source, baseUrl: book.bookUrl)
                if let redirectUrl = ruleExecutor.execute(initRule, in: &ctx), !redirectUrl.isEmpty {
                    detailUrl = redirectUrl
                }
            }

            var context = AnalyzeContext(source: source, baseUrl: detailUrl)
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
            VStack(alignment: .leading, spacing: 20) {
                // 顶部卡片
                HStack(alignment: .top, spacing: 15) {
                    // 封面
                    AsyncImage(url: URL(string: viewModel.book.coverUrl ?? "")) { image in
                        image.resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Rectangle().fill(Color.gray.opacity(0.2))
                    }
                    .frame(width: 100, height: 140)
                    .cornerRadius(8)
                    .shadow(radius: 5)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text(viewModel.book.name)
                            .font(.title3)
                            .fontWeight(.bold)
                        
                        Text(viewModel.book.author)
                            .foregroundColor(.secondary)
                        
                        Text("来源: \(viewModel.book.originName)")
                            .font(.caption)
                            .padding(4)
                            .background(Color.blue.opacity(0.1))
                            .foregroundColor(.blue)
                            .cornerRadius(4)
                        
                        Spacer()
                        
                        Button(action: { Task { await viewModel.addToShelf() } }) {
                            Text(viewModel.isSaved ? "已在书架" : "加入书架")
                                .fontWeight(.bold)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(viewModel.isSaved ? Color.gray : Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                        }
                        .disabled(viewModel.isSaved)
                    }
                }
                .padding()
                
                // 简介
                VStack(alignment: .leading, spacing: 10) {
                    Text("简介")
                        .font(.headline)
                    Text(viewModel.book.intro ?? "暂无简介")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineSpacing(5)
                }
                .padding(.horizontal)
            }
        }
        .navigationTitle(viewModel.book.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadDetails()
        }
    }
}
