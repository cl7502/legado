import SwiftUI

/// 书源管理界面
struct BookSourceListView: View {
    @StateObject private var viewModel = BookSourceViewModel()
    @State private var showingImportAlert = false
    @State private var importText = ""
    
    var body: some View {
        NavigationView {
            List {
                ForEach(viewModel.sources) { source in
                    BookSourceRow(source: source) {
                        Task { await viewModel.toggleEnabled(source) }
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            Task { await viewModel.deleteSource(source) }
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle("书源管理")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingImportAlert = true }) {
                        Image(systemName: "square.and.arrow.down")
                    }
                }
            }
            .task {
                await viewModel.loadSources()
            }
            .alert("导入书源", isPresented: $showingImportAlert) {
                TextField("粘贴书源 JSON", text: $importText)
                Button("取消", role: .cancel) { }
                Button("导入") {
                    Task {
                        let count = await viewModel.importFromJSON(importText)
                        print("✅ 成功导入 \(count) 个书源")
                        importText = ""
                    }
                }
            } message: {
                Text("请粘贴 Legado 标准格式的 JSON 字符串")
            }
        }
    }
}

struct BookSourceRow: View {
    let source: BookSource
    let onToggle: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(source.bookSourceName)
                    .font(.headline)
                    .foregroundColor(source.enabled ? .primary : .secondary)
                
                HStack {
                    Text(source.bookSourceGroup ?? "未分组")
                    Text("|")
                    Text(source.bookSourceUrl)
                        .lineLimit(1)
                }
                .font(.caption2)
                .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Toggle("", isOn: Binding(get: { source.enabled }, set: { _ in onToggle() }))
                .labelsHidden()
        }
        .padding(.vertical, 4)
    }
}
