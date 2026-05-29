import SwiftUI

struct HighlightListView: View {
    let bookUrl: String
    let chapters: [Chapter]
    let onJump: (Int) -> Void

    @StateObject private var vm = HighlightListViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Group {
                if vm.highlights.isEmpty {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "highlighter")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary.opacity(0.5))
                        Text("暂无高亮")
                            .font(.headline).foregroundColor(.secondary)
                        Text("长按阅读页文字选择后可添加高亮")
                            .font(.caption).foregroundColor(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    List {
                        ForEach(vm.highlights) { h in
                            Button {
                                onJump(h.chapterIndex)
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(Color(h.uiColor))
                                            .frame(width: 6, height: 36)
                                        VStack(alignment: .leading, spacing: 2) {
                                            let title = h.chapterIndex < chapters.count
                                                ? chapters[h.chapterIndex].title
                                                : "第\(h.chapterIndex+1)章"
                                            Text(title)
                                                .font(.caption).foregroundColor(.secondary)
                                            Text(h.selectedText)
                                                .font(.body).lineLimit(2)
                                        }
                                        Spacer()
                                        Text(h.createdAt, style: .date)
                                            .font(.caption2).foregroundColor(.secondary)
                                    }
                                    if let note = h.note, !note.isEmpty {
                                        Text("笔记：\(note)")
                                            .font(.caption).foregroundColor(.secondary)
                                            .padding(.leading, 14)
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    Task { await vm.delete(h) }
                                } label: { Label("删除", systemImage: "trash") }
                            }
                        }
                    }
                }
            }
            .navigationTitle("高亮列表")
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

@MainActor
class HighlightListViewModel: ObservableObject {
    @Published var highlights: [BookHighlight] = []
    private let db = DatabaseManager.shared

    func load(bookUrl: String) async {
        highlights = (try? await db.getAllHighlights(bookUrl: bookUrl)) ?? []
    }

    func delete(_ h: BookHighlight) async {
        try? await db.deleteHighlight(h)
        if let idx = highlights.firstIndex(where: { $0.id == h.id }) {
            highlights.remove(at: idx)
        }
    }
}
