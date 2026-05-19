import SwiftUI

/// 书架视图
struct BookshelfView: View {
    @StateObject private var viewModel = BookshelfViewModel()
    
    @State private var selectedBook: Book?
    @State private var isReaderPresented = false
    
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
                        ForEach(viewModel.books) { book in
                            BookItemView(book: book)
                                .onTapGesture {
                                    selectedBook = book
                                    isReaderPresented = true
                                }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Legado")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
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
            .fullScreenCover(isPresented: $isReaderPresented, onDismiss: {
                Task { await viewModel.loadBooks() } // 退出阅读器时刷新进度
            }) {
                if let book = selectedBook {
                    ReaderView(viewModel: ReaderViewModel(book: book))
                }
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
