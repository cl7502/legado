// IOS/Legado/App/Features/BookSource/ViewModels/DeepCheckViewModel.swift
import Foundation
import Combine

class DeepCheckViewModel: ObservableObject {

    // MARK: - State
    @Published var entries:    [DeepCheckEntry] = []
    @Published var isRunning   = false
    @Published var totalCount  = 0
    @Published var doneCount   = 0

    // MARK: - Batch config (not used in single-source mode)
    @Published var alsoRunSearch = false    // only affects sources that have exploreUrl
    @Published var concurrency   = 3        // sliding-window concurrency, 1-5
    @Published var searchKeyword = "小说"   // override in batch config sheet

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
        await MainActor.run {
            entries = []
            totalCount = sources.count
            doneCount = 0
            isRunning = true
        }

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
        guard let idx = await MainActor.run(body: { entries.firstIndex(where: { $0.id == sourceUrl }) }),
              await MainActor.run(body: { entries[idx].result.hasSearch }) else { return }
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
        let failed = await MainActor.run {
            entries.filter { $0.result.overallStatus == .failed || $0.result.overallStatus == .partial }
                   .map(\.result.sourceUrl)
        }
        guard !failed.isEmpty else { return }
        let all = (try? await db.getAllBookSources()) ?? []
        for var src in all where failed.contains(src.bookSourceUrl) {
            src.enabled = false
            try? await db.saveCheckResult(src)
        }
    }

    func deleteFailedSources() async {
        let failed = await MainActor.run {
            entries.filter { $0.result.overallStatus == .failed || $0.result.overallStatus == .partial }
                   .map(\.result.sourceUrl)
        }
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

        let willRunSearch = !hasExplore || alsoRunSearch

        // Create entry with pre-initialised pending steps
        var result = makeResult(source: source, hasExplore: hasExplore, hasSearch: hasSearch)
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
            // Write checkState after explore if search won't also run
            if !willRunSearch || !hasSearch {
                await writeCheckStateFromSteps(sourceUrl: source.bookSourceUrl)
            }
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
        let entry = await MainActor.run { entries.first(where: { $0.id == sourceUrl }) }
        guard let entry else { return }
        if entry.execStatus == .skipped { return }
        let all = (try? await db.getAllBookSources()) ?? []
        guard var src = all.first(where: { $0.bookSourceUrl == sourceUrl }) else { return }
        let status = entry.result.overallStatus
        src.checkState = (status == .passed) ? 1 : 3
        try? await db.saveCheckResult(src)
    }

    private func writeCheckStateFromSteps(sourceUrl: String) async {
        let entry = await MainActor.run { entries.first(where: { $0.id == sourceUrl }) }
        guard let entry, entry.execStatus != .skipped else { return }
        let all = (try? await db.getAllBookSources()) ?? []
        guard var src = all.first(where: { $0.bookSourceUrl == sourceUrl }) else { return }
        let exploreSteps = entry.result.exploreSteps
        let passed = !exploreSteps.isEmpty
                  && exploreSteps.allSatisfy { $0.status == .passed || $0.status == .skipped }
                  && exploreSteps.contains { $0.status == .passed }
        src.checkState = passed ? 1 : 3
        try? await db.saveCheckResult(src)
    }

    private func getSource(url: String) async -> BookSource? {
        let all = try? await db.getAllBookSources()
        return all?.first { $0.bookSourceUrl == url }
    }
}
