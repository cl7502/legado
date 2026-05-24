import SwiftUI

/// 书源编辑界面 — 支持新建与编辑
struct BookSourceEditView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: BookSourceViewModel

    @State private var source: BookSource

    private let isNew: Bool

    init(source: BookSource, viewModel: BookSourceViewModel) {
        self._source = State(initialValue: source)
        self.viewModel = viewModel
        self.isNew = source.bookSourceUrl.isEmpty
    }

    var body: some View {
        Form {
            // MARK: 基础信息
            Section(header: Text("基础信息")) {
                LabeledTextField("名称", text: $source.bookSourceName)
                LabeledTextField("URL（唯一标识）", text: $source.bookSourceUrl)
                    .keyboardType(.URL)
                    .autocapitalization(.none)
                LabeledOptionalTextField("分组", text: $source.bookSourceGroup)
                Picker("类型", selection: $source.bookSourceType) {
                    Text("网络文本").tag(0)
                    Text("音频").tag(1)
                    Text("RSS").tag(2)
                }
                LabeledOptionalTextField("备注", text: $source.bookSourceComment)
                Toggle("启用", isOn: $source.enabled)
            }

            // MARK: 登录
            Section(header: Text("登录")) {
                LabeledOptionalTextField("登录 URL", text: $source.loginUrl)
                LabeledOptionalTextField("登录检测 JS", text: $source.loginCheckJs)
            }

            // MARK: 搜索规则
            Section(header: Text("搜索规则")) {
                LabeledOptionalTextField("searchUrl", text: $source.searchUrl)
                LabeledOptionalTextField("ruleSearchList", text: $source.ruleSearchList)
                LabeledOptionalTextField("ruleSearchName", text: $source.ruleSearchName)
                LabeledOptionalTextField("ruleSearchAuthor", text: $source.ruleSearchAuthor)
                LabeledOptionalTextField("ruleSearchCoverUrl", text: $source.ruleSearchCoverUrl)
                LabeledOptionalTextField("ruleSearchNoteUrl", text: $source.ruleSearchNoteUrl)
            }

            // MARK: 详情页规则
            Section(header: Text("详情页规则")) {
                LabeledOptionalTextField("ruleBookInfoInit", text: $source.ruleBookInfoInit)
                LabeledOptionalTextField("ruleBookName", text: $source.ruleBookName)
                LabeledOptionalTextField("ruleBookAuthor", text: $source.ruleBookAuthor)
                LabeledOptionalTextField("ruleBookIntro", text: $source.ruleBookIntro)
                LabeledOptionalTextField("ruleBookCoverUrl", text: $source.ruleBookCoverUrl)
                LabeledOptionalTextField("ruleTocUrl", text: $source.ruleTocUrl)
            }

            // MARK: 目录规则
            Section(header: Text("目录规则")) {
                LabeledOptionalTextField("ruleTocList", text: $source.ruleTocList)
                LabeledOptionalTextField("ruleChapterName", text: $source.ruleChapterName)
                LabeledOptionalTextField("ruleChapterUrl", text: $source.ruleChapterUrl)
                LabeledOptionalTextField("ruleTocNextUrl", text: $source.ruleTocNextUrl)
            }

            // MARK: 正文规则
            Section(header: Text("正文规则")) {
                LabeledOptionalTextField("ruleContent", text: $source.ruleContent)
                LabeledOptionalTextField("ruleContentNextUrl", text: $source.ruleContentNextUrl)
                LabeledOptionalTextField("ruleContentReplace", text: $source.ruleContentReplace)
            }

            // MARK: 发现规则
            Section(header: Text("发现规则")) {
                LabeledOptionalTextField("exploreUrl", text: $source.exploreUrl)
                LabeledOptionalTextField("ruleExploreList", text: $source.ruleExploreList)
                LabeledOptionalTextField("ruleExploreName", text: $source.ruleExploreName)
                LabeledOptionalTextField("ruleExploreNoteUrl", text: $source.ruleExploreNoteUrl)
            }
        }
        .navigationTitle(isNew ? "新建书源" : "编辑书源")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("保存") {
                    Task {
                        await viewModel.saveSource(source)
                        dismiss()
                    }
                }
                .disabled(source.bookSourceUrl.isEmpty || source.bookSourceName.isEmpty)
            }
            ToolbarItem(placement: .navigationBarLeading) {
                Button("取消") { dismiss() }
            }
        }
    }
}

// MARK: - 辅助组件

/// 必填字段文本输入行
private struct LabeledTextField: View {
    let label: String
    @Binding var text: String

    init(_ label: String, text: Binding<String>) {
        self.label = label
        self._text = text
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            TextField(label, text: $text)
                .autocapitalization(.none)
                .disableAutocorrection(true)
        }
        .padding(.vertical, 2)
    }
}

/// 可选字段文本输入行（绑定 Optional<String>）
private struct LabeledOptionalTextField: View {
    let label: String
    @Binding var value: String?

    init(_ label: String, text binding: Binding<String?>) {
        self.label = label
        self._value = binding
    }

    private var proxy: Binding<String> {
        Binding(
            get: { value ?? "" },
            set: { value = $0.isEmpty ? nil : $0 }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            TextField(label, text: proxy)
                .autocapitalization(.none)
                .disableAutocorrection(true)
        }
        .padding(.vertical, 2)
    }
}
