import SwiftUI

// MARK: - 书源发现调试器

struct ExploreDebugView: View {
    let original: BookSource
    let listViewModel: BookSourceViewModel

    @StateObject private var debugVM = ExploreDebugViewModel()
    @State private var draft: BookSource
    @State private var hasUnsaved = false
    @Environment(\.dismiss) private var dismiss

    init(source: BookSource, listViewModel: BookSourceViewModel) {
        self.original = source
        self.listViewModel = listViewModel
        _draft = State(initialValue: source)
    }

    var body: some View {
        Form {
            exploreUrlSection
            listRuleSection
            extractRuleSection
            if !debugVM.steps.isEmpty {
                diagnosticsSection
            }
        }
        .navigationTitle(original.bookSourceName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("关闭") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    Task {
                        await listViewModel.saveSource(draft)
                        hasUnsaved = false
                    }
                }
                .disabled(!hasUnsaved)
            }
        }
        .safeAreaInset(edge: .bottom) { runButton }
    }

    // MARK: - Sections

    @ViewBuilder
    private var exploreUrlSection: some View {
        Section {
            TextEditor(text: Binding(
                get: { draft.exploreUrl ?? "" },
                set: { draft.exploreUrl = $0.isEmpty ? nil : $0; hasUnsaved = true }
            ))
            .font(.system(.caption, design: .monospaced))
            .frame(minHeight: 80)
            .autocapitalization(.none)
            .disableAutocorrection(true)
        } header: {
            Text("exploreUrl  —  分类列表定义")
        }
    }

    @ViewBuilder
    private var listRuleSection: some View {
        Section("书单列表规则") {
            ruleField("ruleExploreList",
                      get: { draft.ruleExploreList ?? "" },
                      set: { draft.ruleExploreList = $0.isEmpty ? nil : $0 })
        }
    }

    @ViewBuilder
    private var extractRuleSection: some View {
        Section("字段提取规则") {
            ruleField("ruleExploreName",
                      get: { draft.ruleExploreName ?? "" },
                      set: { draft.ruleExploreName = $0.isEmpty ? nil : $0 })
            ruleField("ruleExploreAuthor",
                      get: { draft.ruleExploreAuthor ?? "" },
                      set: { draft.ruleExploreAuthor = $0.isEmpty ? nil : $0 })
            ruleField("ruleExploreNoteUrl",
                      get: { draft.ruleExploreNoteUrl ?? "" },
                      set: { draft.ruleExploreNoteUrl = $0.isEmpty ? nil : $0 })
            ruleField("ruleExploreCoverUrl",
                      get: { draft.ruleExploreCoverUrl ?? "" },
                      set: { draft.ruleExploreCoverUrl = $0.isEmpty ? nil : $0 })
            ruleField("ruleExploreKind",
                      get: { draft.ruleExploreKind ?? "" },
                      set: { draft.ruleExploreKind = $0.isEmpty ? nil : $0 })
        }
    }

    @ViewBuilder
    private var diagnosticsSection: some View {
        Section("诊断结果") {
            ForEach(debugVM.steps) { step in
                DebugStepRow(step: step)
            }
        }
    }

    @ViewBuilder
    private var runButton: some View {
        Button {
            Task { await debugVM.run(source: draft) }
        } label: {
            HStack {
                if debugVM.isRunning {
                    ProgressView().tint(.white)
                    Text("运行中...")
                } else {
                    Image(systemName: "play.fill")
                    Text("运行诊断")
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
        .buttonStyle(.borderedProminent)
        .disabled(debugVM.isRunning)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    // MARK: - Rule field helper

    @ViewBuilder
    private func ruleField(_ label: String,
                           get: @escaping () -> String,
                           set: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            TextField(label, text: Binding(
                get: get,
                set: { set($0); hasUnsaved = true }
            ))
            .font(.system(.caption, design: .monospaced))
            .autocapitalization(.none)
            .disableAutocorrection(true)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - DebugStep 数据模型

struct DebugStep: Identifiable {
    enum Status { case pending, running, passed, failed, warning }

    var id: Int
    var title: String
    var status: Status = .pending
    var summary: String = ""
    var detail: String = ""

    var isRunning: Bool { status == .running }

    var icon: String {
        switch status {
        case .pending:  return "circle"
        case .running:  return "arrow.clockwise.circle"
        case .passed:   return "checkmark.circle.fill"
        case .failed:   return "xmark.circle.fill"
        case .warning:  return "exclamationmark.triangle.fill"
        }
    }

    var iconColor: Color {
        switch status {
        case .pending:  return .secondary
        case .running:  return .accentColor
        case .passed:   return .green
        case .failed:   return .red
        case .warning:  return .orange
        }
    }
}

// MARK: - 单步展示行

private struct DebugStepRow: View {
    let step: DebugStep

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                if step.isRunning {
                    ProgressView()
                        .scaleEffect(0.75)
                        .frame(width: 20, height: 20)
                } else {
                    Image(systemName: step.icon)
                        .foregroundColor(step.iconColor)
                        .frame(width: 20)
                }
                Text(step.title)
                    .font(.subheadline.weight(.medium))
                Spacer()
            }
            if !step.summary.isEmpty {
                Text(step.summary)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.leading, 28)
            }
            if !step.detail.isEmpty {
                Text(step.detail)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.secondary)
                    .padding(.leading, 28)
                    .lineLimit(8)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - ExploreDebugViewModel

@MainActor
class ExploreDebugViewModel: ObservableObject {
    @Published var steps: [DebugStep] = []
    @Published var isRunning = false

    private let network = NetworkManager.shared
    private let ruleExecutor = RuleExecutor.shared

    func run(source: BookSource) async {
        isRunning = true
        defer { isRunning = false }

        print("🔍 [ExploreDebug] run() 开始 source=\(source.bookSourceName)")
        steps = (0..<5).map { DebugStep(id: $0, title: stepTitle($0)) }
        print("🔍 [ExploreDebug] steps 初始化完毕 count=\(steps.count)")

        // Step 0: 解析 exploreUrl → 分类列表
        steps[0].status = .running
        let categories = parseCategories(source: source)
        guard !categories.isEmpty else {
            steps[0].status = .failed
            steps[0].summary = "未解析到任何分类"
            steps[0].detail = "exploreUrl = \(source.exploreUrl ?? "(空)")"
            print("❌ [ExploreDebug] Step0 失败：无分类")
            return
        }
        steps[0].status = .passed
        steps[0].summary = "共 \(categories.count) 个分类"
        steps[0].detail = categories.prefix(8).map { $0.title }.joined(separator: "  ")
        print("✅ [ExploreDebug] Step0 通过：\(categories.count) 个分类")

        // Step 1: 解析第一个分类的请求 URL
        steps[1].status = .running
        let firstCat = categories[0]
        var parseCtx = AnalyzeContext(source: source, baseUrl: source.bookSourceUrl)
        parseCtx.variables["page"] = "1"
        let parsed = AnalyzeUrl.parse(firstCat.url, variables: ["page": "1"], context: parseCtx)
        let requestUrl = resolveUrl(parsed.url, base: source.bookSourceUrl)
        guard requestUrl.lowercased().hasPrefix("http") else {
            steps[1].status = .failed
            steps[1].summary = "URL 无效（非 http/https）"
            steps[1].detail = "原始: \(firstCat.url)\n解析: \(requestUrl)"
            return
        }
        steps[1].status = .passed
        steps[1].summary = "分类「\(firstCat.title)」"
        steps[1].detail = requestUrl
        print("✅ [ExploreDebug] Step1 通过：\(requestUrl)")

        // Step 2: 网络请求
        steps[2].status = .running
        let t0 = Date()
        let html: String
        do {
            if parsed.method == "POST", let body = parsed.body {
                html = try await network.requestPost(requestUrl, body: body, source: source)
            } else {
                html = try await network.request(requestUrl, source: source)
            }
        } catch {
            steps[2].status = .failed
            steps[2].summary = "请求失败"
            steps[2].detail = error.localizedDescription
            print("❌ [ExploreDebug] Step2 网络失败：\(error)")
            return
        }
        let ms = Int(Date().timeIntervalSince(t0) * 1000)
        steps[2].status = .passed
        steps[2].summary = "HTTP 200  \(html.count) 字节  \(ms)ms"
        steps[2].detail = String(html.prefix(300)).replacingOccurrences(of: "\n", with: " ")
        print("✅ [ExploreDebug] Step2 通过：\(html.count) 字节 \(ms)ms")

        // Step 3: ruleExploreList
        steps[3].status = .running
        let listRule = source.ruleExploreList ?? ""
        guard !listRule.isEmpty else {
            steps[3].status = .failed
            steps[3].summary = "ruleExploreList 为空"
            return
        }
        var htmlCtx = AnalyzeContext(source: source, baseUrl: requestUrl)
        htmlCtx.result = html
        let items = ruleExecutor.executeList(listRule, in: &htmlCtx)
        guard !items.isEmpty else {
            steps[3].status = .failed
            steps[3].summary = "规则未匹配到任何条目"
            steps[3].detail = "规则: \(listRule)"
            return
        }
        steps[3].status = items.count < 3 ? .warning : .passed
        steps[3].summary = "找到 \(items.count) 条\(items.count < 3 ? "（偏少，请检查规则）" : "")"
        steps[3].detail = "规则: \(listRule)"
        print("✅ [ExploreDebug] Step3 通过：\(items.count) 条")

        // Step 4: 提取前 5 个 item 的字段
        steps[4].status = .running
        var lines: [String] = []
        var validCount = 0
        for (i, item) in items.prefix(5).enumerated() {
            var ctx = AnalyzeContext(source: source, baseUrl: requestUrl)
            ctx.result = item
            let name     = ruleExecutor.execute(source.ruleExploreName    ?? "", in: &ctx) ?? ""
            let author   = ruleExecutor.execute(source.ruleExploreAuthor  ?? "", in: &ctx) ?? ""
            let bookUrl  = ruleExecutor.execute(source.ruleExploreNoteUrl ?? "", in: &ctx) ?? ""
            let coverUrl = ruleExecutor.execute(source.ruleExploreCoverUrl ?? "", in: &ctx) ?? ""
            let valid = !name.isEmpty && !bookUrl.isEmpty
            if valid { validCount += 1 }
            lines.append("\(valid ? "✅" : "❌") [\(i + 1)] \(name.isEmpty ? "(空)" : name)  \(author)")
            lines.append("    bookUrl: \(bookUrl.isEmpty ? "(空)" : bookUrl)")
            if !coverUrl.isEmpty { lines.append("    cover: \(coverUrl)") }
        }
        let shown = min(items.count, 5)
        steps[4].status = validCount == 0 ? .failed : (validCount < shown ? .warning : .passed)
        steps[4].summary = "前 \(shown) 条中 \(validCount) 条有效（name + bookUrl 非空）"
        steps[4].detail = lines.joined(separator: "\n")
        print("✅ [ExploreDebug] Step4 完成：\(validCount)/\(shown) 条有效")
        print("🏁 [ExploreDebug] run() 结束")
    }

    // MARK: - Category parsing — mirrors ExploreCategoryViewModel exactly

    private func parseCategories(source: BookSource) -> [ExploreCategory] {
        guard let rawInput = source.exploreUrl,
              !rawInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }

        var raw = rawInput
        let trimmed = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("@js:") || trimmed.lowercased().hasPrefix("javascript:") {
            let ctx = AnalyzeContext(source: source, baseUrl: source.bookSourceUrl)
            let p = AnalyzeUrl.parse(raw, context: ctx)
            if p.url.lowercased().hasPrefix("http") { raw = p.url }
        }

        if let data = raw.data(using: .utf8),
           let arr = try? JSONDecoder().decode([ExploreCategory].self, from: data) {
            let cats = arr.compactMap { cat -> ExploreCategory? in
                let u = cat.url.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !u.isEmpty else { return nil }
                let t = cat.title.trimmingCharacters(in: .whitespacesAndNewlines)
                return ExploreCategory(title: t.isEmpty ? "全部" : t, url: u)
            }
            if !cats.isEmpty { return cats }
        }

        let lines = raw.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if lines.count > 1 || lines.first?.contains("::") == true || lines.first?.contains(",http") == true {
            let cats = lines.compactMap { line -> ExploreCategory? in
                if line.contains("::") {
                    let parts = line.components(separatedBy: "::")
                    let title = parts[0].trimmingCharacters(in: .whitespaces)
                    let url   = parts.dropFirst().joined(separator: "::").trimmingCharacters(in: .whitespaces)
                    guard !url.isEmpty else { return nil }
                    return ExploreCategory(title: title.isEmpty ? "全部" : title, url: url)
                } else if let r = line.range(of: ",http") {
                    let title = String(line[..<r.lowerBound]).trimmingCharacters(in: .whitespaces)
                    let url   = "http" + String(line[r.upperBound...]).trimmingCharacters(in: .whitespaces)
                    return ExploreCategory(title: title.isEmpty ? "全部" : title, url: url)
                } else if line.hasPrefix("http") {
                    return ExploreCategory(title: "全部", url: line)
                } else if line.hasPrefix("/") || line.hasPrefix("./") {
                    return ExploreCategory(title: "全部", url: line)
                }
                return nil
            }
            if !cats.isEmpty { return cats }
        }

        return [ExploreCategory(title: "全部", url: raw)]
    }

    // MARK: - Helpers

    private func stepTitle(_ i: Int) -> String {
        ["Step 1  解析 exploreUrl",
         "Step 2  分类 URL 解析",
         "Step 3  网络请求",
         "Step 4  执行 ruleExploreList",
         "Step 5  提取 item 字段"][i]
    }

    private func resolveUrl(_ path: String, base: String) -> String {
        if path.lowercased().hasPrefix("http") { return path }
        if path.hasPrefix("//") {
            return (base.hasPrefix("https") ? "https:" : "http:") + path
        }
        guard let baseURL = URL(string: base),
              let resolved = URL(string: path, relativeTo: baseURL) else { return path }
        return resolved.absoluteString
    }
}
