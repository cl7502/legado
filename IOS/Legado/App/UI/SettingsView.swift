import SwiftUI

/// 设置界面
struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    @ObservedObject private var syncManager = WebDAVSyncManager.shared
    @ObservedObject private var webdavSettings = WebDAVSettings.shared
    @State private var webdavPassword = ""
    @State private var showTestResult = false
    @State private var testResultMessage = ""
    @State private var isTesting = false

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

                // MARK: 阅读
                Section(header: Text("阅读")) {
                    NavigationLink(destination: GlobalReaderSettingsView()) {
                        Label("阅读设置", systemImage: "book")
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

                // MARK: WebDAV 同步
                Section(header: Text("WebDAV 云同步")) {
                    TextField("服务器地址（https://...）", text: $webdavSettings.serverURL)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                    TextField("用户名", text: $webdavSettings.username)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                    SecureField("密码", text: $webdavPassword)
                        .onAppear { if webdavPassword.isEmpty { webdavPassword = webdavSettings.password } }
                        .onChange(of: webdavPassword) { webdavSettings.password = $0 }

                    Button {
                        isTesting = true
                    } label: {
                        HStack {
                            Text("测试连接")
                            if isTesting { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(isTesting || !webdavSettings.isConfigured)
                    .task(id: isTesting) {
                        guard isTesting else { return }
                        do {
                            let client = try WebDAVClient(
                                serverURL: webdavSettings.normalizedServerURL,
                                username:  webdavSettings.username,
                                password:  webdavSettings.password
                            )
                            _ = try await client.exists(path: "legado/metadata.json")
                            testResultMessage = "✅ 连接成功"
                        } catch {
                            testResultMessage = "❌ \(error.localizedDescription)"
                        }
                        isTesting = false
                        showTestResult = true
                    }
                    .alert("连接测试", isPresented: $showTestResult) {
                        Button("确定", role: .cancel) {}
                    } message: { Text(testResultMessage) }

                    Toggle("自动同步", isOn: $webdavSettings.autoSync)

                    if let d = webdavSettings.lastSyncDate {
                        HStack {
                            Text("上次同步")
                            Spacer()
                            Text(d, style: .relative)
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                    }

                    HStack {
                        Text("状态")
                        Spacer()
                        Group {
                            switch syncManager.state {
                            case .idle:
                                Text(webdavSettings.lastSyncDate != nil ? "已同步" : "未同步")
                                    .foregroundColor(.secondary)
                            case .syncing:
                                HStack(spacing: 6) {
                                    ProgressView().scaleEffect(0.8)
                                    Text("同步中…").foregroundColor(.secondary)
                                }
                            case .error(let msg):
                                Text(msg).foregroundColor(.red).lineLimit(2)
                            }
                        }
                        .font(.caption)
                    }

                    Button("立即同步") {
                        syncManager.syncNow()
                    }
                    .disabled(!webdavSettings.isConfigured || syncManager.state == .syncing)
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
}

// MARK: - GlobalReaderSettingsView（全局阅读设置）

struct GlobalReaderSettingsView: View {
    @StateObject private var settings = ReaderSettings.shared

    var body: some View {
        Form {
            // ── 翻页动画 ──────────────────────────────────
            Section("翻页动画") {
                Picker("动画效果", selection: Binding(
                    get: { settings.pageAnimation },
                    set: { settings.pageAnimation = $0 }
                )) {
                    ForEach(PageAnimation.allCases, id: \.self) { anim in
                        Text(anim.displayName).tag(anim)
                    }
                }
                .pickerStyle(.segmented)
            }

            // ── 缓存 ──────────────────────────────────────
            Section("缓存") {
                HStack {
                    Text("预缓存章节数")
                    Spacer()
                    Button {
                        settings.prefetchCount = max(1, settings.prefetchCount - 1)
                    } label: {
                        Image(systemName: "minus.circle")
                    }.buttonStyle(.plain)
                    Text("\(settings.prefetchCount)章")
                        .frame(width: 44, alignment: .center)
                        .monospacedDigit()
                    Button {
                        settings.prefetchCount = min(50, settings.prefetchCount + 1)
                    } label: {
                        Image(systemName: "plus.circle")
                    }.buttonStyle(.plain)
                }
                Text("阅读时在后台提前下载后续章节，数值越大消耗流量越多。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // ── 高级 ──────────────────────────────────────
            Section("高级") {
                Toggle("屏幕常亮", isOn: $settings.keepScreenOn)
                    .onChange(of: settings.keepScreenOn) { val in
                        UIApplication.shared.isIdleTimerDisabled = val
                    }
                Toggle("繁体中文", isOn: $settings.useTraditionalChinese)
                Toggle("音量键翻页", isOn: $settings.volumePageTurn)
                if ModelManager.isAvailable(.zipVoiceDistillInt8) {
                    Toggle("高质量TTS（ZipVoice）", isOn: $settings.useNovellaTTS)
                }
            }
        }
        .navigationTitle("阅读设置")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // 进入设置页时同步系统状态
            UIApplication.shared.isIdleTimerDisabled = settings.keepScreenOn
        }
    }
}

