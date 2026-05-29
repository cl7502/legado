# 深度检查功能实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 新增书源"深度检查"功能，验证完整解析链路（探索 5 步 + 搜索 3 步），集成到批量检查菜单第四项和单个书源三点菜单"深度检查"入口。

**Architecture:** 管线层（`DeepCheckPipeline`）纯逻辑、无 UI 依赖；ViewModel 用滑动窗口 TaskGroup 协调并发，通过 `@MainActor` 回调更新 `@Observable` 状态；View 展示分步可展开结果。`ExploreUrlParser` 从现有 `ExploreCategoryViewModel` 提取为共享工具，同时供 ExploreView 和 Pipeline 使用。

**Tech Stack:** Swift 5.9, SwiftUI, `@Observable`, Swift Concurrency (Task/TaskGroup/async-await), Alamofire (`HTTPHeaders`), RuleExecutor, NetworkManager, HeadlessWebViewLoader, GRDB

---

## 文件变更清单

| 操作 | 文件 |
|---|---|
| 新增 | `Core/Utils/AsyncSemaphore.swift` |
| 新增 | `Core/Services/ExploreUrlParser.swift` |
| 新增 | `Features/BookSource/Models/DeepCheckModels.swift` |
| 新增 | `Core/Services/DeepCheckPipeline.swift` |
| 新增 | `Features/BookSource/ViewModels/DeepCheckViewModel.swift` |
| 新增 | `Features/BookSource/Views/DeepCheckConfigSheet.swift` |
| 新增 | `Features/BookSource/Views/DeepCheckView.swift` |
| 修改 | `Features/BookSource/Views/ExploreView.swift`（提取 ExploreCategory + loadCategories 改用 parser）|
| 修改 | `Features/BookSource/Views/BookSourceCheckView.swift`（删除 AsyncSemaphore，改用共享版）|
| 修改 | `Features/BookSource/Views/BookSourceListView.swift`（菜单 + 三点菜单）|

所有新文件创建后需在 Xcode Project Navigator 中添加到对应 Group（或 xcodegen generate）。

---

## Task 1：提取 AsyncSemaphore + 创建数据模型

**Files:**
- Create: `IOS/Legado/App/Core/Utils/AsyncSemaphore.swift`
- Create: `IOS/Legado/App/Features/BookSource/Models/DeepCheckModels.swift`
- Modify: `IOS/Legado/App/Features/BookSource/Views/BookSourceCheckView.swift`

- [ ] **Step 1.1：新建 `AsyncSemaphore.swift`**

```swift
// IOS/Legado/App/Core/Utils/AsyncSemaphore.swift
import Foundation

actor AsyncSemaphore {
    private var count: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(_ count: Int) { self.count = count }

    func wait() async {
        if count > 0 {
            count -= 1
        } else {
            await withCheckedContinuation { cont in waiters.append(cont) }
        }
    }

    func signal() {
        if waiters.isEmpty {
            count += 1
        } else {
            waiters.removeFirst().resume()
        }
    }
}
```

- [ ] **Step 1.2：删除 `BookSourceCheckView.swift` 中的 AsyncSemaphore（原 191-212 行）**

打开 `BookSourceCheckView.swift`，删除以下代码块（`actor AsyncSemaphore { ... }` 整段），保存。该类型已由 `Core/Utils/AsyncSemaphore.swift` 提供。

- [ ] **Step 1.3：新建 `DeepCheckModels.swift`**

```swift
// IOS/Legado/App/Features/BookSource/Models/DeepCheckModels.swift
import Foundation

// MARK: - Step-level status
enum StepStatus: Equatable {
    case pending, running, passed, failed, skipped
}

// MARK: - Source-level status (distinct from StepStatus to allow `partial`)
enum SourceCheckStatus: Equatable {
    case pending        // 队列中，未开始
    case running        // 检查中
    case awaitingSearch // 探索完成，搜索待用户触发（单源模式）
    case passed         // 所有已跑管线通过
    case partial        // 部分管线通过（探索✅搜索❌ 或反之）
    case failed         // 所有已跑管线失败
    case skipped        // 无可用规则
}

// MARK: - Step kind
enum DeepCheckStepKind: Int, CaseIterable {
    // Explore pipeline (0-4)
    case parseExploreUrl = 0
    case fetchCategoryPage
    case parseBookList
    case parseBookFields
    case verifyDetailPage
    // Search pipeline (5-7)
    case fetchSearchPage
    case parseSearchList
    case parseSearchFields

    enum Pipeline { case explore, search }
    var pipeline: Pipeline { rawValue < 5 ? .explore : .search }

    var displayName: String {
        switch self {
        case .parseExploreUrl:   return "解析分类 URL"
        case .fetchCategoryPage: return "获取分类页"
        case .parseBookList:     return "解析书单"
        case .parseBookFields:   return "解析书目字段"
        case .verifyDetailPage:  return "验证详情页"
        case .fetchSearchPage:   return "获取搜索结果"
        case .parseSearchList:   return "解析搜索书单"
        case .parseSearchFields: return "解析书目字段"
        }
    }
}

// MARK: - Single step result
struct DeepCheckStepResult: Identifiable, Equatable {
    var id: Int { kind.rawValue }
    let kind: DeepCheckStepKind
    var status: StepStatus = .pending
    var durationMs: Int = 0
    var summary: String = ""
    var detailPreview: String? = nil
    var errorMessage: String? = nil

    static func pending(_ kind: DeepCheckStepKind) -> DeepCheckStepResult {
        DeepCheckStepResult(kind: kind)
    }
}

// MARK: - Source result (pure data, no execution state)
struct DeepCheckSourceResult: Identifiable {
    let id: String           // = sourceUrl
    let sourceName: String
    let sourceUrl: String
    let hasExplore: Bool
    let hasSearch: Bool
    var exploreSteps: [DeepCheckStepResult] = []
    var searchSteps:  [DeepCheckStepResult] = []
    var skippedReason: String? = nil

    var overallStatus: SourceCheckStatus {
        if skippedReason != nil { return .skipped }
        let all = exploreSteps + searchSteps
        guard !all.isEmpty else { return .pending }
        if all.contains(where: { $0.status == .running }) { return .running }
        // All skipped/pending with no passed → treat as failed
        // (happens when Step 1 fails and cascades all later steps to .skipped)
        if !all.contains(where: { $0.status == .passed || $0.status == .failed }) {
            return all.allSatisfy({ $0.status == .skipped }) ? .failed : .pending
        }
        let hasFail = all.contains { $0.status == .failed }
        let hasPass = all.contains { $0.status == .passed }
        if hasFail && hasPass { return .partial }
        if hasFail            { return .failed  }
        return .passed
    }
}

// MARK: - ViewModel wrapper (result + execution state)
struct DeepCheckEntry: Identifiable {
    let id: String           // = sourceUrl
    var result: DeepCheckSourceResult
    var execStatus: SourceCheckStatus = .pending
}
```

- [ ] **Step 1.4：构建验证**

```bash
cd /Users/alina/Documents/Lei/legado/IOS
xcodebuild -project Legado.xcodeproj -scheme Legado \
  -destination 'platform=iOS Simulator,id=962E405B-C2DC-463C-889D-FC51D1438E83' \
  -quiet build 2>&1 | grep -E "error:|BUILD"
```

期望：`** BUILD SUCCEEDED **`

- [ ] **Step 1.5：Commit**

```bash
cd /Users/alina/Documents/Lei/legado
git add IOS/Legado/App/Core/Utils/AsyncSemaphore.swift \
        IOS/Legado/App/Features/BookSource/Models/DeepCheckModels.swift \
        "IOS/Legado/App/Features/BookSource/Views/BookSourceCheckView.swift"
git commit -m "refactor: 提取 AsyncSemaphore + 新增 DeepCheckModels"
```

---

## Task 2：提取 ExploreUrlParser

**Files:**
- Create: `IOS/Legado/App/Core/Services/ExploreUrlParser.swift`
- Modify: `IOS/Legado/App/Features/BookSource/Views/ExploreView.swift`

- [ ] **Step 2.1：新建 `ExploreUrlParser.swift`**

`ExploreCategory` struct 从 `ExploreView.swift` 移至此处（Swift 同模块可见，ExploreView 无需 import）：

```swift
// IOS/Legado/App/Core/Services/ExploreUrlParser.swift
import Foundation

// Moved from ExploreView.swift — same module, ExploreView accesses without import.
struct ExploreCategory: Codable, Identifiable {
    var id: String { "\(title)|\(url)" }
    var title: String
    var url: String
}

/// Shared exploreUrl parser — used by ExploreCategoryViewModel and DeepCheckPipeline.
struct ExploreUrlParser {

    /// Parse `exploreUrl` string into (title, url) pairs.
    /// Handles: @js: prefix (via LegadoJSEngine), JSON array, newline+:: format, plain URL.
    static func parse(_ exploreUrl: String, context: AnalyzeContext) -> [ExploreCategory] {
        var raw = exploreUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return [] }

        // @js: / javascript: execution — evaluate script, use result as new raw string
        if raw.hasPrefix("@js:") || raw.lowercased().hasPrefix("javascript:") {
            let code = raw.hasPrefix("@js:") ? String(raw.dropFirst(4)) : String(raw.dropFirst(11))
            var ctx = context
            // AnalyzeUrl.parse handles @js: by evaluating the JS and returning the result URL
            let parsed = AnalyzeUrl.parse(raw, context: ctx)
            if parsed.url.lowercased().hasPrefix("http") {
                raw = parsed.url
            } else if let result = LegadoJSEngine.shared.evaluateRule(code, in: &ctx), !result.isEmpty {
                raw = result
            } else {
                return []
            }
        }

        // JSON array: [{"title":"...","url":"..."},...]
        if raw.hasPrefix("["), let data = raw.data(using: .utf8),
           let arr = try? JSONDecoder().decode([ExploreCategory].self, from: data) {
            let cats = arr.compactMap { cat -> ExploreCategory? in
                let u = cat.url.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !u.isEmpty else { return nil }
                let t = cat.title.trimmingCharacters(in: .whitespacesAndNewlines)
                return ExploreCategory(title: t.isEmpty ? "全部" : t, url: u)
            }
            if !cats.isEmpty { return deduplicated(cats) }
        }

        // Newline-separated: "名称::URL" | "名称,http://..." | plain URL per line
        let lines = raw.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if lines.count > 1 || lines.first?.contains("::") == true
                             || lines.first?.contains(",http") == true {
            let cats: [ExploreCategory] = lines.compactMap { line in
                if line.contains("::") {
                    let parts = line.components(separatedBy: "::")
                    let title = parts[0].trimmingCharacters(in: .whitespaces)
                    let url   = parts.dropFirst().joined(separator: "::").trimmingCharacters(in: .whitespaces)
                    guard !url.isEmpty else { return nil }
                    return ExploreCategory(title: title.isEmpty ? "全部" : title, url: url)
                } else if let r = line.range(of: ",http") {
                    let title = String(line[line.startIndex..<r.lowerBound]).trimmingCharacters(in: .whitespaces)
                    let url   = "http" + String(line[r.upperBound...]).trimmingCharacters(in: .whitespaces)
                    return ExploreCategory(title: title.isEmpty ? "全部" : title, url: url)
                } else if line.hasPrefix("http") || line.hasPrefix("/") || line.hasPrefix("./") {
                    return ExploreCategory(title: "全部", url: line)
                }
                return nil
            }
            if !cats.isEmpty { return deduplicated(cats) }
        }

        // Fallback: single URL
        return [ExploreCategory(title: "全部", url: raw)]
    }

    private static func deduplicated(_ cats: [ExploreCategory]) -> [ExploreCategory] {
        var seen = Set<String>()
        return cats.filter { seen.insert($0.id).inserted }
    }
}
```

- [ ] **Step 2.2：修改 `ExploreView.swift` — 删除 ExploreCategory 定义，loadCategories 改用 parser**

**找到并删除** ExploreView.swift 第 322-328 行的 `struct ExploreCategory`（已移至 ExploreUrlParser.swift）。

**找到** `ExploreCategoryViewModel.loadCategories()` 方法（第 153-221 行），**替换整个方法体**为：

```swift
func loadCategories(source: BookSource) async {
    isLoading = true
    defer { isLoading = false }
    let ctx = AnalyzeContext(source: source, baseUrl: source.bookSourceUrl)
    let parsed = ExploreUrlParser.parse(source.exploreUrl ?? "", context: ctx)
    categories = parsed
}
```

- [ ] **Step 2.3：构建验证**

```bash
xcodebuild -project Legado.xcodeproj -scheme Legado \
  -destination 'platform=iOS Simulator,id=962E405B-C2DC-463C-889D-FC51D1438E83' \
  -quiet build 2>&1 | grep -E "error:|BUILD"
```

期望：`** BUILD SUCCEEDED **`

- [ ] **Step 2.4：Commit**

```bash
cd /Users/alina/Documents/Lei/legado
git add IOS/Legado/App/Core/Services/ExploreUrlParser.swift \
        "IOS/Legado/App/Features/BookSource/Views/ExploreView.swift"
git commit -m "refactor: 提取 ExploreUrlParser，ExploreCategoryViewModel 改用共享 parser"
```

---

## Task 3：DeepCheckPipeline — 探索管线

**Files:**
- Create: `IOS/Legado/App/Core/Services/DeepCheckPipeline.swift`

- [ ] **Step 3.1：新建 `DeepCheckPipeline.swift`（含辅助函数 + 探索管线）**

```swift
// IOS/Legado/App/Core/Services/DeepCheckPipeline.swift
import Foundation
import Alamofire

struct DeepCheckPipeline {

    static let perSourceTimeout: TimeInterval = 60

    // MARK: - Explore Pipeline (5 steps)

    /// Run the explore pipeline for a source with an exploreUrl.
    /// Each step fires onStep twice: once with .running (start), once with final status (end).
    /// Errors are captured internally — never throws.
    /// Steps cascade: if step N's required output is missing, N+1..end become .skipped.
    static func runExplore(
        source: BookSource,
        onStep: @escaping (DeepCheckStepResult) -> Void
    ) async -> [DeepCheckStepResult] {
        let inner = Task<[DeepCheckStepResult], Never> {
            await _runExplore(source: source, onStep: onStep)
        }
        let timeout = Task {
            try? await Task.sleep(nanoseconds: UInt64(perSourceTimeout * 1_000_000_000))
            inner.cancel()
        }
        let result = await inner.value
        timeout.cancel()
        return result
    }

    private static func _runExplore(
        source: BookSource,
        onStep: @escaping (DeepCheckStepResult) -> Void
    ) async -> [DeepCheckStepResult] {
        // Pre-initialise all 5 steps as .pending
        var steps = (0..<5).map { DeepCheckStepResult.pending(DeepCheckStepKind(rawValue: $0)!) }

        func emit(_ s: DeepCheckStepResult) { onStep(s) }
        func skipFrom(_ i: Int, reason: String? = nil) {
            for j in i..<5 {
                steps[j].status = .skipped
                steps[j].errorMessage = reason
                emit(steps[j])
            }
        }

        // ── Step 1: parseExploreUrl ──────────────────────────────────────────
        guard !Task.isCancelled else { skipFrom(0, reason: "已取消"); return steps }
        steps[0].status = .running; emit(steps[0])

        let t1 = Date()
        let ctx = AnalyzeContext(source: source, baseUrl: source.bookSourceUrl)
        let categories = ExploreUrlParser.parse(source.exploreUrl ?? "", context: ctx)
        steps[0].durationMs = ms(since: t1)

        guard !categories.isEmpty else {
            steps[0].status = .failed
            steps[0].errorMessage = "无法解析分类列表（exploreUrl 格式有误或为空）"
            emit(steps[0]); skipFrom(1); return steps
        }
        steps[0].status = .passed
        steps[0].summary = "\(categories.count)个分类，首选：\(categories[0].title)"
        steps[0].detailPreview = categories.prefix(5).map(\.title).joined(separator: " / ")
        emit(steps[0])

        let firstCategory = categories[0]

        // ── Step 2: fetchCategoryPage ────────────────────────────────────────
        guard !Task.isCancelled else { skipFrom(1, reason: "已取消"); return steps }
        steps[1].status = .running; emit(steps[1])

        // Resolve relative URL and expand {{page}} template
        var catRawUrl = firstCategory.url
        if !catRawUrl.hasPrefix("http"), let base = URL(string: source.bookSourceUrl),
           let resolved = URL(string: catRawUrl, relativeTo: base) {
            catRawUrl = resolved.absoluteString
        }
        let parsedCat = AnalyzeUrl.parse(catRawUrl, variables: ["page": "1"])
        let catFetchUrl = parsedCat.url.hasPrefix("http") ? parsedCat.url
                        : source.bookSourceUrl + parsedCat.url
        var catHeaders = parsedCat.headers
        source.headerDictionary.forEach { catHeaders[$0.key] = $0.value }

        let t2 = Date()
        let catBody: String
        do {
            if parsedCat.webView {
                catBody = (try? await HeadlessWebViewLoader.fetch(
                    urlString: catFetchUrl, headers: catHeaders, injectJs: parsedCat.webJs)) ?? ""
            } else {
                catBody = try await NetworkManager.shared.request(
                    catFetchUrl, headers: HTTPHeaders(catHeaders), source: source)
            }
        } catch {
            steps[1].durationMs = ms(since: t2)
            steps[1].status = .failed; steps[1].errorMessage = error.localizedDescription
            emit(steps[1]); skipFrom(2); return steps
        }
        steps[1].durationMs = ms(since: t2)
        guard !catBody.isEmpty else {
            steps[1].status = .failed; steps[1].errorMessage = "响应体为空"
            emit(steps[1]); skipFrom(2); return steps
        }
        steps[1].status = .passed; steps[1].summary = "HTTP 200"
        steps[1].detailPreview = String(catBody.prefix(300)); emit(steps[1])

        // ── Step 3: parseBookList ────────────────────────────────────────────
        guard !Task.isCancelled else { skipFrom(2, reason: "已取消"); return steps }
        steps[2].status = .running; emit(steps[2])

        guard let listRule = source.ruleExploreList, !listRule.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            steps[2].status = .failed; steps[2].errorMessage = "ruleExploreList 未配置"
            emit(steps[2]); skipFrom(3); return steps
        }
        let t3 = Date()
        var listCtx = AnalyzeContext(source: source, baseUrl: catFetchUrl)
        listCtx.result = catBody
        let items = RuleExecutor.shared.executeList(listRule, in: &listCtx)
        steps[2].durationMs = ms(since: t3)
        guard !items.isEmpty else {
            steps[2].status = .failed; steps[2].errorMessage = "书单解析结果为空（0条）"
            emit(steps[2]); skipFrom(3); return steps
        }
        steps[2].status = .passed; steps[2].summary = "\(items.count)条书目"
        steps[2].detailPreview = "\(items.count)条书目"; emit(steps[2])

        // ── Step 4: parseBookFields ──────────────────────────────────────────
        guard !Task.isCancelled else { skipFrom(3, reason: "已取消"); return steps }
        steps[3].status = .running; emit(steps[3])

        let t4 = Date()
        var itemCtx = AnalyzeContext(source: source, baseUrl: catFetchUrl)
        itemCtx.result = items[0]

        let name = execute(source.ruleExploreName ?? "", ctx: &itemCtx)
        let author = execute(source.ruleExploreAuthor ?? "", ctx: &itemCtx)
        let noteUrlRaw = execute(source.ruleExploreNoteUrl ?? "", ctx: &itemCtx)
        let noteUrl = resolveUrl(noteUrlRaw, base: catFetchUrl, sourceBase: source.bookSourceUrl)

        steps[3].durationMs = ms(since: t4)
        guard !name.isEmpty else {
            steps[3].status = .failed; steps[3].errorMessage = "书名解析为空（ruleExploreName）"
            emit(steps[3]); skipFrom(4); return steps
        }
        steps[3].status = .passed
        steps[3].summary = "《\(name)》\(author.isEmpty ? "" : " " + author)"
        steps[3].detailPreview = "名：\(name)\n作者：\(author.isEmpty ? "（无）" : author)\n链接：\(noteUrlRaw.isEmpty ? "（无）" : noteUrlRaw)"
        emit(steps[3])

        // ── Step 5: verifyDetailPage ─────────────────────────────────────────
        guard !Task.isCancelled else { skipFrom(4, reason: "已取消"); return steps }
        steps[4].status = .running; emit(steps[4])

        guard !noteUrl.isEmpty else {
            steps[4].status = .skipped; steps[4].errorMessage = "无 noteUrl，跳过详情验证"
            emit(steps[4]); return steps
        }
        let parsedDetail = AnalyzeUrl.parse(noteUrl, variables: [:])
        let detailUrl = parsedDetail.url.hasPrefix("http") ? parsedDetail.url
                      : source.bookSourceUrl + parsedDetail.url
        let t5 = Date()
        do {
            let body: String
            if parsedDetail.webView {
                body = (try? await HeadlessWebViewLoader.fetch(
                    urlString: detailUrl, headers: source.headerDictionary,
                    injectJs: parsedDetail.webJs)) ?? ""
            } else {
                body = try await NetworkManager.shared.request(
                    detailUrl, headers: HTTPHeaders(source.headerDictionary), source: source)
            }
            steps[4].durationMs = ms(since: t5)
            if body.isEmpty {
                steps[4].status = .failed; steps[4].errorMessage = "详情页响应为空"
            } else {
                steps[4].status = .passed; steps[4].summary = "HTTP 200"
                steps[4].detailPreview = String(body.prefix(300))
            }
        } catch {
            steps[4].durationMs = ms(since: t5)
            steps[4].status = .failed; steps[4].errorMessage = error.localizedDescription
        }
        emit(steps[4])
        return steps
    }

    // MARK: - Private helpers

    private static func ms(since start: Date) -> Int {
        Int(Date().timeIntervalSince(start) * 1000)
    }

    private static func execute(_ rule: String, ctx: inout AnalyzeContext) -> String {
        guard !rule.isEmpty else { return "" }
        return RuleExecutor.shared.execute(rule, in: &ctx) ?? ""
    }

    private static func resolveUrl(_ url: String, base: String, sourceBase: String) -> String {
        guard !url.isEmpty else { return "" }
        if url.hasPrefix("http") { return url }
        if url.hasPrefix("//") {
            let scheme = URL(string: base)?.scheme ?? "https"
            return "\(scheme):\(url)"
        }
        if let baseURL = URL(string: base), let r = URL(string: url, relativeTo: baseURL) {
            return r.absoluteString
        }
        return sourceBase + (url.hasPrefix("/") ? "" : "/") + url
    }
}
```

- [ ] **Step 3.2：构建验证**

```bash
xcodebuild -project Legado.xcodeproj -scheme Legado \
  -destination 'platform=iOS Simulator,id=962E405B-C2DC-463C-889D-FC51D1438E83' \
  -quiet build 2>&1 | grep -E "error:|BUILD"
```

期望：`** BUILD SUCCEEDED **`

- [ ] **Step 3.3：Commit**

```bash
cd /Users/alina/Documents/Lei/legado
git add IOS/Legado/App/Core/Services/DeepCheckPipeline.swift
git commit -m "feat(deep-check): DeepCheckPipeline 探索管线（5步）"
```

---

## Task 4：DeepCheckPipeline — 搜索管线

**Files:**
- Modify: `IOS/Legado/App/Core/Services/DeepCheckPipeline.swift`

- [ ] **Step 4.1：在 `DeepCheckPipeline` 末尾（`}` 前）添加搜索管线**

```swift
    // MARK: - Search Pipeline (3 steps)

    static func runSearch(
        source: BookSource,
        keyword: String = "小说",
        onStep: @escaping (DeepCheckStepResult) -> Void
    ) async -> [DeepCheckStepResult] {
        let inner = Task<[DeepCheckStepResult], Never> {
            await _runSearch(source: source, keyword: keyword, onStep: onStep)
        }
        let timeout = Task {
            try? await Task.sleep(nanoseconds: UInt64(perSourceTimeout * 1_000_000_000))
            inner.cancel()
        }
        let result = await inner.value
        timeout.cancel()
        return result
    }

    private static func _runSearch(
        source: BookSource,
        keyword: String,
        onStep: @escaping (DeepCheckStepResult) -> Void
    ) async -> [DeepCheckStepResult] {
        var steps = (5..<8).map { DeepCheckStepResult.pending(DeepCheckStepKind(rawValue: $0)!) }

        func emit(_ s: DeepCheckStepResult) { onStep(s) }
        func skipFrom(_ localIdx: Int, reason: String? = nil) {
            for j in localIdx..<3 {
                steps[j].status = .skipped
                steps[j].errorMessage = reason
                emit(steps[j])
            }
        }

        // ── Step 1: fetchSearchPage ──────────────────────────────────────────
        guard !Task.isCancelled else { skipFrom(0, reason: "已取消"); return steps }
        steps[0].status = .running; emit(steps[0])

        guard let searchTmpl = source.searchUrl, !searchTmpl.isEmpty else {
            steps[0].status = .failed; steps[0].errorMessage = "searchUrl 未配置"
            emit(steps[0]); skipFrom(1); return steps
        }
        var baseCtx = AnalyzeContext(source: source, baseUrl: source.bookSourceUrl)
        let parsedSearch = AnalyzeUrl.parse(
            searchTmpl, variables: ["key": keyword, "page": "1"], context: baseCtx)
        let searchUrl = parsedSearch.url.hasPrefix("http") ? parsedSearch.url
                      : source.bookSourceUrl + parsedSearch.url
        var searchHeaders = parsedSearch.headers
        source.headerDictionary.forEach { searchHeaders[$0.key] = $0.value }

        let t1 = Date()
        let searchBody: String
        do {
            if parsedSearch.webView {
                searchBody = (try? await HeadlessWebViewLoader.fetch(
                    urlString: searchUrl, headers: searchHeaders, injectJs: parsedSearch.webJs)) ?? ""
            } else {
                searchBody = try await NetworkManager.shared.request(
                    searchUrl, headers: HTTPHeaders(searchHeaders), source: source)
            }
        } catch {
            steps[0].durationMs = ms(since: t1)
            steps[0].status = .failed; steps[0].errorMessage = error.localizedDescription
            emit(steps[0]); skipFrom(1); return steps
        }
        steps[0].durationMs = ms(since: t1)
        guard !searchBody.isEmpty else {
            steps[0].status = .failed; steps[0].errorMessage = "搜索响应体为空"
            emit(steps[0]); skipFrom(1); return steps
        }
        steps[0].status = .passed; steps[0].summary = "HTTP 200"
        steps[0].detailPreview = String(searchBody.prefix(300)); emit(steps[0])

        // ── Step 2: parseSearchList ──────────────────────────────────────────
        guard !Task.isCancelled else { skipFrom(1, reason: "已取消"); return steps }
        steps[1].status = .running; emit(steps[1])

        guard let listRule = source.ruleSearchList,
              !listRule.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            steps[1].status = .failed; steps[1].errorMessage = "ruleSearchList 未配置"
            emit(steps[1]); skipFrom(2); return steps
        }
        let t2 = Date()
        var listCtx = AnalyzeContext(source: source, baseUrl: searchUrl)
        listCtx.result = searchBody
        let items = RuleExecutor.shared.executeList(listRule, in: &listCtx)
        steps[1].durationMs = ms(since: t2)
        guard !items.isEmpty else {
            steps[1].status = .failed; steps[1].errorMessage = "搜索结果为空（0条）"
            emit(steps[1]); skipFrom(2); return steps
        }
        steps[1].status = .passed; steps[1].summary = "\(items.count)条搜索结果"; emit(steps[1])

        // ── Step 3: parseSearchFields ────────────────────────────────────────
        guard !Task.isCancelled else { skipFrom(2, reason: "已取消"); return steps }
        steps[2].status = .running; emit(steps[2])

        let t3 = Date()
        var itemCtx = AnalyzeContext(source: source, baseUrl: searchUrl)
        itemCtx.result = items[0]
        let name = execute(source.ruleSearchName ?? "", ctx: &itemCtx)
        let noteUrlRaw = execute(source.ruleSearchNoteUrl ?? "", ctx: &itemCtx)
        steps[2].durationMs = ms(since: t3)
        guard !name.isEmpty else {
            steps[2].status = .failed; steps[2].errorMessage = "书名解析为空（ruleSearchName）"
            emit(steps[2]); return steps
        }
        steps[2].status = .passed
        steps[2].summary = "《\(name)》"
        steps[2].detailPreview = "名：\(name)\n链接：\(noteUrlRaw.isEmpty ? "（无）" : noteUrlRaw)"
        emit(steps[2])
        return steps
    }
```

- [ ] **Step 4.2：构建验证**

```bash
xcodebuild -project Legado.xcodeproj -scheme Legado \
  -destination 'platform=iOS Simulator,id=962E405B-C2DC-463C-889D-FC51D1438E83' \
  -quiet build 2>&1 | grep -E "error:|BUILD"
```

期望：`** BUILD SUCCEEDED **`

- [ ] **Step 4.3：Commit**

```bash
cd /Users/alina/Documents/Lei/legado
git add IOS/Legado/App/Core/Services/DeepCheckPipeline.swift
git commit -m "feat(deep-check): DeepCheckPipeline 搜索管线（3步）"
```

---

## Task 5：DeepCheckViewModel

**Files:**
- Create: `IOS/Legado/App/Features/BookSource/ViewModels/DeepCheckViewModel.swift`

- [ ] **Step 5.1：新建 `DeepCheckViewModel.swift`**

```swift
// IOS/Legado/App/Features/BookSource/ViewModels/DeepCheckViewModel.swift
import Foundation
import Observation

@Observable
class DeepCheckViewModel {

    // MARK: - State
    var entries:    [DeepCheckEntry] = []
    var isRunning   = false
    var totalCount  = 0
    var doneCount   = 0

    // MARK: - Batch config (not used in single-source mode)
    var alsoRunSearch = false    // only affects sources that have exploreUrl
    var concurrency   = 3        // sliding-window concurrency, 1-5
    var searchKeyword = "小说"   // override in batch config sheet

    // MARK: - Computed summaries
    var passedCount:  Int { entries.filter { $0.result.overallStatus == .passed  }.count }
    var partialCount: Int { entries.filter { $0.result.overallStatus == .partial }.count }
    var failedCount:  Int { entries.filter { $0.result.overallStatus == .failed  }.count }
    var skippedCount: Int { entries.filter { $0.result.overallStatus == .skipped }.count }
    var summaryText: String { "✅\(passedCount)  🟠\(partialCount)  ❌\(failedCount)  ⏭\(skippedCount)" }

    private var cancelTask: Task<Void, Never>?
    private let db = DatabaseManager.shared

    // MARK: - Batch start (sliding-window TaskGroup)

    func start(sources: [BookSource]) async {
        entries = []
        totalCount = sources.count
        doneCount = 0
        isRunning = true

        let semaphore = AsyncSemaphore(concurrency)
        cancelTask = Task { [weak self] in
            guard let self else { return }
            var iter = sources.makeIterator()
            await withTaskGroup(of: Void.self) { group in
                for _ in 0..<min(concurrency, sources.count) {
                    if let src = iter.next() {
                        group.addTask { [weak self] in
                            await semaphore.wait()
                            defer { Task { await semaphore.signal() } }
                            await self?.runOneSource(src)
                        }
                    }
                }
                for await _ in group {
                    if let src = iter.next() {
                        group.addTask { [weak self] in
                            await semaphore.wait()
                            defer { Task { await semaphore.signal() } }
                            await self?.runOneSource(src)
                        }
                    }
                }
            }
            await MainActor.run { [weak self] in self?.isRunning = false }
        }
        await cancelTask?.value
    }

    // MARK: - Single-source: user triggers search after explore
    func runSearchFor(sourceUrl: String) async {
        guard let idx = entries.firstIndex(where: { $0.id == sourceUrl }),
              entries[idx].result.hasSearch else { return }
        let source = await getSource(url: sourceUrl)
        guard let source else { return }

        await MainActor.run { [weak self] in
            guard let self, let i = entries.firstIndex(where: { $0.id == sourceUrl }) else { return }
            entries[i].execStatus = .running
            entries[i].result.searchSteps = (5..<8).map {
                DeepCheckStepResult.pending(DeepCheckStepKind(rawValue: $0)!)
            }
        }
        let searchSteps = await DeepCheckPipeline.runSearch(
            source: source, keyword: searchKeyword
        ) { [weak self] step in
            Task { @MainActor [weak self] in self?.applyStep(step, sourceUrl: sourceUrl) }
        }
        await MainActor.run { [weak self] in
            guard let self, let i = entries.firstIndex(where: { $0.id == sourceUrl }) else { return }
            entries[i].result.searchSteps = searchSteps
            entries[i].execStatus = entries[i].result.overallStatus
        }
        await writeCheckState(sourceUrl: sourceUrl)
    }

    // MARK: - Cancel
    func cancel() { cancelTask?.cancel() }

    // MARK: - Post-completion cleanup

    func disableFailedSources() async {
        let failed = entries.filter { $0.result.overallStatus == .failed || $0.result.overallStatus == .partial }
            .map(\.result.sourceUrl)
        guard !failed.isEmpty else { return }
        let all = (try? await db.getAllBookSources()) ?? []
        for var src in all where failed.contains(src.bookSourceUrl) {
            src.enabled = false
            try? await db.saveCheckResult(src)
        }
    }

    func deleteFailedSources() async {
        let failed = entries.filter { $0.result.overallStatus == .failed || $0.result.overallStatus == .partial }
            .map(\.result.sourceUrl)
        guard !failed.isEmpty else { return }
        let all = (try? await db.getAllBookSources()) ?? []
        for src in all where failed.contains(src.bookSourceUrl) {
            try? await db.deleteBookSource(src)
        }
    }

    // MARK: - Internal

    private func runOneSource(_ source: BookSource) async {
        guard !Task.isCancelled else {
            await addCancelledEntry(source); return
        }
        let hasExplore = !(source.exploreUrl ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasSearch  = !(source.searchUrl ?? "").isEmpty

        // Sources with no rules: skip immediately
        if !hasExplore && !hasSearch {
            var result = makeResult(source: source, hasExplore: false, hasSearch: false)
            result.skippedReason = "此书源无搜索/发现规则"
            let entry = DeepCheckEntry(id: source.bookSourceUrl, result: result, execStatus: .skipped)
            await MainActor.run { [weak self] in self?.addEntry(entry) }
            await bumpDone()
            return
        }

        // Create entry with pre-initialised pending steps
        var result = makeResult(source: source, hasExplore: hasExplore, hasSearch: hasSearch)
        let willRunSearch = !hasExplore || alsoRunSearch
        if hasExplore {
            result.exploreSteps = (0..<5).map { DeepCheckStepResult.pending(DeepCheckStepKind(rawValue: $0)!) }
        }
        if willRunSearch && hasSearch {
            result.searchSteps = (5..<8).map { DeepCheckStepResult.pending(DeepCheckStepKind(rawValue: $0)!) }
        }
        let entry = DeepCheckEntry(id: source.bookSourceUrl, result: result, execStatus: .running)
        await MainActor.run { [weak self] in self?.addEntry(entry) }

        // Run explore
        if hasExplore {
            let steps = await DeepCheckPipeline.runExplore(source: source) { [weak self] step in
                Task { @MainActor [weak self] in self?.applyStep(step, sourceUrl: source.bookSourceUrl) }
            }
            await MainActor.run { [weak self] in
                guard let self, let i = entries.firstIndex(where: { $0.id == source.bookSourceUrl }) else { return }
                entries[i].result.exploreSteps = steps
            }
            // Write checkState after explore (may be updated again after search)
            await writeCheckStateFromSteps(source: source, exploreSteps: steps, searchSteps: nil,
                                           willRunSearch: willRunSearch && hasSearch)
        }

        // Run search
        if willRunSearch && hasSearch && !Task.isCancelled {
            let steps = await DeepCheckPipeline.runSearch(source: source, keyword: searchKeyword) { [weak self] step in
                Task { @MainActor [weak self] in self?.applyStep(step, sourceUrl: source.bookSourceUrl) }
            }
            await MainActor.run { [weak self] in
                guard let self, let i = entries.firstIndex(where: { $0.id == source.bookSourceUrl }) else { return }
                entries[i].result.searchSteps = steps
            }
        }

        // Final state
        await MainActor.run { [weak self] in
            guard let self, let i = entries.firstIndex(where: { $0.id == source.bookSourceUrl }) else { return }
            entries[i].execStatus = entries[i].result.overallStatus
        }
        await writeCheckState(sourceUrl: source.bookSourceUrl)
        await bumpDone()
    }

    @MainActor
    private func applyStep(_ step: DeepCheckStepResult, sourceUrl: String) {
        guard let i = entries.firstIndex(where: { $0.id == sourceUrl }) else { return }
        if step.kind.pipeline == .explore {
            if let j = entries[i].result.exploreSteps.firstIndex(where: { $0.kind == step.kind }) {
                entries[i].result.exploreSteps[j] = step
            } else {
                entries[i].result.exploreSteps.append(step)
            }
        } else {
            if let j = entries[i].result.searchSteps.firstIndex(where: { $0.kind == step.kind }) {
                entries[i].result.searchSteps[j] = step
            } else {
                entries[i].result.searchSteps.append(step)
            }
        }
    }

    @MainActor
    private func addEntry(_ entry: DeepCheckEntry) {
        entries.insert(entry, at: 0)
    }

    private func bumpDone() async {
        await MainActor.run { [weak self] in self?.doneCount += 1 }
    }

    private func addCancelledEntry(_ source: BookSource) async {
        var result = makeResult(source: source,
                                hasExplore: !(source.exploreUrl ?? "").isEmpty,
                                hasSearch: !(source.searchUrl ?? "").isEmpty)
        result.skippedReason = "已取消"
        let entry = DeepCheckEntry(id: source.bookSourceUrl, result: result, execStatus: .skipped)
        await MainActor.run { [weak self] in self?.addEntry(entry) }
        await bumpDone()
    }

    private func makeResult(source: BookSource, hasExplore: Bool, hasSearch: Bool) -> DeepCheckSourceResult {
        DeepCheckSourceResult(id: source.bookSourceUrl, sourceName: source.bookSourceName,
                              sourceUrl: source.bookSourceUrl,
                              hasExplore: hasExplore, hasSearch: hasSearch)
    }

    private func writeCheckState(sourceUrl: String) async {
        guard let i = await MainActor.run(body: { entries.firstIndex(where: { $0.id == sourceUrl }) })
        else { return }
        let entry = await MainActor.run { entries[i] }
        if entry.execStatus == .skipped { return } // no rules or cancelled — don't touch checkState
        let all = (try? await db.getAllBookSources()) ?? []
        guard var src = all.first(where: { $0.bookSourceUrl == sourceUrl }) else { return }
        let status = entry.result.overallStatus
        src.checkState = (status == .passed) ? 1 : 3
        try? await db.saveCheckResult(src)
    }

    private func writeCheckStateFromSteps(source: BookSource, exploreSteps: [DeepCheckStepResult],
                                          searchSteps: [DeepCheckStepResult]?,
                                          willRunSearch: Bool) async {
        // Write only if search won't run (avoids double-write; final write happens in writeCheckState)
        guard !willRunSearch else { return }
        let passed = exploreSteps.allSatisfy { $0.status == .passed || $0.status == .skipped }
                  && exploreSteps.contains { $0.status == .passed }
        var src = source
        src.checkState = passed ? 1 : 3
        try? await db.saveCheckResult(src)
    }

    private func getSource(url: String) async -> BookSource? {
        let all = try? await db.getAllBookSources()
        return all?.first { $0.bookSourceUrl == url }
    }
}
```

- [ ] **Step 5.2：构建验证**

```bash
xcodebuild -project Legado.xcodeproj -scheme Legado \
  -destination 'platform=iOS Simulator,id=962E405B-C2DC-463C-889D-FC51D1438E83' \
  -quiet build 2>&1 | grep -E "error:|BUILD"
```

期望：`** BUILD SUCCEEDED **`

- [ ] **Step 5.3：Commit**

```bash
cd /Users/alina/Documents/Lei/legado
git add IOS/Legado/App/Features/BookSource/ViewModels/DeepCheckViewModel.swift
git commit -m "feat(deep-check): DeepCheckViewModel（滑动窗口并发 + checkState 回写）"
```

---

## Task 6：DeepCheckConfigSheet

**Files:**
- Create: `IOS/Legado/App/Features/BookSource/Views/DeepCheckConfigSheet.swift`

- [ ] **Step 6.1：新建 `DeepCheckConfigSheet.swift`**

```swift
// IOS/Legado/App/Features/BookSource/Views/DeepCheckConfigSheet.swift
import SwiftUI

enum DeepCheckScope: String, CaseIterable, Identifiable {
    case all       = "全部已启用书源"
    case untested  = "仅未测书源"
    case failedToo = "未测+失败书源"
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
    let onStart: (DeepCheckViewModel) -> Void

    @State private var scope: DeepCheckScope = .all
    @State private var keyword = "小说"
    @State private var alsoRunSearch = false
    @State private var concurrency = 3

    private var targetCount: Int { scope.filter(allSources).count }

    var body: some View {
        NavigationView {
            Form {
                Section("检查范围") {
                    Picker("范围", selection: $scope) {
                        ForEach(DeepCheckScope.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Text("共 \(targetCount) 个书源").font(.caption).foregroundColor(.secondary)
                }

                Section("搜索测试词") {
                    TextField("搜索词（默认：小说）", text: $keyword)
                        .autocorrectionDisabled()
                }

                Section {
                    Toggle("探索后自动跑搜索链路", isOn: $alsoRunSearch)
                    Text("仅对有发现规则的书源有额外效果；无发现规则的书源始终跑搜索。")
                        .font(.caption).foregroundColor(.secondary)
                }

                Section("并发数（1-5）") {
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
                        onStart(vm)
                        dismiss()
                    }
                    .disabled(targetCount == 0)
                }
            }
        }
    }
}
```

- [ ] **Step 6.2：构建验证**

```bash
xcodebuild -project Legado.xcodeproj -scheme Legado \
  -destination 'platform=iOS Simulator,id=962E405B-C2DC-463C-889D-FC51D1438E83' \
  -quiet build 2>&1 | grep -E "error:|BUILD"
```

- [ ] **Step 6.3：Commit**

```bash
cd /Users/alina/Documents/Lei/legado
git add "IOS/Legado/App/Features/BookSource/Views/DeepCheckConfigSheet.swift"
git commit -m "feat(deep-check): DeepCheckConfigSheet"
```

---

## Task 7：DeepCheckView

**Files:**
- Create: `IOS/Legado/App/Features/BookSource/Views/DeepCheckView.swift`

- [ ] **Step 7.1：新建 `DeepCheckView.swift`**

```swift
// IOS/Legado/App/Features/BookSource/Views/DeepCheckView.swift
import SwiftUI

// MARK: - Main View

struct DeepCheckView: View {
    @State var vm: DeepCheckViewModel
    let sources: [BookSource]   // nil for single-source (pass [source])
    let isSingleSource: Bool

    var body: some View {
        VStack(spacing: 0) {
            if !isSingleSource {
                batchHeader
            }
            resultsListView
            if !vm.isRunning && !vm.entries.isEmpty && !isSingleSource {
                batchFooter
            }
        }
        .navigationTitle(isSingleSource ? "深度检查" : "深度检查结果")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if vm.isRunning {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("停止", role: .destructive) { vm.cancel() }
                }
            }
        }
        .task {
            guard !sources.isEmpty else { return }
            await vm.start(sources: sources)
        }
    }

    // MARK: Batch header
    private var batchHeader: some View {
        VStack(spacing: 6) {
            if vm.isRunning || vm.totalCount > 0 {
                ProgressView(value: Double(vm.doneCount), total: Double(max(1, vm.totalCount)))
                    .padding(.horizontal)
            }
            Text(vm.summaryText)
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.bottom, 4)
        }
        .padding(.top, 8)
    }

    // MARK: Results list
    private var resultsListView: some View {
        List(vm.entries) { entry in
            DeepCheckSourceRow(entry: entry, isSingleSource: isSingleSource) {
                Task { await vm.runSearchFor(sourceUrl: entry.id) }
            }
        }
        .listStyle(.plain)
    }

    // MARK: Batch footer
    private var batchFooter: some View {
        VStack(spacing: 8) {
            Divider()
            HStack(spacing: 16) {
                Button(role: .destructive) { Task { await vm.disableFailedSources() } } label: {
                    Label("禁用失败书源", systemImage: "eye.slash")
                        .font(.subheadline)
                }
                .disabled(vm.failedCount + vm.partialCount == 0)
                Button(role: .destructive) { Task { await vm.deleteFailedSources() } } label: {
                    Label("删除失败书源", systemImage: "trash")
                        .font(.subheadline)
                }
                .disabled(vm.failedCount + vm.partialCount == 0)
            }
            .padding(.vertical, 10)
        }
    }
}

// MARK: - Source Row

struct DeepCheckSourceRow: View {
    let entry: DeepCheckEntry
    let isSingleSource: Bool
    let onRunSearch: () -> Void

    @State private var exploreExpanded = true
    @State private var searchExpanded  = true

    private var result: DeepCheckSourceResult { entry.result }
    private var totalMs: Int {
        (result.exploreSteps + result.searchSteps).reduce(0) { $0 + $1.durationMs }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Header
            HStack {
                statusIcon(for: entry.result.overallStatus)
                Text(result.sourceName).font(.headline).lineLimit(1)
                Spacer()
                if entry.execStatus == .running {
                    ProgressView().scaleEffect(0.7)
                } else if totalMs > 0 {
                    Text("\(totalMs)ms").font(.caption).foregroundColor(.secondary)
                }
            }

            if let reason = result.skippedReason {
                Text(reason).font(.caption).foregroundColor(.secondary).padding(.leading, 28)
            }

            // Explore steps
            if !result.exploreSteps.isEmpty {
                pipelineSection(
                    title: "发现链路", steps: result.exploreSteps,
                    expanded: $exploreExpanded
                )
            }

            // Search steps
            if !result.searchSteps.isEmpty {
                pipelineSection(
                    title: "搜索链路", steps: result.searchSteps,
                    expanded: $searchExpanded
                )
            }

            // "继续搜索" button (single-source mode, awaitingSearch)
            if isSingleSource && entry.execStatus == .awaitingSearch && result.hasSearch {
                Button(action: onRunSearch) {
                    Label("继续跑搜索链路", systemImage: "magnifyingglass")
                        .font(.subheadline)
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 4)
            }
        }
        .padding(.vertical, 4)
    }

    private func pipelineSection(title: String, steps: [DeepCheckStepResult],
                                  expanded: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { expanded.wrappedValue.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: expanded.wrappedValue ? "chevron.down" : "chevron.right")
                        .font(.caption2).foregroundColor(.secondary)
                    Text(title).font(.caption).bold().foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)
            .padding(.leading, 28)

            if expanded.wrappedValue {
                ForEach(steps) { step in
                    DeepCheckStepRow(step: step)
                        .padding(.leading, 36)
                }
            }
        }
    }

    private func statusIcon(for status: SourceCheckStatus) -> some View {
        Group {
            switch status {
            case .passed:
                Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
            case .partial:
                Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
            case .failed:
                Image(systemName: "xmark.circle.fill").foregroundColor(.red)
            case .skipped:
                Image(systemName: "minus.circle").foregroundColor(.secondary)
            case .running:
                ProgressView().scaleEffect(0.7)
            case .awaitingSearch:
                Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
            case .pending:
                Image(systemName: "circle").foregroundColor(.secondary)
            }
        }
        .font(.title3)
    }
}

// MARK: - Step Row

struct DeepCheckStepRow: View {
    let step: DeepCheckStepResult
    @State private var previewExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                stepIcon
                Text(step.kind.displayName).font(.caption)
                Spacer()
                if !step.summary.isEmpty {
                    Text(step.summary).font(.caption).foregroundColor(.secondary).lineLimit(1)
                }
                if step.durationMs > 0 {
                    Text("\(step.durationMs)ms").font(.caption2).foregroundColor(.secondary)
                }
                if step.detailPreview != nil {
                    Image(systemName: previewExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2).foregroundColor(.secondary)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if step.detailPreview != nil {
                    withAnimation(.easeInOut(duration: 0.15)) { previewExpanded.toggle() }
                }
            }

            if let err = step.errorMessage, !err.isEmpty {
                Text(err).font(.caption2).foregroundColor(.red).padding(.leading, 22)
            }

            if previewExpanded, let preview = step.detailPreview {
                Text(preview)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                    .padding(6)
                    .background(Color(.systemGray6))
                    .cornerRadius(4)
                    .padding(.leading, 22)
            }
        }
        .padding(.vertical, 1)
    }

    @ViewBuilder
    private var stepIcon: some View {
        switch step.status {
        case .passed:
            Image(systemName: "checkmark.circle.fill").foregroundColor(.green).font(.caption)
        case .failed:
            Image(systemName: "xmark.circle.fill").foregroundColor(.red).font(.caption)
        case .skipped:
            Image(systemName: "minus.circle").foregroundColor(.secondary).font(.caption)
        case .running:
            ProgressView().scaleEffect(0.55)
        case .pending:
            Image(systemName: "circle").foregroundColor(.secondary).font(.caption)
        }
    }
}
```

- [ ] **Step 7.2：构建验证**

```bash
xcodebuild -project Legado.xcodeproj -scheme Legado \
  -destination 'platform=iOS Simulator,id=962E405B-C2DC-463C-889D-FC51D1438E83' \
  -quiet build 2>&1 | grep -E "error:|BUILD"
```

期望：`** BUILD SUCCEEDED **`

- [ ] **Step 7.3：Commit**

```bash
cd /Users/alina/Documents/Lei/legado
git add "IOS/Legado/App/Features/BookSource/Views/DeepCheckView.swift"
git commit -m "feat(deep-check): DeepCheckView（分步可展开结果 + 探索/搜索管线标签）"
```

---

## Task 8：集成到 BookSourceListView

**Files:**
- Modify: `IOS/Legado/App/Features/BookSource/Views/BookSourceListView.swift`

- [ ] **Step 8.1：添加状态变量**

在 `BookSourceListView` 的 `@State` 属性区域（紧接现有的 `@State var showingCheckConfig` 等变量之后）追加：

```swift
@State private var showingDeepCheckConfig = false
@State private var deepCheckVM: DeepCheckViewModel? = nil
@State private var deepCheckSources: [BookSource] = []
@State private var showingDeepCheckResult = false
@State private var deepCheckSingleSource: BookSource? = nil
```

- [ ] **Step 8.2：在检查书源菜单末尾追加"深度检查..."**

找到 `BookSourceListView.swift` 第 121-133 行的 `Menu` 块，在 `ForEach(CheckScope.allCases)` 结束的 `}` 之后、外层 `Menu` 关闭 `}` 之前添加：

```swift
Divider()
Button {
    Task {
        deepCheckSources = (try? await DatabaseManager.shared.getAllBookSources()) ?? []
        showingDeepCheckConfig = true
    }
} label: {
    Label("深度检查...", systemImage: "stethoscope")
}
```

- [ ] **Step 8.3：在三点菜单中追加"深度检查"**

找到三点菜单（`BookSourceListView.swift` 第 66-68 行）中 `Button { debugSource = source }` 这行之后，`}` 关闭之前，追加：

```swift
Button { deepCheckSingleSource = source } label: {
    Label("深度检查", systemImage: "stethoscope")
}
```

- [ ] **Step 8.4：添加两个 sheet modifier**

在文件末尾现有 `.sheet(item: $debugSource)` modifier 之后追加两个 sheet：

```swift
// 批量深度检查：配置弹窗
.sheet(isPresented: $showingDeepCheckConfig) {
    DeepCheckConfigSheet(allSources: deepCheckSources) { vm in
        deepCheckVM = vm
        showingDeepCheckResult = true
        Task { await vm.start(sources: DeepCheckScope.all.filter(deepCheckSources)) }
    }
}
// 批量深度检查：结果视图
.sheet(isPresented: $showingDeepCheckResult) {
    if let vm = deepCheckVM {
        NavigationView {
            DeepCheckView(vm: vm, sources: [], isSingleSource: false)
        }
    }
}
// 单书源深度检查
.sheet(item: $deepCheckSingleSource) { source in
    NavigationView {
        DeepCheckView(
            vm: DeepCheckViewModel(),
            sources: [source],
            isSingleSource: true
        )
    }
}
```

> **注意**：批量检查的 `start` 应由 `DeepCheckConfigSheet.onStart` 回调传入的 vm 已配置正确 scope，此处 `.start(sources:)` 调用需传入 `scope.filter(deepCheckSources)`。需在 `DeepCheckConfigSheet.onStart` 回调中传递过滤后的 sources。修改 `DeepCheckConfigSheet` 的 `onStart` 闭包签名为 `(DeepCheckViewModel, [BookSource]) -> Void`，并在 sheet 中读取过滤后的 sources 传入。

- [ ] **Step 8.5：修正 `DeepCheckConfigSheet` onStart 签名传递 sources**

打开 `DeepCheckConfigSheet.swift`，修改 `onStart` 的类型和调用：

```swift
// 修改属性声明
let onStart: (DeepCheckViewModel, [BookSource]) -> Void

// 修改"开始检查"按钮逻辑
Button("开始检查") {
    let vm = DeepCheckViewModel()
    vm.alsoRunSearch = alsoRunSearch
    vm.concurrency   = concurrency
    vm.searchKeyword = keyword.isEmpty ? "小说" : keyword
    let filtered = scope.filter(allSources)
    onStart(vm, filtered)
    dismiss()
}
```

在 `BookSourceListView.swift` 中，更新 `DeepCheckConfigSheet` 的使用：

```swift
.sheet(isPresented: $showingDeepCheckConfig) {
    DeepCheckConfigSheet(allSources: deepCheckSources) { vm, filtered in
        deepCheckVM = vm
        showingDeepCheckResult = true
        Task { await vm.start(sources: filtered) }
    }
}
```

- [ ] **Step 8.6：构建验证**

```bash
xcodebuild -project Legado.xcodeproj -scheme Legado \
  -destination 'platform=iOS Simulator,id=962E405B-C2DC-463C-889D-FC51D1438E83' \
  -quiet build 2>&1 | grep -E "error:|BUILD"
```

期望：`** BUILD SUCCEEDED **`

- [ ] **Step 8.7：Commit**

```bash
cd /Users/alina/Documents/Lei/legado
git add "IOS/Legado/App/Features/BookSource/Views/BookSourceListView.swift" \
        "IOS/Legado/App/Features/BookSource/Views/DeepCheckConfigSheet.swift"
git commit -m "feat(deep-check): 集成到书源列表菜单 + 单书源三点菜单"
```

---

## Task 9：集成验证（AutoTest + 模拟器）

**Files:**
- Modify（临时）: `IOS/Legado/App/LegadoApp.swift`

- [ ] **Step 9.1：添加 AutoTest**

```swift
// 临时修改 LegadoApp.swift
import SwiftUI
import GRDB

@main
struct LegadoApp: App {
    var body: some Scene {
        WindowGroup {
            MainTabView().task { await DeepCheckAutoTest.run() }
        }
    }
}

private enum DeepCheckAutoTest {
    static func run() async {
        guard CommandLine.arguments.contains("--autotest-deepcheck") else { return }
        try? await Task.sleep(nanoseconds: 4_000_000_000)
        print("🧪 [DeepCheckTest] 开始深度检查测试")

        let sources = (try? await DatabaseManager.shared.getAllBookSources()) ?? []
        let maoyou = sources.first { $0.bookSourceName.contains("猫眼") && $0.enabled }
        guard let src = maoyou else { print("❌ [DeepCheckTest] 找不到猫眼书源"); return }
        print("✅ [DeepCheckTest] 测试书源: \(src.bookSourceName)")

        // Test explore pipeline
        print("🔍 [DeepCheckTest] 开始探索管线...")
        let exploreSteps = await DeepCheckPipeline.runExplore(source: src) { step in
            let icon = step.status == .passed ? "✅" : step.status == .failed ? "❌" : "⏭"
            print("\(icon) 探索[\(step.kind.displayName)] \(step.summary) \(step.errorMessage ?? "")")
        }
        let explorepassed = exploreSteps.filter { $0.status == .passed }.count
        print("✅ [DeepCheckTest] 探索管线: \(explorepassed)/5 步通过")

        // Test search pipeline  
        print("🔍 [DeepCheckTest] 开始搜索管线...")
        let searchSteps = await DeepCheckPipeline.runSearch(source: src, keyword: "斗破苍穹") { step in
            let icon = step.status == .passed ? "✅" : step.status == .failed ? "❌" : "⏭"
            print("\(icon) 搜索[\(step.kind.displayName)] \(step.summary) \(step.errorMessage ?? "")")
        }
        let searchPassed = searchSteps.filter { $0.status == .passed }.count
        print("✅ [DeepCheckTest] 搜索管线: \(searchPassed)/3 步通过")

        if explorepassed >= 4 && searchPassed == 3 {
            print("🎉 [DeepCheckTest] 深度检查管线验证通过！")
        } else {
            print("❌ [DeepCheckTest] 有步骤失败，请检查日志")
        }
    }
}
```

- [ ] **Step 9.2：构建并安装**

```bash
xcodebuild -project Legado.xcodeproj -scheme Legado \
  -destination 'platform=iOS Simulator,id=962E405B-C2DC-463C-889D-FC51D1438E83' \
  build 2>&1 | grep "BUILD"

APP=$(find ~/Library/Developer/Xcode/DerivedData/Legado-*/Build/Products/Debug-iphonesimulator/Legado.app -maxdepth 0 2>/dev/null | tail -1)
xcrun simctl install 962E405B-C2DC-463C-889D-FC51D1438E83 "$APP"
```

- [ ] **Step 9.3：运行 AutoTest**

```bash
SIM=962E405B-C2DC-463C-889D-FC51D1438E83
xcrun simctl terminate $SIM com.legado.app 2>/dev/null
sleep 1
xcrun simctl launch --console-pty $SIM com.legado.app --autotest-deepcheck \
  > /tmp/legado_deepcheck_test.log 2>&1 &
sleep 50
grep -E "DeepCheckTest|探索|搜索|🎉|❌|✅" /tmp/legado_deepcheck_test.log | head -20
```

期望看到：
```
🎉 [DeepCheckTest] 深度检查管线验证通过！
```

- [ ] **Step 9.4：恢复 LegadoApp.swift**

```swift
import SwiftUI

@main
struct LegadoApp: App {
    var body: some Scene {
        WindowGroup {
            MainTabView()
        }
    }
}
```

- [ ] **Step 9.5：最终构建验证**

```bash
xcodebuild -project Legado.xcodeproj -scheme Legado \
  -destination 'platform=iOS Simulator,id=962E405B-C2DC-463C-889D-FC51D1438E83' \
  build 2>&1 | grep "BUILD"
```

期望：`** BUILD SUCCEEDED **`

- [ ] **Step 9.6：最终 Commit**

```bash
cd /Users/alina/Documents/Lei/legado
git add IOS/Legado/App/LegadoApp.swift
git commit -m "feat(deep-check): 深度检查功能完整实现

- DeepCheckPipeline: 探索5步 + 搜索3步管线，60s超时，级联失败，webView支持
- ExploreUrlParser: 从 ExploreCategoryViewModel 提取的共享分类解析工具  
- DeepCheckViewModel: 滑动窗口并发(1-5)，checkState回写，取消支持
- DeepCheckView: 分步可展开结果，pass/partial/fail/skip状态徽章
- DeepCheckConfigSheet: 批量配置（范围/搜索词/自动搜索/并发数）
- BookSourceListView: 检查书源菜单第4项 + 单书源三点菜单"深度检查"
- AsyncSemaphore 提取到 Core/Utils，ExploreCategory 提取到 ExploreUrlParser

AutoTest验证：猫眼看书（优++）探索5步 + 搜索3步全部通过"
```

---

## 自检清单

### Spec 覆盖度

| 规格要求 | 对应 Task |
|---|---|
| 探索管线 5 步（parseExploreUrl → fetchCategoryPage → parseBookList → parseBookFields → verifyDetailPage）| Task 3 |
| 搜索管线 3 步（fetchSearchPage → parseSearchList → parseSearchFields）| Task 4 |
| 失败级联：步骤 N 失败 → 后续 skipped | Task 3-4（各步 `guard` + `skipFrom()`）|
| webView 支持 | Task 3-4（HeadlessWebViewLoader 分支）|
| 书源请求头（Authorization 等）| Task 3-4（`source.headerDictionary` 合并）|
| noteUrl 相对路径解析 | Task 3（`resolveUrl()` 辅助方法）|
| 60s 单源超时 | Task 3-4（`Task.cancel()` 包装）|
| 每步两次 onStep（running + 最终状态）| Task 3-4（各步 `emit()` 两次）|
| 无 `exploreUrl` 也无 `searchUrl` → skipped | Task 5（`runOneSource` 前置检查）|
| 批量滑动窗口并发 | Task 5（`withTaskGroup` + `AsyncSemaphore`）|
| 单源"继续搜索"按钮 | Task 5（`runSearchFor()`）+ Task 7（按钮 UI）|
| checkState 回写（pass→1, fail→3，跳过→不写）| Task 5（`writeCheckState()`）|
| `SourceCheckStatus.partial`（探索✅搜索❌）| Task 1（模型）+ Task 5（计算）|
| 取消：运行中 → 剩余 skipped；队列中 → skippedReason | Task 5（`addCancelledEntry()`）|
| 批量配置 Sheet（范围/词/自动搜索/并发）| Task 6 |
| 检查书源菜单第 4 项"深度检查..." | Task 8 |
| 单书源三点菜单"深度检查" | Task 8 |
| 结果视图：分步展开 + detailPreview | Task 7 |
| 批量完成后"禁用/删除失败书源"按钮 | Task 5（方法）+ Task 7（UI）|
| ExploreUrlParser 提取，ExploreView 复用 | Task 2 |
| AsyncSemaphore 提取到共享位置 | Task 1 |
