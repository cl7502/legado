import SwiftUI
import SwiftSoup

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
            if let fix = debugVM.fixStep {
                DebugStepRow(step: fix).id(99)
            }
        }
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

    private var storedHtml = ""
    private var storedRequestUrl = ""
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
        storedHtml = html
        storedRequestUrl = requestUrl
        canAttemptFix = true

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

    // MARK: - 智能修复

    func inferAndFix(for source: BookSource) -> BookSource {
        var patched = source
        var changes: [String] = []
        let trimmed = storedHtml.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.hasPrefix("{") || trimmed.hasPrefix("["),
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

    // MARK: - JSON 推断

    private func inferFromJSON(json: Any, source: BookSource) -> (BookSource, [String]) {
        var patched = source
        var changes: [String] = []

        // 1. 收集所有可能的书单数组
        var candidates: [(String, [[String: Any]])] = []
        collectBookArrays(from: json, path: "$", into: &candidates)
        guard let best = candidates
            .filter({ $0.1.count >= 2 })
            .max(by: { bookScore($0.1) < bookScore($1.1) }) else {
            return (patched, ["未找到书单数组，响应可能为错误页或需要认证"])
        }

        let listPath = best.0 == "$" ? "$[*]" : "\(best.0)[*]"
        let bestItems = best.1

        // 3. 只填空白字段，不覆盖已有规则
        if (patched.ruleExploreList ?? "").isEmpty {
            patched.ruleExploreList = listPath
            changes.append("ruleExploreList = \(listPath)  （共 \(bestItems.count) 条）")
        }

        let sample = bestItems[0]
        func fill(_ current: String?, key: WritableKeyPath<BookSource, String?>,
                  label: String, candidates: [String]) {
            guard (current ?? "").isEmpty else { return }
            if let f = pickField(from: sample, candidates: candidates) {
                patched[keyPath: key] = "$.\(f)"
                changes.append("\(label) = $.\(f)  （样例：\(stringify(sample[f]))）")
            }
        }

        fill(patched.ruleExploreName, key: \.ruleExploreName, label: "ruleExploreName",
             candidates: ["novelName", "bookName", "book_name", "name", "title", "bookTitle"])
        fill(patched.ruleExploreAuthor, key: \.ruleExploreAuthor, label: "ruleExploreAuthor",
             candidates: ["authorName", "author_name", "author", "penName", "pen_name"])
        fill(patched.ruleExploreCoverUrl, key: \.ruleExploreCoverUrl, label: "ruleExploreCoverUrl",
             candidates: ["cover", "coverUrl", "cover_url", "img", "image", "thumb", "pic", "picurl"])
        fill(patched.ruleExploreKind, key: \.ruleExploreKind, label: "ruleExploreKind",
             candidates: ["kind", "category", "type", "sort", "genre", "cat", "sortName", "sort_name"])

        // ruleExploreNoteUrl：优先直接 URL，次选 ID 字段
        if (patched.ruleExploreNoteUrl ?? "").isEmpty {
            if let f = pickField(from: sample,
                                 candidates: ["url", "link", "bookUrl", "book_url", "detailUrl", "detail_url"]),
               let val = sample[f] as? String, val.lowercased().hasPrefix("http") {
                patched.ruleExploreNoteUrl = "$.\(f)"
                changes.append("ruleExploreNoteUrl = $.\(f)  （样例：\(val.prefix(60))）")
            } else if let f = pickField(from: sample,
                                        candidates: ["novelId", "novel_id", "bookId", "book_id", "id"]) {
                patched.ruleExploreNoteUrl = "$.\(f)"
                changes.append("ruleExploreNoteUrl = $.\(f)  ⚠️ 这是 ID 字段，可能需要手动补全 URL 前缀")
            }
        }

        return (patched, changes)
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
