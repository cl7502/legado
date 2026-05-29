// IOS/Legado/App/Features/BookSource/Views/DeepCheckConfigSheet.swift
import SwiftUI

enum DeepCheckScope: String, CaseIterable, Identifiable {
    case all       = "全部已启用"
    case untested  = "仅未测"
    case failedToo = "未测+失败"
    var id: String { rawValue }

    func filter(_ sources: [BookSource]) -> [BookSource] {
        switch self {
        case .all:       return sources.filter { $0.enabled }
        case .untested:  return sources.filter { $0.enabled && $0.checkState == 0 }
        case .failedToo: return sources.filter { $0.enabled && ($0.checkState == 0 || $0.checkState == 3) }
        }
    }
}

struct DeepCheckConfigSheet: View {
    @Environment(\.dismiss) private var dismiss
    let allSources: [BookSource]
    let onStart: (DeepCheckViewModel, [BookSource]) -> Void

    @State private var scope: DeepCheckScope = .all
    @State private var keyword = "小说"
    @State private var alsoRunSearch = false
    @State private var concurrency = 3

    private var targetSources: [BookSource] { scope.filter(allSources) }
    private var targetCount: Int { targetSources.count }

    var body: some View {
        NavigationView {
            Form {
                Section("检查范围") {
                    Picker("范围", selection: $scope) {
                        ForEach(DeepCheckScope.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Text("已选 \(targetCount) 个书源").font(.caption).foregroundColor(.secondary)
                }

                Section("搜索测试词") {
                    TextField("搜索词（留空使用默认：小说）", text: $keyword)
                        .autocorrectionDisabled()
                }

                Section {
                    Toggle("探索后自动跑搜索链路", isOn: $alsoRunSearch)
                    Text("仅对有发现规则的书源有额外效果；无发现规则的书源始终跑搜索。")
                        .font(.caption).foregroundColor(.secondary)
                }

                Section("并发数（1–5）") {
                    Stepper("\(concurrency) 个同时", value: $concurrency, in: 1...5)
                }
            }
            .navigationTitle("深度检查配置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("开始检查") {
                        let vm = DeepCheckViewModel()
                        vm.alsoRunSearch = alsoRunSearch
                        vm.concurrency   = concurrency
                        vm.searchKeyword = keyword.isEmpty ? "小说" : keyword
                        onStart(vm, targetSources)
                        dismiss()
                    }
                    .disabled(targetCount == 0)
                }
            }
        }
    }
}
