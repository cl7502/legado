import SwiftUI

// MARK: - 书内搜索 Sheet

struct BookSearchView: View {
    let bookUrl: String
    let chapterContents: [Int: String]     // chapterIndex → content
    let chapters: [Chapter]
    let onJump: (Int) -> Void              // 跳转到 chapterIndex

    @StateObject private var vm = BookSearchViewModel()
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                searchBar
                Divider()
                resultList
            }
            .navigationTitle("搜索本书")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .onAppear { focused = true }
        }
    }

    // MARK: - 搜索框

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundColor(.secondary)
            TextField("输入关键词", text: $vm.query)
                .focused($focused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .onChange(of: vm.query) { _ in
                    vm.search(in: chapterContents, chapters: chapters)
                }
            if !vm.query.isEmpty {
                Button { vm.query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                }
            }
        }
        .padding(10)
    }

    // MARK: - 结果列表

    @ViewBuilder
    private var resultList: some View {
        if vm.query.isEmpty {
            emptyState(icon: "magnifyingglass", title: "输入关键词开始搜索")
        } else if vm.results.isEmpty {
            emptyState(icon: "magnifyingglass", title: "未找到 \"\(vm.query)\"")
        } else {
            List(vm.results) { result in
                Button {
                    onJump(result.chapterIndex)
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(result.chapterTitle)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        HighlightText(result.snippet, keyword: vm.query)
                            .font(.body)
                            .lineLimit(3)
                    }
                    .padding(.vertical, 2)
                }
                .buttonStyle(.plain)
            }
            .overlay(alignment: .bottom) {
                Text("共 \(vm.results.count) 处匹配（已缓存章节）")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 8)
            }
        }
    }

    private func emptyState(icon: String, title: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.5))
            Text(title)
                .font(.headline)
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 结果模型（避免与 SearchResult.swift 命名冲突）

struct BookSearchMatch: Identifiable {
    let id = UUID()
    let chapterIndex: Int
    let chapterTitle: String
    let snippet: String          // 含关键词上下文约100字
}

// MARK: - ViewModel

@MainActor
class BookSearchViewModel: ObservableObject {
    @Published var query: String = ""
    @Published var results: [BookSearchMatch] = []

    func search(in contents: [Int: String], chapters: [Chapter]) {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 1 else { results = []; return }

        var found: [BookSearchMatch] = []
        for (idx, content) in contents.sorted(by: { $0.key < $1.key }) {
            let title = idx < chapters.count ? chapters[idx].title : "第\(idx+1)章"
            var searchFrom = content.startIndex
            while let range = content.range(of: q, options: .caseInsensitive, range: searchFrom..<content.endIndex) {
                let snippet = extractSnippet(from: content, around: range)
                found.append(BookSearchMatch(chapterIndex: idx, chapterTitle: title, snippet: snippet))
                searchFrom = range.upperBound
                if found.count >= 200 { break }
            }
            if found.count >= 200 { break }
        }
        results = found
    }

    private func extractSnippet(from text: String, around range: Range<String.Index>) -> String {
        let contextLen = 50
        let start = text.index(range.lowerBound, offsetBy: -min(contextLen, text.distance(from: text.startIndex, to: range.lowerBound)), limitedBy: text.startIndex) ?? text.startIndex
        let end   = text.index(range.upperBound, offsetBy: min(contextLen, text.distance(from: range.upperBound, to: text.endIndex)), limitedBy: text.endIndex) ?? text.endIndex
        let raw   = String(text[start..<end])
        let prefix = start > text.startIndex ? "…" : ""
        let suffix = end   < text.endIndex   ? "…" : ""
        return prefix + raw.trimmingCharacters(in: .whitespacesAndNewlines) + suffix
    }
}

// MARK: - 关键词高亮文本

private struct HighlightText: View {
    let text: String
    let keyword: String

    init(_ text: String, keyword: String) {
        self.text    = text
        self.keyword = keyword
    }

    var body: some View {
        if keyword.isEmpty {
            Text(text)
        } else {
            buildHighlighted()
        }
    }

    private func buildHighlighted() -> Text {
        var result = Text("")
        var remaining = text
        while let range = remaining.range(of: keyword, options: .caseInsensitive) {
            let before = String(remaining[remaining.startIndex..<range.lowerBound])
            let match  = String(remaining[range])
            if !before.isEmpty { result = result + Text(before) }
            result = result + Text(match).foregroundColor(.accentColor).bold()
            remaining = String(remaining[range.upperBound...])
        }
        if !remaining.isEmpty { result = result + Text(remaining) }
        return result
    }
}
