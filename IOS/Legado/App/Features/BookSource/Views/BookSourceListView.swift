import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// 书源管理界面
struct BookSourceListView: View {
    @StateObject private var viewModel    = BookSourceViewModel()
    @StateObject private var checkVM      = BookSourceCheckViewModel()
    @State private var newSourceSheet     = false

    // ISSUE-023: 粘贴 JSON
    @State private var showingPasteSheet  = false
    @State private var pasteText          = ""

    // URL 导入
    @State private var showingURLImportAlert = false
    @State private var importURLText      = ""

    // 文件导入
    @State private var showingFilePicker  = false

    // 清空书源确认
    @State private var showingClearConfirm = false

    // 导入结果提示
    @State private var importResultMessage = ""
    @State private var showingImportResult = false

    // 检测书源
    @State private var pendingCheckScope: CheckScope? = nil   // 待确认的检测范围
    @State private var showingCheckConfig = false             // 配置 sheet
    @State private var showingCheckProgress = false           // 进度 sheet

    // 书源发现调试器
    @State private var debugSource: BookSource? = nil
    // 编辑书源 sheet
    @State private var editSource: BookSource? = nil
    // 浏览书源 sheet
    @State private var browseURL: URL? = nil

    var body: some View {
        NavigationView {
            List {
                ForEach(viewModel.sources) { source in
                    HStack(spacing: 0) {
                        // 三点菜单（完整版）
                        Menu {
                            Button { editSource = source } label: {
                                Label("编辑书源", systemImage: "pencil")
                            }
                            Button {
                                if let url = URL(string: source.bookSourceUrl) { browseURL = url }
                            } label: {
                                Label("浏览书源", systemImage: "safari")
                            }
                            Button { Task { await viewModel.moveToTop(source) } } label: {
                                Label("置顶", systemImage: "arrow.up.to.line")
                            }
                            Button { Task { await viewModel.toggleEnabledExplore(source) } } label: {
                                Label(
                                    source.enabledExplore ? "禁用发现" : "启用发现",
                                    systemImage: source.enabledExplore ? "eye.slash" : "eye"
                                )
                            }
                            Divider()
                            Button { debugSource = source } label: {
                                Label("调试发现规则", systemImage: "ladybug")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.system(size: 16))
                                .foregroundColor(.secondary)
                                .frame(width: 36, height: 44)
                                .contentShape(Rectangle())
                        }
                        BookSourceRow(source: source) {
                            Task { await viewModel.toggleEnabled(source) }
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            Task { await viewModel.deleteSource(source) }
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }
                .onMove { from, to in
                    Task { await viewModel.moveSource(from: from, to: to) }
                }
            }
            .navigationTitle("书源管理")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    EditButton()
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            newSourceSheet = true
                        } label: {
                            Label("新建书源", systemImage: "plus.circle")
                        }
                        Button {
                            pasteText = ""
                            showingPasteSheet = true
                        } label: {
                            Label("粘贴 JSON", systemImage: "doc.on.clipboard")
                        }
                        Button {
                            showingURLImportAlert = true
                        } label: {
                            Label("从 URL 导入", systemImage: "link.badge.plus")
                        }
                        Button {
                            showingFilePicker = true
                        } label: {
                            Label("从文件导入", systemImage: "doc.badge.plus")
                        }
                        Divider()
                        // 检测书源子菜单
                        Menu {
                            ForEach(CheckScope.allCases) { scope in
                                Button {
                                    pendingCheckScope = scope
                                    showingCheckConfig = true
                                } label: {
                                    Text(scope.rawValue)
                                }
                            }
                        } label: {
                            Label("检测书源", systemImage: "antenna.radiowaves.left.and.right")
                        }
                        Divider()
                        Button(role: .destructive) {
                            showingClearConfirm = true
                        } label: {
                            Label("清空书源", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .task {
                await viewModel.loadSources()
            }
            .sheet(isPresented: $newSourceSheet) {
                NavigationView {
                    BookSourceEditView(source: BookSource(), viewModel: viewModel)
                }
            }
            // ISSUE-023: 粘贴 JSON 使用 sheet + TextEditor，不受系统 Alert 255 字符限制
            .sheet(isPresented: $showingPasteSheet) {
                PasteJSONSheet(text: $pasteText) { json in
                    Task {
                        let (count, error) = await viewModel.importFromJSON(json)
                        importResultMessage = count > 0
                            ? "成功导入 \(count) 个书源"
                            : "导入失败：\(error.isEmpty ? "未找到有效书源" : error)"
                        showingImportResult = true
                    }
                }
            }
            // URL 导入弹框（URL 通常很短，Alert 足够）
            .alert("从 URL 导入书源", isPresented: $showingURLImportAlert) {
                TextField("https://...", text: $importURLText)
                Button("取消", role: .cancel) { }
                Button("导入") {
                    Task {
                        let (count, error) = await viewModel.importFromURL(importURLText)
                        importResultMessage = count > 0
                            ? "成功导入 \(count) 个书源"
                            : "导入失败：\(error.isEmpty ? "未知错误" : error)"
                        showingImportResult = true
                        importURLText = ""
                    }
                }
            } message: {
                Text("输入包含书源 JSON 的远程地址")
            }
            // 文件选择器：支持 .json 和纯文本（部分书源打包为 .txt）
            .fileImporter(
                isPresented: $showingFilePicker,
                allowedContentTypes: [.json, .plainText, .data],
                allowsMultipleSelection: false
            ) { result in
                handleFileImport(result)
            }
            .alert("导入结果", isPresented: $showingImportResult) {
                Button("好") { }
            } message: {
                Text(importResultMessage)
            }
            .alert("清空书源", isPresented: $showingClearConfirm) {
                Button("取消", role: .cancel) { }
                Button("清空", role: .destructive) {
                    Task { await viewModel.deleteAllSources() }
                }
            } message: {
                Text("将删除全部 \(viewModel.sources.count) 个书源，此操作不可恢复。书架中的书籍不受影响。")
            }
            // 检测配置 sheet
            .sheet(isPresented: $showingCheckConfig) {
                if let scope = pendingCheckScope {
                    BookSourceCheckConfigSheet(scope: scope) { invalidAct, slowAct in
                        checkVM.invalidAction = invalidAct
                        checkVM.slowAction    = slowAct
                        checkVM.start(scope: scope)
                        showingCheckProgress = true
                    }
                }
            }
            // 检测进度 sheet
            .sheet(isPresented: $showingCheckProgress) {
                BookSourceCheckProgressSheet(vm: checkVM) {
                    Task { await viewModel.loadSources() }
                }
            }
            // 书源发现调试器 sheet
            .sheet(item: $debugSource) { source in
                NavigationView {
                    ExploreDebugView(source: source, listViewModel: viewModel)
                }
            }
            // 编辑书源 sheet（替代行点击导航）
            .sheet(item: $editSource) { source in
                NavigationView {
                    BookSourceEditView(source: source, viewModel: viewModel)
                }
            }
            // 浏览书源 sheet
            .sheet(isPresented: Binding(
                get: { browseURL != nil },
                set: { if !$0 { browseURL = nil } }
            )) {
                if let url = browseURL { SafariView(url: url) }
            }
        }
    }

    // MARK: - 文件导入处理

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            importResultMessage = "无法访问文件：\(error.localizedDescription)"
            showingImportResult = true

        case .success(let urls):
            guard let url = urls.first else { return }

            // 沙盒外文件需申请访问权限
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }

            do {
                let data = try Data(contentsOf: url)
                // 尝试 UTF-8，失败时用 GBK（部分书源文件为 GBK 编码）
                let json = String(data: data, encoding: .utf8)
                    ?? String(data: data, encoding: .init(rawValue: 936) /* GBK */)
                    ?? ""
                guard !json.isEmpty else {
                    importResultMessage = "文件内容为空或编码不支持"
                    showingImportResult = true
                    return
                }
                Task {
                    let (count, error) = await viewModel.importFromJSON(json)
                    importResultMessage = count > 0
                        ? "成功从文件导入 \(count) 个书源"
                        : "导入失败：\(error.isEmpty ? "未找到有效书源，请确认文件为 Legado JSON 格式" : error)"
                    showingImportResult = true
                }
            } catch {
                importResultMessage = "读取文件失败：\(error.localizedDescription)"
                showingImportResult = true
            }
        }
    }
}

// MARK: - 粘贴 JSON Sheet（无字符限制）

private struct PasteJSONSheet: View {
    @Binding var text: String
    let onImport: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                HStack {
                    Text("粘贴 Legado 标准格式的 JSON（单个或数组）")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    // Explicit paste button — reads UIPasteboard on user tap,
                    // bypasses iOS 16+ pasteboard permission prompt reliably.
                    Button {
                        if let s = UIPasteboard.general.string, !s.isEmpty {
                            text = s
                        }
                    } label: {
                        Label("从剪贴板粘贴", systemImage: "doc.on.clipboard")
                            .font(.caption)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)

                TextEditor(text: $text)
                    .font(.system(.body, design: .monospaced))
                    .padding(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )
                    .padding()
            }
            .navigationTitle("粘贴 JSON")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("导入") {
                        let json = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !json.isEmpty else { return }
                        dismiss()
                        onImport(json)
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

// MARK: - 书源行

struct BookSourceRow: View {
    let source: BookSource
    let onToggle: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(source.bookSourceName)
                    .font(.headline)
                    .foregroundColor(source.enabled ? .primary : .secondary)

                HStack(spacing: 4) {
                    Text(source.bookSourceGroup ?? "未分组")
                    Text("|")
                    Text(source.bookSourceUrl)
                        .lineLimit(1)
                }
                .font(.caption2)
                .foregroundColor(.secondary)
            }

            Spacer()

            // 网速徽章
            speedBadge

            Toggle("", isOn: Binding(get: { source.enabled }, set: { _ in onToggle() }))
                .labelsHidden()
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var speedBadge: some View {
        switch source.checkState {
        case 1:
            Text("\(source.respondTime)ms")
                .font(.system(size: 10, weight: .medium))
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(Color.green.opacity(0.12))
                .foregroundColor(.green)
                .cornerRadius(4)
        case 2:
            Text("\(source.respondTime)ms")
                .font(.system(size: 10, weight: .medium))
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(Color.red.opacity(0.12))
                .foregroundColor(.red)
                .cornerRadius(4)
        case 3:
            Text("失败")
                .font(.system(size: 10, weight: .medium))
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(Color.red.opacity(0.12))
                .foregroundColor(.red)
                .cornerRadius(4)
        default:
            EmptyView()  // 未检测：不显示
        }
    }
}
