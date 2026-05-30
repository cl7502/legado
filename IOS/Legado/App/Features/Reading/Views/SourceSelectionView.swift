// IOS/Legado/App/Features/Reading/Views/SourceSelectionView.swift
import SwiftUI

struct SourceSelectionView: View {
    let currentSourceUrl: String
    let bookName: String
    let currentChapterIndex: Int
    let onSelect: (BookSource) -> Void

    @StateObject private var vm = SourceSelectionViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var confirmSource: BookSource? = nil
    @State private var showConfirm = false

    var body: some View {
        NavigationView {
            Group {
                if vm.results.isEmpty && !vm.isSearching {
                    Text("暂无结果")
                        .foregroundColor(.secondary)
                } else {
                    List(vm.sortedResults) { result in
                        SourceResultRow(
                            result: result,
                            isCurrent: result.id == currentSourceUrl
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            guard case .found(let avail) = result.status, avail else { return }
                            Task {
                                let sources = (try? await DatabaseManager.shared.getAllBookSources()) ?? []
                                if let source = sources.first(where: { $0.bookSourceUrl == result.id }) {
                                    confirmSource = source
                                    showConfirm = true
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("选择来源")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    if vm.isSearching {
                        ProgressView().scaleEffect(0.8)
                    }
                }
            }
            .alert("切换书源", isPresented: $showConfirm, presenting: confirmSource) { source in
                Button("确定切换") {
                    onSelect(source)
                    dismiss()
                }
                Button("取消", role: .cancel) {}
            } message: { source in
                Text("切换到「\(source.bookSourceName)」？当前阅读进度将保留，章节内容将重新加载。")
            }
        }
        .task {
            await vm.startSearch(bookName: bookName, currentChapterIndex: currentChapterIndex)
        }
        .onDisappear { vm.cancelAll() }
    }
}

// MARK: - Row

private struct SourceResultRow: View {
    let result: SourceSearchResult
    let isCurrent: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(result.sourceName).font(.subheadline)
                    if isCurrent {
                        Text("当前使用")
                            .font(.caption2)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.blue.opacity(0.15))
                            .foregroundColor(.blue)
                            .cornerRadius(4)
                    }
                }
                statusView
                    .font(.caption)
                    .foregroundColor(statusColor)
            }
            Spacer()
            if isCurrent {
                Image(systemName: "checkmark.circle.fill").foregroundColor(.blue)
            }
        }
        .opacity(isDisabled ? 0.4 : 1.0)
    }

    private var isDisabled: Bool {
        switch result.status {
        case .found(let avail): return !avail && !isCurrent
        case .notFound, .timeout, .searching: return !isCurrent
        }
    }

    @ViewBuilder private var statusView: some View {
        switch result.status {
        case .searching:
            HStack(spacing: 4) {
                ProgressView().scaleEffect(0.6)
                Text("搜索中…")
            }
        case .found(let avail):
            Text(avail ? "章节 ✅ 可用" : "❌ 当前章节不可用")
        case .notFound:
            Text("未找到此书")
        case .timeout:
            Text("请求超时")
        }
    }

    private var statusColor: Color {
        switch result.status {
        case .found(let avail): return avail ? .green : .orange
        case .searching, .notFound, .timeout: return .secondary
        }
    }
}
