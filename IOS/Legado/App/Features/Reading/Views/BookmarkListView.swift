import SwiftUI

// MARK: - 书签列表 Sheet

struct BookmarkListView: View {
    let bookUrl: String
    let onJump: (Int, Int) -> Void   // (chapterIndex, chapterPos)

    @StateObject private var vm = BookmarkListViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Group {
                if vm.bookmarks.isEmpty {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "bookmark")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary.opacity(0.5))
                        Text("暂无书签")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text("在阅读器菜单中点击「添加书签」")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    List {
                        ForEach(vm.bookmarks) { bm in
                            Button {
                                onJump(bm.chapterIndex, bm.chapterPos)
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(bm.chapterTitle)
                                            .font(.headline)
                                            .lineLimit(1)
                                        Spacer()
                                        Text(bm.createdAt, style: .date)
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                    if !bm.content.isEmpty {
                                        Text(bm.content)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .lineLimit(2)
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    Task { await vm.delete(bm) }
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("书签")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .task { await vm.load(bookUrl: bookUrl) }
        }
    }
}

// MARK: - ViewModel

@MainActor
class BookmarkListViewModel: ObservableObject {
    @Published var bookmarks: [Bookmark] = []
    private let db = DatabaseManager.shared

    func load(bookUrl: String) async {
        bookmarks = (try? await db.getBookmarks(bookUrl: bookUrl)) ?? []
    }

    func delete(_ bookmark: Bookmark) async {
        try? await db.deleteBookmark(bookmark)
        if let idx = bookmarks.firstIndex(where: { $0.id == bookmark.id }) {
            bookmarks.remove(at: idx)
        }
    }
}
