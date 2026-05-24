import SwiftUI

/// 设置界面
struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    @AppStorage("readerPreset") private var readerPreset: String = "normal"

    var body: some View {
        NavigationView {
            List {
                // MARK: 内容管理
                Section(header: Text("内容管理")) {
                    NavigationLink(destination: BookSourceListView()) {
                        Label("书源管理", systemImage: "network")
                    }
                    NavigationLink(destination: ReplaceRuleView()) {
                        Label("净化规则", systemImage: "wand.and.sparkles")
                    }
                }

                // MARK: 阅读偏好
                Section(header: Text("阅读偏好")) {
                    Picker("字号/行高预设", selection: $readerPreset) {
                        Text("正常").tag("normal")
                        Text("舒适").tag("comfortable")
                        Text("紧凑").tag("compact")
                    }
                    .pickerStyle(.segmented)

                    HStack {
                        Image(systemName: "textformat.size")
                            .foregroundColor(.secondary)
                        Text(presetDescription)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // MARK: 数据管理
                Section(header: Text("数据管理")) {
                    Button(action: { viewModel.clearCache() }) {
                        HStack {
                            Text("清理缓存")
                            Spacer()
                            Text(viewModel.cacheSize).foregroundColor(.secondary)
                        }
                    }

                    Button(role: .destructive, action: { viewModel.clearCookies() }) {
                        Text("清理所有 Cookie（注销登录）")
                    }

                    Button(role: .destructive, action: { viewModel.clearDatabase() }) {
                        Text("重置数据库（清空所有书源与书籍）")
                    }
                }

                // MARK: 关于
                Section(header: Text("关于")) {
                    HStack {
                        Text("当前版本")
                        Spacer()
                        Text(viewModel.appVersion).foregroundColor(.secondary)
                    }

                    Link(destination: URL(string: "https://github.com/gedoor/legado")!) {
                        HStack {
                            Label("开源项目（gedoor/legado）", systemImage: "link")
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("设置")
        }
    }

    private var presetDescription: String {
        switch readerPreset {
        case "comfortable": return "字号 18pt · 行高 1.8 — 适合长时间阅读"
        case "compact":     return "字号 14pt · 行高 1.3 — 显示更多内容"
        default:            return "字号 16pt · 行高 1.5 — 默认设置"
        }
    }
}
