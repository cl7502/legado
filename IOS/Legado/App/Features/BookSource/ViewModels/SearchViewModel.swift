import SwiftUI
import Combine
import Alamofire

/// 搜索业务逻辑
@MainActor
class SearchViewModel: ObservableObject {
    @Published var searchResults: [SearchResult] = []
    @Published var isSearching = false
    @Published var searchProgress: Float = 0

    private let db = DatabaseManager.shared
    private let network = NetworkManager.shared
    private let ruleExecutor = RuleExecutor.shared

    func search(_ query: String) async {
        guard !query.isEmpty else { return }

        isSearching = true
        searchResults = []
        searchProgress = 0

        do {
            let sources = try await db.getEnabledBookSources()
            guard !sources.isEmpty else { isSearching = false; return }

            let total = Float(sources.count)
            var done: Float = 0

            await withTaskGroup(of: [SearchResult].self) { group in
                for source in sources {
                    group.addTask { await self.searchInSource(query, source: source) }
                }
                for await results in group {
                    self.searchResults.append(contentsOf: results)
                    done += 1
                    self.searchProgress = done / total
                }
            }

            // P2-A: 按 name+author 组合去重，保留每组的第一条结果
            var seen = Set<String>()
            self.searchResults = self.searchResults.filter { result in
                let key = "\(result.name)|\(result.author)"
                return seen.insert(key).inserted
            }
        } catch {
            print("❌ [Search Error]: \(error)")
        }

        isSearching = false
    }

    // MARK: - Private

    // nonisolated：脱离 @MainActor，使 TaskGroup 中的搜索任务真正并发执行
    nonisolated private func searchInSource(_ query: String, source: BookSource) async -> [SearchResult] {
        guard let template = source.searchUrl else { return [] }

        // 解析搜索 URL 模板 — 支持 GET/POST 及 {{key}}、{{page}} 变量
        let parsed = AnalyzeUrl.parse(template, variables: ["key": query, "page": "1"])
        guard !parsed.url.isEmpty else { return [] }

        do {
            var context = AnalyzeContext(source: source, baseUrl: parsed.url)

            // Merge per-request headers from AnalyzeUrl with source headers
            var reqHeaders = parsed.headers
            source.headerDictionary.forEach { reqHeaders[$0.key] = $0.value }

            let html: String
            let finalUrl: String

            if parsed.method == "POST", let body = parsed.body {
                html = try await network.requestPost(parsed.url, body: body,
                                                     source: source, headers: Alamofire.HTTPHeaders(reqHeaders))
                finalUrl = parsed.url
            } else {
                // Use requestWithFinalUrl to detect redirects for bookUrlPattern (ISSUE-020)
                let result = try await network.requestWithFinalUrl(parsed.url,
                                                                   headers: Alamofire.HTTPHeaders(reqHeaders),
                                                                   source: source)
                html = result.body
                finalUrl = result.finalUrl
            }
            context.result = html

            // ISSUE-020: If final URL matches bookUrlPattern, parse as BookInfo directly
            if let pattern = source.bookUrlPattern, !pattern.isEmpty,
               let regex = try? NSRegularExpression(pattern: pattern),
               regex.firstMatch(in: finalUrl, range: NSRange(finalUrl.startIndex..., in: finalUrl)) != nil {
                return parseAsBookInfo(html: html, bookUrl: finalUrl, parsedUrl: parsed.url,
                                      source: source, context: context)
            }

            guard let listRule = source.ruleSearchList, !listRule.isEmpty else { return [] }
            let items = ruleExecutor.executeList(listRule, in: &context)

            return items.compactMap { item -> SearchResult? in
                var ctx = context
                ctx.result = item

                let name    = ruleExecutor.execute(source.ruleSearchName    ?? "", in: &ctx) ?? ""
                let author  = ruleExecutor.execute(source.ruleSearchAuthor  ?? "", in: &ctx) ?? ""
                let bookUrl = ruleExecutor.execute(source.ruleSearchNoteUrl ?? "", in: &ctx) ?? ""
                guard !name.isEmpty, !bookUrl.isEmpty else { return nil }

                let coverUrl = ruleExecutor.execute(source.ruleSearchCoverUrl ?? "", in: &ctx)
                let kind     = ruleExecutor.execute(source.ruleSearchKind    ?? "", in: &ctx)

                let absBookUrl = resolveUrl(bookUrl, base: parsed.url)
                let absCover   = coverUrl.map { resolveUrl($0, base: parsed.url) }

                return SearchResult(
                    name: name, author: author, bookUrl: absBookUrl,
                    kind: kind, intro: nil, coverUrl: absCover,
                    origin: source.bookSourceUrl, originName: source.bookSourceName
                )
            }
        } catch {
            print("⚠️ [\(source.bookSourceName)]: \(error.localizedDescription)")
            return []
        }
    }

    nonisolated private func resolveUrl(_ url: String, base: String) -> String {
        if url.hasPrefix("http") { return url }
        guard let baseURL = URL(string: base),
              let resolved = URL(string: url, relativeTo: baseURL) else { return url }
        return resolved.absoluteString
    }

    /// ISSUE-020: Parse a book detail page as a SearchResult when finalUrl matches bookUrlPattern.
    /// Mirrors Android BookList.analyzeBookList() → BookInfo path when bookUrlPattern matches.
    nonisolated private func parseAsBookInfo(html: String, bookUrl: String, parsedUrl: String,
                                              source: BookSource, context: AnalyzeContext) -> [SearchResult] {
        var ctx = context
        ctx.result = html
        ctx.baseUrl = bookUrl

        let name    = ruleExecutor.execute(source.ruleBookName    ?? "", in: &ctx) ?? ""
        let author  = ruleExecutor.execute(source.ruleBookAuthor  ?? "", in: &ctx) ?? ""
        guard !name.isEmpty else { return [] }

        let coverRaw  = ruleExecutor.execute(source.ruleBookCoverUrl  ?? "", in: &ctx)
        let kind      = ruleExecutor.execute(source.ruleBookKind      ?? "", in: &ctx)
        let intro     = ruleExecutor.execute(source.ruleBookIntro     ?? "", in: &ctx)
        let absCover  = coverRaw.map { resolveUrl($0, base: bookUrl) }

        return [SearchResult(
            name: name, author: author, bookUrl: bookUrl,
            kind: kind, intro: intro, coverUrl: absCover,
            origin: source.bookSourceUrl, originName: source.bookSourceName
        )]
    }
}

/// URL template parser — mirrors Android AnalyzeUrl logic.
///
/// Supports:
///   • {{key}} / {{page}} variable substitution (with noEncode() variant)
///   • {1,2,3} page-based URL switching (Android page pattern)
///   • URL option JSON:  http://...url, {"method":"POST","body":"...","headers":{...}}
///   • @POST@ separator
///   • charset / headers / body from option JSON
struct AnalyzeUrl {
    let url: String
    let body: String?
    let headers: [String: String]
    let method: String  // "GET" or "POST"

    init(url: String, body: String? = nil, headers: [String: String] = [:], method: String = "GET") {
        self.url = url
        self.body = body
        self.headers = headers
        self.method = method
    }

    static func parse(_ template: String, variables: [String: String] = [:]) -> AnalyzeUrl {
        var tmpl = template.trimmingCharacters(in: .whitespacesAndNewlines)

        // 1. Replace {{varName}} / {{page}} placeholders
        for (key, value) in variables {
            let encoded = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
            tmpl = tmpl.replacingOccurrences(of: "{{\(key)}}", with: encoded)
            tmpl = tmpl.replacingOccurrences(of: "{{\(key), noEncode()}}", with: value)
            tmpl = tmpl.replacingOccurrences(of: "{{\(key),noEncode()}}", with: value)
        }
        // 清除所有未被替换的 {{...}} 占位符（含 { } 的 URL 会被 URLSession 拒绝 → Unsupported URL）
        if let re = try? NSRegularExpression(pattern: #"\{\{[^}]*\}\}"#) {
            let ns = tmpl as NSString
            tmpl = re.stringByReplacingMatches(in: tmpl, range: NSRange(location: 0, length: ns.length), withTemplate: "")
        }

        // 2. {1,2,3} page-switching pattern: p1→choice1, p2→choice2, ...
        let page = Int(variables["page"] ?? "1") ?? 1
        if let pagePattern = try? NSRegularExpression(pattern: #"\{([^{}]+(?:,[^{}]+)+)\}"#) {
            let ns = tmpl as NSString
            let matches = pagePattern.matches(in: tmpl, range: NSRange(location: 0, length: ns.length))
            for match in matches.reversed() {
                guard let r = Range(match.range, in: tmpl),
                      let inner = Range(match.range(at: 1), in: tmpl) else { continue }
                let choices = tmpl[inner].components(separatedBy: ",")
                let idx = min(page - 1, choices.count - 1)
                tmpl.replaceSubrange(r, with: choices[idx].trimmingCharacters(in: .whitespaces))
            }
        }

        // 3. @POST@ separator
        if tmpl.contains("@POST@") {
            let parts = tmpl.components(separatedBy: "@POST@")
            if parts.count >= 2 {
                return AnalyzeUrl(url: parts[0].trimmed, body: parts[1].trimmed,
                                  headers: [:], method: "POST")
            }
        }

        // 4. URL option JSON:  url, {"method":...,"body":...,"headers":...}
        //    Android: the first , after the URL splits url from option JSON
        if let commaIdx = findOptionComma(in: tmpl) {
            let urlPart  = String(tmpl[..<commaIdx]).trimmed
            let optPart  = String(tmpl[tmpl.index(after: commaIdx)...]).trimmed

            if urlPart.lowercased().hasPrefix("http") {
                if optPart.hasPrefix("{") {
                    // Try to parse as URL option JSON
                    if let opt = parseOptionJSON(optPart) {
                        return AnalyzeUrl(url: urlPart,
                                          body: opt.body,
                                          headers: opt.headers,
                                          method: opt.method)
                    }
                    // Plain POST body
                    return AnalyzeUrl(url: urlPart, body: optPart, headers: [:], method: "POST")
                }
            }
        }

        return AnalyzeUrl(url: tmpl, body: nil, headers: [:], method: "GET")
    }

    // Find the first comma that is NOT inside a {{ }} or < > or [ ] block
    private static func findOptionComma(in s: String) -> String.Index? {
        var depth = 0
        var i = s.startIndex
        while i < s.endIndex {
            let ch = s[i]
            if ch == "{" || ch == "[" || ch == "<" { depth += 1 }
            else if ch == "}" || ch == "]" || ch == ">" { depth = max(0, depth - 1) }
            else if ch == "," && depth == 0 { return i }
            i = s.index(after: i)
        }
        return nil
    }

    private struct UrlOption {
        var method: String = "GET"
        var body: String? = nil
        var headers: [String: String] = [:]
    }

    private static func parseOptionJSON(_ json: String) -> UrlOption? {
        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        var opt = UrlOption()
        if let m = dict["method"] as? String { opt.method = m.uppercased() }
        if let b = dict["body"] {
            if let bs = b as? String { opt.body = bs }
            else if let bd = try? JSONSerialization.data(withJSONObject: b),
                    let bs = String(data: bd, encoding: .utf8) { opt.body = bs }
        }
        if let h = dict["headers"] as? [String: Any] {
            opt.headers = h.compactMapValues { "\($0)" }
        }
        // charset field (used to set request encoding — noted but not applied here)
        return opt
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
