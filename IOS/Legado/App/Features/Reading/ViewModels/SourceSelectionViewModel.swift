// IOS/Legado/App/Features/Reading/ViewModels/SourceSelectionViewModel.swift
import Foundation

enum SourceSearchStatus {
    case searching
    case found(chapterAvailable: Bool)
    case notFound
    case timeout
}

struct SourceSearchResult: Identifiable {
    let id: String          // bookSourceUrl
    let sourceName: String
    let sourceUrl: String
    var status: SourceSearchStatus
}

@MainActor
final class SourceSelectionViewModel: ObservableObject {
    @Published var results: [SourceSearchResult] = []
    @Published var isSearching: Bool = false

    private var searchTasks: [Task<Void, Never>] = []

    func startSearch(bookName: String, currentChapterIndex: Int) async {
        results = []
        isSearching = true
        searchTasks.forEach { $0.cancel() }
        searchTasks = []

        let allSources = (try? await DatabaseManager.shared.getAllBookSources()) ?? []
        let enabled = allSources.filter { $0.enabled }

        for source in enabled {
            let task = Task { @MainActor in
                let placeholder = SourceSearchResult(
                    id: source.bookSourceUrl,
                    sourceName: source.bookSourceName,
                    sourceUrl: source.bookSourceUrl,
                    status: .searching
                )
                results.append(placeholder)

                let searchResult = await withTaskGroup(of: SourceSearchStatus.self) { group in
                    group.addTask {
                        await self.searchSource(source, bookName: bookName, chapterIndex: currentChapterIndex)
                    }
                    group.addTask {
                        try? await Task.sleep(nanoseconds: 10_000_000_000)
                        return .timeout
                    }
                    let first = await group.next() ?? .timeout
                    group.cancelAll()
                    return first
                }

                if let idx = results.firstIndex(where: { $0.id == source.bookSourceUrl }) {
                    results[idx].status = searchResult
                }
            }
            searchTasks.append(task)
        }

        for task in searchTasks { await task.value }
        isSearching = false
    }

    func cancelAll() {
        searchTasks.forEach { $0.cancel() }
        searchTasks = []
        isSearching = false
    }

    private func searchSource(_ source: BookSource, bookName: String, chapterIndex: Int) async -> SourceSearchStatus {
        guard let searchUrl = source.searchUrl, !searchUrl.isEmpty else { return .notFound }

        var ctx = AnalyzeContext(source: source, baseUrl: source.bookSourceUrl)
        let parsed = AnalyzeUrl.parse(searchUrl, variables: ["key": bookName, "page": "1"], context: ctx)
        let url = parsed.url.hasPrefix("http") ? parsed.url : source.bookSourceUrl + parsed.url
        var headers = parsed.headers
        source.headerDictionary.forEach { headers[$0.key] = $0.value }

        guard !url.isEmpty,
              let body = NetworkManager.shared.requestSync(url, headers: headers) else {
            return .notFound
        }
        ctx.result = body

        let items = RuleExecutor.shared.executeList(source.ruleSearchList ?? "", in: &ctx)
        guard !items.isEmpty else { return .notFound }

        var itemCtx = AnalyzeContext(source: source, baseUrl: url)
        itemCtx.result = items[0]
        let foundName = RuleExecutor.shared.execute(source.ruleSearchName ?? "", in: &itemCtx) ?? ""
        guard !foundName.isEmpty, isSimilar(foundName, bookName) else { return .notFound }

        let noteUrlRaw = RuleExecutor.shared.execute(source.ruleSearchNoteUrl ?? "", in: &itemCtx) ?? ""
        let noteUrl = noteUrlRaw.hasPrefix("http") ? noteUrlRaw : source.bookSourceUrl + noteUrlRaw
        guard !noteUrl.isEmpty else { return .found(chapterAvailable: false) }

        let chapterAvailable = await checkChapterAvailability(source: source, bookUrl: noteUrl, chapterIndex: chapterIndex)
        return .found(chapterAvailable: chapterAvailable)
    }

    private func checkChapterAvailability(source: BookSource, bookUrl: String, chapterIndex: Int) async -> Bool {
        var ctx = AnalyzeContext(source: source, baseUrl: bookUrl)
        let tocUrlRaw = RuleExecutor.shared.execute(source.ruleTocUrl ?? "", in: &ctx) ?? bookUrl
        let tocUrl = tocUrlRaw.hasPrefix("http") ? tocUrlRaw : (source.bookSourceUrl + tocUrlRaw)
        let fetchUrl = tocUrl.isEmpty ? bookUrl : tocUrl
        guard let tocBody = NetworkManager.shared.requestSync(fetchUrl) else { return false }
        ctx.result = tocBody
        let chapters = RuleExecutor.shared.executeList(source.ruleTocList ?? "", in: &ctx)
        return chapters.count > chapterIndex
    }

    private func isSimilar(_ a: String, _ b: String) -> Bool {
        let na = a.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let nb = b.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return na.contains(nb) || nb.contains(na)
    }

    var sortedResults: [SourceSearchResult] {
        results.sorted { score($0) > score($1) }
    }

    private func score(_ r: SourceSearchResult) -> Int {
        switch r.status {
        case .found(let avail): return avail ? 2 : 1
        case .searching: return 0
        case .notFound, .timeout: return -1
        }
    }
}
