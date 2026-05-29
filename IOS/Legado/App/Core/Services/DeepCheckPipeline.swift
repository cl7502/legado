// IOS/Legado/App/Core/Services/DeepCheckPipeline.swift
import Foundation
import Alamofire

struct DeepCheckPipeline {

    static let perSourceTimeout: TimeInterval = 60

    // MARK: - Explore Pipeline (5 steps)

    /// Run the explore pipeline for a source with an exploreUrl.
    /// Each step fires onStep TWICE: once with .running (start), once with final status (end).
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

        guard let listRule = source.ruleExploreList,
              !listRule.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
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
        // Merge URL-embedded headers with source-level headers (same pattern as Step 2)
        var detailHeaders = parsedDetail.headers
        source.headerDictionary.forEach { detailHeaders[$0.key] = $0.value }
        let t5 = Date()
        do {
            let body: String
            if parsedDetail.webView {
                body = (try? await HeadlessWebViewLoader.fetch(
                    urlString: detailUrl, headers: detailHeaders,
                    injectJs: parsedDetail.webJs)) ?? ""
            } else {
                body = try await NetworkManager.shared.request(
                    detailUrl, headers: HTTPHeaders(detailHeaders), source: source)
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

    static func ms(since start: Date) -> Int {
        Int(Date().timeIntervalSince(start) * 1000)
    }

    private static func execute(_ rule: String, ctx: inout AnalyzeContext) -> String {
        guard !rule.isEmpty else { return "" }
        return RuleExecutor.shared.execute(rule, in: &ctx) ?? ""
    }

    static func resolveUrl(_ url: String, base: String, sourceBase: String) -> String {
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
