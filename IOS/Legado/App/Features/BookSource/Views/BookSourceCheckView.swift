import SwiftUI
import Foundation

// MARK: - 检测范围

enum CheckScope: String, CaseIterable, Identifiable {
    case untested   = "检测未测书源"
    case failedToo  = "检测未测+失败书源"
    case all        = "检测全部书源"
    var id: String { rawValue }
}

// MARK: - 检测后的处理策略

enum InvalidAction: String, CaseIterable {
    case disable = "禁用"
    case delete  = "删除"
}

enum SlowAction: String, CaseIterable {
    case keep    = "保持启用"
    case disable = "禁用"
}

// MARK: - 慢速阈值（ms）

private let slowThreshold: Int64 = 3000   // >3s 视为慢速
private let timeoutSeconds: Double = 8.0  // 8s 超时

// MARK: - 检测 ViewModel

@MainActor
class BookSourceCheckViewModel: ObservableObject {
    @Published var checkedCount  = 0
    @Published var totalCount    = 0
    @Published var isRunning     = false
    @Published var results: [CheckResult] = []  // 实时追加

    // 配置
    var invalidAction: InvalidAction = .disable
    var slowAction: SlowAction       = .keep

    private let db = DatabaseManager.shared
    private var checkTask: Task<Void, Never>?

    struct CheckResult: Identifiable {
        let id = UUID()
        let sourceName: String
        let sourceUrl: String
        let state: Int        // 1=正常 2=慢速 3=失败
        let respondTime: Int64
    }

    func start(scope: CheckScope) {
        checkTask?.cancel()
        checkedCount = 0
        results = []
        isRunning = true

        checkTask = Task {
            do {
                var sources = try await db.getAllBookSources()
                sources = filter(sources, scope: scope)
                totalCount = sources.count

                // 并发限制：最多 5 个并发
                let semaphore = AsyncSemaphore(5)
                await withTaskGroup(of: Void.self) { group in
                    for source in sources {
                        group.addTask { [weak self] in
                            await semaphore.wait()
                            await self?.checkOne(source)
                            await semaphore.signal()
                        }
                    }
                }
            } catch { }
            isRunning = false
        }
    }

    func cancel() {
        checkTask?.cancel()
        isRunning = false
    }

    // MARK: - 单个书源检测

    private func checkOne(_ source: BookSource) async {
        guard !Task.isCancelled else { return }

        let start = Date()
        var updated = source
        let testUrl = buildTestUrl(source)

        do {
            let deadline = Date().addingTimeInterval(timeoutSeconds)
            _ = try await withThrowingTaskGroup(of: String.self) { group in
                group.addTask {
                    let (_, resp) = try await URLSession.shared.data(from: URL(string: testUrl)!)
                    _ = resp
                    return "ok"
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                    throw CancellationError()
                }
                guard let first = try await group.next() else { throw CancellationError() }
                group.cancelAll()
                return first
            }

            let elapsed = Int64(Date().timeIntervalSince(start) * 1000)
            updated.respondTime = elapsed
            updated.checkState  = elapsed > slowThreshold ? 2 : 1
            // 慢速处理
            if updated.checkState == 2, slowAction == .disable {
                updated.enabled = false
            }
            _ = deadline
        } catch {
            updated.respondTime  = -1
            updated.checkState   = 3
            // lastCheckTime 在 saveCheckResult 内部用当前时间写入

            // 失败处理
            switch invalidAction {
            case .disable: updated.enabled = false
            case .delete:  break  // 检测完后统一删除
            }
        }

        // 持久化
        try? await db.saveCheckResult(updated)

        // 主线程更新 UI
        await MainActor.run { [weak self, updated] in
            guard let self else { return }
            self.checkedCount += 1
            self.results.insert(
                CheckResult(
                    sourceName: updated.bookSourceName,
                    sourceUrl: updated.bookSourceUrl,
                    state: updated.checkState,
                    respondTime: updated.respondTime
                ),
                at: 0
            )
        }
    }

    /// 检测完成后批量删除失败书源（仅当 invalidAction == .delete）
    func applyDeletions() async {
        guard invalidAction == .delete else { return }
        let failed = results.filter { $0.state == 3 }.map { $0.sourceUrl }
        guard !failed.isEmpty else { return }
        do {
            let all = try await db.getAllBookSources()
            for source in all where failed.contains(source.bookSourceUrl) {
                try? await db.deleteBookSource(source)
            }
        } catch { }
    }

    // MARK: - 辅助

    private func filter(_ sources: [BookSource], scope: CheckScope) -> [BookSource] {
        switch scope {
        case .untested:  return sources.filter { $0.checkState == 0 }
        case .failedToo: return sources.filter { $0.checkState == 0 || $0.checkState == 3 }
        case .all:       return sources
        }
    }

    private func buildTestUrl(_ source: BookSource) -> String {
        // 优先用搜索 URL，如果没有则用书源根 URL
        if let search = source.searchUrl, !search.isEmpty {
            // 取出第一个 URL（可能有 &&、||）
            let base = search.components(separatedBy: CharacterSet(charactersIn: ",&|")).first ?? search
            let clean = base.trimmingCharacters(in: .whitespaces)
            // 替换 key 占位符
            let url = clean.replacingOccurrences(of: "{{key}}", with: "test")
                           .replacingOccurrences(of: "{key}", with: "test")
            if url.hasPrefix("http") { return url }
        }
        return source.bookSourceUrl
    }
}

// 简单异步信号量，限制并发数
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

// MARK: - 检测配置 Sheet

struct BookSourceCheckConfigSheet: View {
    let scope: CheckScope
    let onStart: (InvalidAction, SlowAction) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var invalidAction: InvalidAction = .disable
    @State private var slowAction: SlowAction = .keep

    var body: some View {
        NavigationView {
            Form {
                Section {
                    Text(scope.rawValue)
                        .font(.headline)
                        .foregroundColor(.primary)
                } header: { Text("检测范围") }

                Section {
                    Picker("无效书源处理", selection: $invalidAction) {
                        ForEach(InvalidAction.allCases, id: \.self) {
                            Text($0.rawValue).tag($0)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: { Text("无效书源（连接失败）") }
                  footer: { Text("检测完成后对失败书源执行此操作") }

                Section {
                    Picker("慢速书源处理", selection: $slowAction) {
                        ForEach(SlowAction.allCases, id: \.self) {
                            Text($0.rawValue).tag($0)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: { Text("慢速书源（响应 >3 秒）") }
                  footer: { Text("响应时间超过 3 秒的书源视为慢速") }
            }
            .navigationTitle("检测配置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("开始检测") {
                        dismiss()
                        onStart(invalidAction, slowAction)
                    }
                    .font(.body.bold())
                }
            }
        }
    }
}

// MARK: - 检测进度 Sheet

struct BookSourceCheckProgressSheet: View {
    @ObservedObject var vm: BookSourceCheckViewModel
    let onDone: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // 顶部进度
                VStack(spacing: 8) {
                    if vm.isRunning {
                        ProgressView(value: Double(vm.checkedCount),
                                     total: Double(max(vm.totalCount, 1)))
                            .progressViewStyle(.linear)
                            .padding(.horizontal)
                    }
                    Text(vm.isRunning
                         ? "正在检测 \(vm.checkedCount) / \(vm.totalCount)"
                         : "检测完成  共 \(vm.totalCount) 个书源")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    // 结果统计
                    if !vm.results.isEmpty {
                        HStack(spacing: 20) {
                            statBadge(vm.results.filter { $0.state == 1 }.count,
                                      label: "正常", color: .green)
                            statBadge(vm.results.filter { $0.state == 2 }.count,
                                      label: "慢速", color: .orange)
                            statBadge(vm.results.filter { $0.state == 3 }.count,
                                      label: "失败", color: .red)
                        }
                        .font(.caption)
                    }
                }
                .padding(.vertical, 12)
                .background(Color(.secondarySystemBackground))

                // 结果列表
                List(vm.results) { result in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(result.sourceName)
                                .font(.subheadline)
                                .lineLimit(1)
                            Text(result.sourceUrl)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        speedBadge(result)
                    }
                    .padding(.vertical, 2)
                }
                .listStyle(.plain)
            }
            .navigationTitle("检测书源")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if vm.isRunning {
                        Button("停止") { vm.cancel() }
                            .foregroundColor(.red)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !vm.isRunning {
                        Button("完成") {
                            Task {
                                await vm.applyDeletions()
                                dismiss()
                                onDone()
                            }
                        }
                        .font(.body.bold())
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func speedBadge(_ r: BookSourceCheckViewModel.CheckResult) -> some View {
        switch r.state {
        case 1:
            Text("\(r.respondTime)ms")
                .font(.caption2)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color.green.opacity(0.15))
                .foregroundColor(.green)
                .cornerRadius(4)
        case 2:
            Text("\(r.respondTime)ms")
                .font(.caption2)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color.orange.opacity(0.15))
                .foregroundColor(.orange)
                .cornerRadius(4)
        default:
            Text("失败")
                .font(.caption2)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color.red.opacity(0.15))
                .foregroundColor(.red)
                .cornerRadius(4)
        }
    }

    private func statBadge(_ count: Int, label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text("\(label) \(count)")
        }
    }
}
