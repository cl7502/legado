import SwiftUI

/// 书架视图
struct BookshelfView: View {
    @StateObject private var viewModel = BookshelfViewModel()

    @State private var selectedBook: Book?

    @State private var bookPendingDelete: Book? = nil
    @State private var showDeleteConfirm = false

    // 定义 3 列网格
    let columns = [
        GridItem(.flexible(), spacing: 20),
        GridItem(.flexible(), spacing: 20),
        GridItem(.flexible(), spacing: 20)
    ]

    var body: some View {
        NavigationView {
            ScrollView {
                if viewModel.books.isEmpty && !viewModel.isLoading {
                    VStack(spacing: 20) {
                        Image(systemName: "book.closed")
                            .font(.system(size: 80))
                            .foregroundColor(.gray)
                        Text("书架空空如也\n去搜索书源添加书籍吧")
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 100)
                } else {
                    LazyVGrid(columns: columns, spacing: 25) {
                        ForEach(viewModel.sortedBooks) { book in
                            BookItemView(book: book)
                                .onTapGesture {
                                    selectedBook = book
                                }
                                .contextMenu {
                                    Button(role: .destructive) {
                                        bookPendingDelete = book
                                        showDeleteConfirm = true
                                    } label: {
                                        Label("从书架删除", systemImage: "trash")
                                    }
                                }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Legado")
            .toolbar {
                // P2-C: 排序 Menu
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        ForEach(BookshelfViewModel.SortOrder.allCases, id: \.self) { order in
                            Button {
                                viewModel.sortOrder = order
                            } label: {
                                HStack {
                                    Text(order.rawValue)
                                    if viewModel.sortOrder == order {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                }

                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { /* 切换列表/网格模式 */ }) {
                        Image(systemName: "square.grid.2x2")
                    }
                }
            }
            .task {
                await viewModel.loadBooks()
            }
            .refreshable {
                await viewModel.loadBooks()
            }
            .alert("删除书籍", isPresented: $showDeleteConfirm, presenting: bookPendingDelete) { book in
                Button("取消", role: .cancel) {}
                Button("删除", role: .destructive) {
                    Task { await viewModel.deleteBook(book) }
                }
            } message: { book in
                Text("将从书架移除《\(book.name)》，阅读进度和缓存章节也会一并清除，不影响书源。")
            }
            // 用 item: 绑定，避免 isPresented + 独立 selectedBook 的时序竞态：
            // fullScreenCover(isPresented:) 可能在 selectedBook 提交前就渲染闭包，
            // 导致 if let book = selectedBook 为 nil，显示空白 EmptyView。
            .fullScreenCover(item: $selectedBook, onDismiss: {
                Task { await viewModel.loadBooks() }
            }) { book in
                ReaderView(viewModel: ReaderViewModel(book: book))
            }
        }
    }
}

/// 单个书籍封面组件
struct BookItemView: View {
    let book: Book
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 封面图
            ZStack(alignment: .bottomTrailing) {
                if let coverUrl = book.coverUrl, let url = URL(string: coverUrl) {
                    AsyncImage(url: url) { image in
                        image.resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Rectangle().fill(Color.gray.opacity(0.2))
                            .overlay(Image(systemName: "book").foregroundColor(.gray))
                    }
                    .frame(height: 140)
                    .clipped()
                    .cornerRadius(8)
                    .shadow(radius: 3)
                } else {
                    Rectangle().fill(Color.gray.opacity(0.2))
                        .frame(height: 140)
                        .cornerRadius(8)
                }
                
                // 阅读进度小标签
                Text("\(Int(Double(book.durChapterIndex + 1) / Double(max(1, book.totalChapterNum)) * 100))%")
                    .font(.system(size: 9, weight: .bold))
                    .padding(4)
                    .background(Color.black.opacity(0.6))
                    .foregroundColor(.white)
                    .cornerRadius(4)
                    .padding(4)
            }
            
            // 书名
            Text(book.name)
                .font(.system(size: 14, weight: .medium))
                .lineLimit(2)
                .frame(height: 34, alignment: .topLeading)
            
            // 进度文字
            Text("读至: \(book.durChapterTitle ?? "尚未阅读")")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
    }
}
