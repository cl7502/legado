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
            // 1. 检查是否已经在书架
            let localBooks = try await db.getBookshelf()
            self.isSaved = localBooks.contains { $0.bookUrl == book.bookUrl }
            
            // 2. 从网络抓取详情
            let sources = try await db.getAllBookSources()
            guard let source = sources.first(where: { $0.bookSourceUrl == book.origin }) else { return }
            
            var context = AnalyzeContext(source: source, baseUrl: book.bookUrl)
            let html = try await network.request(book.bookUrl, source: source)
            context.result = html
            
            // 执行详情页规则
            if let intro = ruleExecutor.execute(source.ruleBookIntro ?? "", in: &context) {
                book.intro = intro
            }
            if let tocUrl = ruleExecutor.execute(source.ruleTocUrl ?? "", in: &context) {
                book.tocUrl = tocUrl
            }
            // ... 更多字段补全
            
        } catch {
            print("❌ [Detail Error]: \(error)")
        }
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
