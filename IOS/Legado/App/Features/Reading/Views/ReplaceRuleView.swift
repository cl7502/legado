import SwiftUI

/// 净化规则管理界面 — 列表 + 编辑
struct ReplaceRuleView: View {
    @StateObject private var viewModel = ReplaceRuleViewModel()
    @State private var editingRule: ReplaceRule?
    @State private var showingNewRule = false

    var body: some View {
        NavigationView {
            List {
                ForEach($viewModel.rules) { $rule in
                    ReplaceRuleRow(
                        rule: $rule,
                        onToggle: { Task { await viewModel.toggleRule(rule) } },
                        onMoveUp: { Task { await viewModel.moveUp(rule) } },
                        onMoveDown: { Task { await viewModel.moveDown(rule) } }
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { editingRule = rule }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            Task { await viewModel.deleteRule(rule) }
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }
                .onMove { indices, newOffset in
                    viewModel.rules.move(fromOffsets: indices, toOffset: newOffset)
                    Task { await viewModel.saveOrder() }
                }
            }
            .navigationTitle("净化规则")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    EditButton()
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showingNewRule = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .task { await viewModel.loadRules() }
            .sheet(item: $editingRule) { rule in
                NavigationView {
                    ReplaceRuleEditView(rule: rule) { updated in
                        Task { await viewModel.saveRule(updated) }
                    }
                }
            }
            .sheet(isPresented: $showingNewRule) {
                NavigationView {
                    ReplaceRuleEditView(rule: ReplaceRule()) { newRule in
                        Task { await viewModel.saveRule(newRule) }
                    }
                }
            }
            .overlay {
                if viewModel.rules.isEmpty && !viewModel.isLoading {
                    ContentUnavailableView(
                        "暂无净化规则",
                        systemImage: "wand.and.sparkles",
                        description: Text("点击左上角 + 新建规则")
                    )
                }
            }
        }
    }
}

// MARK: - 规则列表行

private struct ReplaceRuleRow: View {
    @Binding var rule: ReplaceRule
    let onToggle: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(rule.name.isEmpty ? "（未命名）" : rule.name)
                    .font(.headline)
                    .foregroundColor(rule.isEnabled ? .primary : .secondary)
                Text(rule.pattern ?? "")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            HStack(spacing: 4) {
                Button(action: onMoveUp) {
                    Image(systemName: "chevron.up")
                        .font(.caption)
                }
                .buttonStyle(.borderless)

                Button(action: onMoveDown) {
                    Image(systemName: "chevron.down")
                        .font(.caption)
                }
                .buttonStyle(.borderless)

                Toggle("", isOn: Binding(
                    get: { rule.isEnabled },
                    set: { _ in onToggle() }
                ))
                .labelsHidden()
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - 规则编辑页

struct ReplaceRuleEditView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var rule: ReplaceRule
    let onSave: (ReplaceRule) -> Void

    init(rule: ReplaceRule, onSave: @escaping (ReplaceRule) -> Void) {
        self._rule = State(initialValue: rule)
        self.onSave = onSave
    }

    var body: some View {
        Form {
            Section(header: Text("基本信息")) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("规则名称").font(.caption).foregroundColor(.secondary)
                    TextField("规则名称", text: $rule.name)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("匹配模式（正则）").font(.caption).foregroundColor(.secondary)
                    TextField("正则表达式", text: Binding(
                        get: { rule.pattern ?? "" },
                        set: { rule.pattern = $0.isEmpty ? nil : $0 }
                    ))
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .font(.system(.body, design: .monospaced))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("替换内容（留空则删除）").font(.caption).foregroundColor(.secondary)
                    TextField("替换内容（可为空）", text: $rule.replacement)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }
            }

            Section(header: Text("选项")) {
                Toggle("启用", isOn: $rule.isEnabled)
                Toggle("使用正则", isOn: $rule.isRegex)
            }
        }
        .navigationTitle(rule.name.isEmpty ? "新建规则" : "编辑规则")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("保存") {
                    onSave(rule)
                    dismiss()
                }
                .disabled((rule.pattern ?? "").isEmpty)
            }
            ToolbarItem(placement: .navigationBarLeading) {
                Button("取消") { dismiss() }
            }
        }
    }
}

// MARK: - ViewModel

@MainActor
class ReplaceRuleViewModel: ObservableObject {
    @Published var rules: [ReplaceRule] = []
    @Published var isLoading = false

    private let db = DatabaseManager.shared

    func loadRules() async {
        isLoading = true
        defer { isLoading = false }
        do {
            rules = try await db.getAllReplaceRules()
        } catch {
            print("❌ [ReplaceRuleVM] loadRules: \(error)")
        }
    }

    func saveRule(_ rule: ReplaceRule) async {
        do {
            try await db.saveReplaceRule(rule)
            await loadRules()
        } catch {
            print("❌ [ReplaceRuleVM] saveRule: \(error)")
        }
    }

    func deleteRule(_ rule: ReplaceRule) async {
        do {
            try await db.deleteReplaceRule(rule)
            await loadRules()
        } catch {
            print("❌ [ReplaceRuleVM] deleteRule: \(error)")
        }
    }

    func toggleRule(_ rule: ReplaceRule) async {
        var updated = rule
        updated.isEnabled.toggle()
        await saveRule(updated)
    }

    func moveUp(_ rule: ReplaceRule) async {
        guard let idx = rules.firstIndex(of: rule), idx > 0 else { return }
        rules.swapAt(idx, idx - 1)
        await saveOrder()
    }

    func moveDown(_ rule: ReplaceRule) async {
        guard let idx = rules.firstIndex(of: rule), idx < rules.count - 1 else { return }
        rules.swapAt(idx, idx + 1)
        await saveOrder()
    }

    func saveOrder() async {
        for (idx, var rule) in rules.enumerated() {
            rule.order = idx
            try? await db.saveReplaceRule(rule)
        }
    }
}
