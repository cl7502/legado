import SwiftUI
import SwiftSoup

// MARK: - 书源发现调试器

struct ExploreDebugView: View {
    let original: BookSource
    let listViewModel: BookSourceViewModel

    @StateObject private var debugVM = ExploreDebugViewModel()
    @State private var draft: BookSource
    @State private var hasUnsaved = false
    @State private var showingFullResponse = false   // 增强1
    @Environment(\.dismiss) private var dismiss

    init(source: BookSource, listViewModel: BookSourceViewModel) {
        self.original = source
        self.listViewModel = listViewModel
        _draft = State(initialValue: source)
    }

    var body: some View {
        ScrollViewReader { proxy in
            Form {
                exploreUrlSection
                listRuleSection
                extractRuleSection
                diagnosticsSection
            }
            .onChange(of: debugVM.isRunning) { isRunning in
                guard isRunning else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    withAnimation(.easeInOut(duration: 0.4)) {
                        proxy.scrollTo(0, anchor: .top)
                    }
                }
            }
            .onChange(of: debugVM.fixVersion) { _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation(.easeInOut(duration: 0.4)) {
                        proxy.scrollTo(99, anchor: .top)
                    }
                }
            }
        }
        .navigationTitle(original.bookSourceName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("关闭") { dismiss() }
            }
            // 增强5：导出书源 JSON
            ToolbarItem(placement: .principal) {
                if let jsonData = try? JSONEncoder().encode(draft),
                   let jsonStr = String(data: jsonData, encoding: .utf8) {
                    ShareLink(
                        item: jsonStr,
                        subject: Text("书源: \(draft.bookSourceName)"),
                        message: Text("Legado 书源规则（发现）")
                    ) {
                        Image(systemName: "square.and.arrow.up").font(.caption)
                    }
                }
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
        // 增强1：完整响应 sheet
        .sheet(isPresented: $showingFullResponse) {
            FullResponseSheet(html: debugVM.storedHtml)
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
                // 增强1：Step 3（网络请求）通过后显示"查看完整响应"按钮
                if step.id == 2 && step.status == .passed && !debugVM.storedHtml.isEmpty {
                    Button {
                        showingFullResponse = true
                    } label: {
                        Label("查看完整响应（\(debugVM.storedHtml.count) 字节）",
                              systemImage: "doc.text.magnifyingglass")
                            .font(.caption)
                    }
                    .padding(.leading, 28)
                }
            }
            // 增强2：候选数组选择器（JSON 书源，多个候选时显示）
            if debugVM.arrayCandidates.count > 1 {
                candidatePickerSection
            }
            if let fix = debugVM.fixStep {
                DebugStepRow(step: fix).id(99)
            }
        }
    }

    @ViewBuilder
    private var candidatePickerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("书单数组候选（选择后点「修复」）")
                .font(.caption)
                .foregroundColor(.secondary)
            Picker("", selection: $debugVM.selectedCandidateIndex) {
                ForEach(debugVM.arrayCandidates.indices, id: \.self) { i in
                    let c = debugVM.arrayCandidates[i]
                    Text("\(c.path)[*]  (\(c.count)条)  \(c.sampleKeys)")
                        .font(.system(.caption2, design: .monospaced))
                        .tag(i)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
        .padding(.leading, 28)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var runButton: some View {
        HStack(spacing: 12) {
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

            Button {
                let fixed = debugVM.inferAndFix(for: draft)
                draft = fixed
                hasUnsaved = true
            } label: {
                Label("修复", systemImage: "wand.and.stars")
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
            }
            .buttonStyle(.bordered)
            .disabled(!debugVM.canAttemptFix || debugVM.isRunning)
        }
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
    @Published var steps: [DebugStep] = [
        DebugStep(id: 0, title: "Step 1  解析 exploreUrl"),
        DebugStep(id: 1, title: "Step 2  分类 URL 解析"),
        DebugStep(id: 2, title: "Step 3  网络请求"),
        DebugStep(id: 3, title: "Step 4  执行 ruleExploreList"),
        DebugStep(id: 4, title: "Step 5  提取 item 字段"),
    ]
    @Published var isRunning = false
    @Published var canAttemptFix = false
    @Published var fixStep: DebugStep? = nil
    @Published var fixVersion = 0

    // 完整响应（增强1）
    @Published var storedHtml = ""
    // 候选书单数组（增强2）
    @Published var arrayCandidates: [(path: String, count: Int, sampleKeys: String)] = []
    @Published var selectedCandidateIndex = 0

    private var storedRequestUrl = ""
    private var storedJsonCandidates: [(String, [[String: Any]])] = []   // 内部完整候选
    private let network = NetworkManager.shared
    private let ruleExecutor = RuleExecutor.shared

    func run(source: BookSource) async {
        isRunning = true
        defer { isRunning = false }

        print("🔍 [ExploreDebug] run() 开始 source=\(source.bookSourceName)")
        // 重置状态，保留标题，不替换整个数组（避免 ForEach 重建导致不渲染）
        for i in 0..<steps.count {
            steps[i].status = .pending
            steps[i].summary = ""
            steps[i].detail = ""
        }
        print("🔍 [ExploreDebug] steps 重置完毕")

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

        // Step 2: 网络请求（JS 驱动的书源跳过，由 java.ajax() 内部处理）
        steps[2].status = .running
        let isJSRule = (source.ruleExploreList ?? "").trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<js>") ||
                       (source.ruleExploreList ?? "").trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("@js:")
        let html: String
        if isJSRule {
            html = ""
            steps[2].status = .passed
            steps[2].summary = "JS 驱动书源 — 网络请求由 ruleExploreList 内的 java.ajax() 负责"
            steps[2].detail = "baseUrl 已设置为：\(requestUrl)"
            print("✅ [ExploreDebug] Step2 JS驱动，跳过预取")
        } else {
            let t0 = Date()
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
            storedHtml = html
            storedRequestUrl = requestUrl
            canAttemptFix = true
            // 增强2：收集候选书单数组
            let t = html.trimmingCharacters(in: .whitespacesAndNewlines)
            if (t.hasPrefix("{") || t.hasPrefix("[")),
               let data = html.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) {
                var raw: [(String, [[String: Any]])] = []
                collectBookArrays(from: json, path: "$", into: &raw)
                storedJsonCandidates = raw.filter { $0.1.count >= 2 }
                                           .sorted { bookScore($1.1) < bookScore($0.1) }
                selectedCandidateIndex = 0
                arrayCandidates = storedJsonCandidates.prefix(8).map { path, items in
                    let keys = items.first.map { $0.keys.sorted().prefix(6).joined(separator: " / ") } ?? ""
                    return (path: path, count: items.count, sampleKeys: keys)
                }
            } else {
                storedJsonCandidates = []; arrayCandidates = []
            }
        }

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

    // MARK: - Category parsing — delegates to shared ExploreUrlParser

    private func parseCategories(source: BookSource) -> [ExploreCategory] {
        let ctx = AnalyzeContext(source: source, baseUrl: source.bookSourceUrl)
        return ExploreUrlParser.parse(source.exploreUrl ?? "", context: ctx)
    }

    // MARK: - 智能修复

    func inferAndFix(for source: BookSource) -> BookSource {
        var patched = source
        var changes: [String] = []
        let trimmed = storedHtml.trimmingCharacters(in: .whitespacesAndNewlines)

        if !storedJsonCandidates.isEmpty {
            // 增强2：使用用户选中的候选数组
            let idx = min(selectedCandidateIndex, storedJsonCandidates.count - 1)
            let chosen = storedJsonCandidates[idx]
            (patched, changes) = inferFromJSONCandidate(path: chosen.0, items: chosen.1, source: patched)
        } else if trimmed.hasPrefix("{") || trimmed.hasPrefix("["),
                  let data = storedHtml.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) {
            (patched, changes) = inferFromJSON(json: json, source: patched)
        } else if !trimmed.isEmpty {
            (patched, changes) = inferFromHTML(html: trimmed, source: patched)
        } else {
            changes = ["尚无响应数据，请先运行诊断"]
        }

        let summary = changes.isEmpty ? "未能自动推断，请手动填写" : "已填入 \(changes.count) 项"
        fixStep = DebugStep(
            id: 99,
            title: "修复建议",
            status: changes.isEmpty ? .warning : .passed,
            summary: summary,
            detail: changes.joined(separator: "\n")
        )
        fixVersion += 1
        return patched
    }

    // MARK: - JSON 推断（基于已选候选）

    private func inferFromJSONCandidate(path: String, items: [[String: Any]],
                                        source: BookSource) -> (BookSource, [String]) {
        var patched = source
        var changes: [String] = []

        let listPath = path == "$" ? "$[*]" : "\(path)[*]"
        if (patched.ruleExploreList ?? "").isEmpty {
            patched.ruleExploreList = listPath
            changes.append("ruleExploreList = \(listPath)  （共 \(items.count) 条）")
        }

        let sample = items[0]
        applyFieldInference(to: &patched, sample: sample, source: source, changes: &changes)
        return (patched, changes)
    }

    // MARK: - JSON 推断（旧入口，保持向后兼容）

    private func inferFromJSON(json: Any, source: BookSource) -> (BookSource, [String]) {
        var patched = source
        var changes: [String] = []

        var candidates: [(String, [[String: Any]])] = []
        collectBookArrays(from: json, path: "$", into: &candidates)
        guard let best = candidates
            .filter({ $0.1.count >= 2 })
            .max(by: { bookScore($0.1) < bookScore($1.1) }) else {
            return (patched, ["未找到书单数组，响应可能为错误页或需要认证"])
        }

        let listPath = best.0 == "$" ? "$[*]" : "\(best.0)[*]"
        let bestItems = best.1

        if (patched.ruleExploreList ?? "").isEmpty {
            patched.ruleExploreList = listPath
            changes.append("ruleExploreList = \(listPath)  （共 \(bestItems.count) 条）")
        }

        let sample = bestItems[0]
        applyFieldInference(to: &patched, sample: sample, source: source, changes: &changes)
        return (patched, changes)
    }

    // MARK: - 字段推断核心（增强3：URL模板推断 + 增强4：值类型启发）

    private func applyFieldInference(to patched: inout BookSource,
                                     sample: [String: Any],
                                     source: BookSource,
                                     changes: inout [String]) {
        func fill(_ current: String?, key: WritableKeyPath<BookSource, String?>,
                  label: String, candidates: [String], valueType: ValueHint? = nil) {
            guard (current ?? "").isEmpty else { return }
            // 优先按字段名匹配
            if let f = pickField(from: sample, candidates: candidates) {
                patched[keyPath: key] = "$.\(f)"
                changes.append("\(label) = $.\(f)  （样例：\(stringify(sample[f]))）")
                return
            }
            // 增强4：值类型启发式匹配
            if let hint = valueType, let f = pickFieldByValue(from: sample, hint: hint) {
                patched[keyPath: key] = "$.\(f)"
                changes.append("\(label) = $.\(f)  💡 值类型启发（样例：\(stringify(sample[f]))）")
            }
        }

        fill(patched.ruleExploreName, key: \.ruleExploreName, label: "ruleExploreName",
             candidates: ["novelName", "bookName", "book_name", "name", "title", "bookTitle"],
             valueType: .chineseText)
        fill(patched.ruleExploreAuthor, key: \.ruleExploreAuthor, label: "ruleExploreAuthor",
             candidates: ["authorName", "author_name", "author", "penName", "pen_name"],
             valueType: .chineseText)
        fill(patched.ruleExploreCoverUrl, key: \.ruleExploreCoverUrl, label: "ruleExploreCoverUrl",
             candidates: ["cover", "coverUrl", "cover_url", "img", "image", "thumb", "pic", "picurl"],
             valueType: .imageUrl)
        fill(patched.ruleExploreKind, key: \.ruleExploreKind, label: "ruleExploreKind",
             candidates: ["kind", "category", "type", "sort", "genre", "cat", "sortName", "sort_name"])

        // ruleExploreNoteUrl：增强3 URL模板推断 + 增强4 值启发
        if (patched.ruleExploreNoteUrl ?? "").isEmpty {
            if let f = pickField(from: sample,
                                 candidates: ["url", "link", "bookUrl", "book_url", "detailUrl", "detail_url"]),
               let val = sample[f] as? String, val.lowercased().hasPrefix("http") {
                patched.ruleExploreNoteUrl = "$.\(f)"
                changes.append("ruleExploreNoteUrl = $.\(f)  （样例：\(val.prefix(60))）")
            } else if let f = pickField(from: sample,
                                        candidates: ["novelId", "novel_id", "bookId", "book_id", "id"])
                      ?? pickFieldByValue(from: sample, hint: .idNumber) {
                // 增强3：尝试从书源现有规则推断 URL 模板
                if let tpl = inferUrlTemplate(idField: f, source: source) {
                    patched.ruleExploreNoteUrl = tpl
                    changes.append("ruleExploreNoteUrl = \(tpl)  （从 ruleSearchNoteUrl/bookUrlPattern 推断）")
                } else {
                    patched.ruleExploreNoteUrl = "$.\(f)"
                    changes.append("ruleExploreNoteUrl = $.\(f)  ⚠️ 是 ID 字段，需手动补全 URL 前缀")
                }
            } else if let f = pickFieldByValue(from: sample, hint: .detailUrl) {
                patched.ruleExploreNoteUrl = "$.\(f)"
                changes.append("ruleExploreNoteUrl = $.\(f)  💡 值类型启发（URL）")
            }
        }
    }

    // MARK: - 增强3：URL 模板推断

    private func inferUrlTemplate(idField: String, source: BookSource) -> String? {
        // 先看 ruleSearchNoteUrl 是否可复用（最可靠）
        if let snUrl = source.ruleSearchNoteUrl, !snUrl.isEmpty {
            // 包含 JSONPath 模板且引用了 ID 类字段 → 替换字段名
            let idHints = ["$.id", "$.novelId", "$.novel_id", "$.bookId", "$.book_id"]
            for hint in idHints where snUrl.contains(hint) {
                return snUrl.replacingOccurrences(of: hint, with: "$.\(idField)")
            }
            // 包含 {{$. 模板语法 → 直接复用
            if snUrl.contains("{{$.") { return snUrl }
        }
        // 再看 bookUrlPattern：提取路径骨架
        if let pattern = source.bookUrlPattern, !pattern.isEmpty {
            // 把正则数字匹配符换成模板变量，提取 URL 路径
            let cleaned = pattern
                .replacingOccurrences(of: "\\d+", with: "{ID}", options: .regularExpression)
                .replacingOccurrences(of: "(\\d+)", with: "{ID}", options: .regularExpression)
            if let urlObj = URL(string: cleaned.hasPrefix("http") ? cleaned : "https://example.com" + cleaned),
               urlObj.path.contains("{ID}") {
                let pathTpl = urlObj.path.replacingOccurrences(of: "{ID}", with: "{{$.\(idField)}}")
                return pathTpl
            }
        }
        return nil
    }

    // MARK: - 增强4：值类型启发式字段选取

    enum ValueHint { case chineseText, imageUrl, detailUrl, idNumber }

    private func pickFieldByValue(from dict: [String: Any], hint: ValueHint) -> String? {
        for (key, rawValue) in dict {
            switch hint {
            case .chineseText:
                guard let s = rawValue as? String else { continue }
                let cjk = s.unicodeScalars.filter { $0.value >= 0x4E00 && $0.value <= 0x9FFF }.count
                if cjk >= 2 && s.count <= 30 { return key }
            case .imageUrl:
                guard let s = rawValue as? String,
                      s.lowercased().hasPrefix("http") else { continue }
                let ext = (s as NSString).pathExtension.lowercased()
                if ["jpg","jpeg","png","webp","gif","bmp"].contains(ext) { return key }
            case .detailUrl:
                guard let s = rawValue as? String,
                      s.lowercased().hasPrefix("http"), s.count > 20 else { continue }
                return key
            case .idNumber:
                if let s = rawValue as? String, Int(s) != nil { return key }
                if rawValue is Int || rawValue is NSNumber { return key }
            }
        }
        return nil
    }

    private func collectBookArrays(from json: Any, path: String,
                                   into result: inout [(String, [[String: Any]])]) {
        if let dict = json as? [String: Any] {
            for (key, value) in dict {
                collectBookArrays(from: value, path: "\(path).\(key)", into: &result)
            }
        } else if let arr = json as? [Any] {
            let dicts = arr.compactMap { $0 as? [String: Any] }
            if dicts.count == arr.count && dicts.count >= 2 {
                result.append((path, dicts))
            } else {
                for (i, item) in arr.enumerated() {
                    collectBookArrays(from: item, path: "\(path)[\(i)]", into: &result)
                }
            }
        }
    }

    private func bookScore(_ items: [[String: Any]]) -> Int {
        guard let sample = items.first else { return 0 }
        var score = min(items.count, 30)
        let keys = Set(sample.keys.map { $0.lowercased() })
        let nameHints   = ["name", "title", "novelname", "bookname"]
        let authorHints = ["author", "authorname", "writer"]
        let urlHints    = ["url", "link", "id", "novelid", "bookid"]
        if nameHints.contains(where: { keys.contains($0) })   { score += 20 }
        if authorHints.contains(where: { keys.contains($0) }) { score += 10 }
        if urlHints.contains(where: { keys.contains($0) })    { score += 10 }
        score += min(sample.keys.count, 10)
        return score
    }

    private func pickField(from dict: [String: Any], candidates: [String]) -> String? {
        for c in candidates {
            if dict[c] != nil { return c }
            if let k = dict.keys.first(where: { $0.lowercased() == c }) { return k }
        }
        return nil
    }

    private func stringify(_ value: Any?) -> String {
        switch value {
        case let s as String: return s
        case let n as NSNumber: return n.stringValue
        case .none: return "(null)"
        default: return "\(value!)"
        }
    }

    // MARK: - HTML 推断（启发式，仅处理常见列表结构）

    private func inferFromHTML(html: String, source: BookSource) -> (BookSource, [String]) {
        guard let doc = try? SwiftSoup.parse(html) else {
            return (source, ["HTML 解析失败"])
        }
        var changes: [String] = []
        var patched = source

        // 查找含有重复子元素的列表容器（li / div / article）
        let selectors = ["ul > li", "ol > li", ".book-list > *", ".list > *",
                         ".booklist > *", ".bookList > *", "article"]
        for sel in selectors {
            guard let elements = try? doc.select(sel),
                  elements.count >= 4 else { continue }
            if (patched.ruleExploreList ?? "").isEmpty {
                patched.ruleExploreList = sel
                changes.append("ruleExploreList = \(sel)  （共 \(elements.count) 个节点）")
            }
            // 从第一个元素推断字段规则
            if let first = elements.first() {
                let tryLink: (String, WritableKeyPath<BookSource, String?>, String) -> Void = { cssPath, kp, label in
                    if (patched[keyPath: kp] ?? "").isEmpty,
                       let node = try? first.select(cssPath).first(),
                       !((try? node.text()) ?? "").isEmpty {
                        patched[keyPath: kp] = cssPath
                        changes.append("\(label) = \(cssPath)")
                    }
                }
                tryLink("h3, h4, .title, .name, a", \.ruleExploreName, "ruleExploreName")
                tryLink(".author, .writer", \.ruleExploreAuthor, "ruleExploreAuthor")
                tryLink("a[href]@href", \.ruleExploreNoteUrl, "ruleExploreNoteUrl")
                tryLink("img@src, img@data-src", \.ruleExploreCoverUrl, "ruleExploreCoverUrl")
            }
            if !changes.isEmpty { break }
        }
        if changes.isEmpty {
            changes.append("未能识别列表结构，请手动编写 CSS 规则")
        }
        return (patched, changes)
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

// MARK: - 增强1：完整响应查看 Sheet

private struct FullResponseSheet: View {
    let html: String
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    var body: some View {
        NavigationView {
            ScrollView {
                let display = searchText.isEmpty ? html : html
                Text(display)
                    .font(.system(.caption2, design: .monospaced))
                    .textSelection(.enabled)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("完整响应  (\(html.count) 字节)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    ShareLink(item: html) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
    }
}
