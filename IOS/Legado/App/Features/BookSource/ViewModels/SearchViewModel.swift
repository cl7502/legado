import SwiftUI
import Combine

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

    private func searchInSource(_ query: String, source: BookSource) async -> [SearchResult] {
        guard let template = source.searchUrl else { return [] }

        // 解析搜索 URL 模板 — 支持 GET/POST 及 {{key}}、{{page}} 变量
        let parsed = AnalyzeUrl.parse(template, variables: ["key": query, "page": "1"])
        guard !parsed.url.isEmpty else { return [] }

        do {
            var context = AnalyzeContext(source: source, baseUrl: parsed.url)

            let html: String
            if let body = parsed.body {
                html = try await network.requestPost(parsed.url, body: body, source: source)
            } else {
                html = try await network.request(parsed.url, source: source)
            }
            context.result = html

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

    private func resolveUrl(_ url: String, base: String) -> String {
        if url.hasPrefix("http") { return url }
        guard let baseURL = URL(string: base),
              let resolved = URL(string: url, relativeTo: baseURL) else { return url }
        return resolved.absoluteString
    }
}

/// URL 模板解析器 — 支持 {{key}}、{{page}}、{{variable.*}} 及 POST body
struct AnalyzeUrl {
    let url: String
    let body: String?      // 非 nil 则用 POST
    let headers: [String: String]

    static func parse(_ template: String, variables: [String: String] = [:]) -> AnalyzeUrl {
        var tmpl = template.trimmingCharacters(in: .whitespacesAndNewlines)

        // 替换所有 {{varName}} 占位符（先替换再检测 POST 格式）
        for (key, value) in variables {
            let encoded = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
            tmpl = tmpl.replacingOccurrences(of: "{{\(key)}}", with: encoded)
            tmpl = tmpl.replacingOccurrences(of: "{{\(key), noEncode()}}", with: value)
            tmpl = tmpl.replacingOccurrences(of: "{{\(key),noEncode()}}", with: value)
        }

        // @POST@ 分隔符格式：http://... @POST@ {body}
        if tmpl.contains("@POST@") {
            let parts = tmpl.components(separatedBy: "@POST@")
            if parts.count >= 2 {
                return AnalyzeUrl(url: parts[0].trimmingCharacters(in: .whitespaces),
                                  body: parts[1].trimmingCharacters(in: .whitespaces),
                                  headers: [:])
            }
        }

        // 逗号分隔格式：http://..., {body}
        if let commaIdx = tmpl.firstIndex(of: ",") {
            let urlPart  = String(tmpl[..<commaIdx]).trimmingCharacters(in: .whitespaces)
            let bodyPart = String(tmpl[tmpl.index(after: commaIdx)...]).trimmingCharacters(in: .whitespaces)
            if urlPart.lowercased().hasPrefix("http"), bodyPart.hasPrefix("{") {
                return AnalyzeUrl(url: urlPart, body: bodyPart, headers: [:])
            }
        }

        return AnalyzeUrl(url: tmpl, body: nil, headers: [:])
    }
}
