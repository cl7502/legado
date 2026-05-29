// IOS/Legado/App/Features/BookSource/Views/DeepCheckView.swift
import SwiftUI

// MARK: - Main View

struct DeepCheckView: View {
    @ObservedObject var vm: DeepCheckViewModel
    let sources: [BookSource]
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
                Button(role: .destructive) {
                    Task { await vm.disableFailedSources() }
                } label: {
                    Label("禁用失败书源", systemImage: "eye.slash")
                        .font(.subheadline)
                }
                .disabled(vm.failedCount + vm.partialCount == 0)

                Button(role: .destructive) {
                    Task { await vm.deleteFailedSources() }
                } label: {
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
            // Header row
            HStack {
                sourceStatusIcon(for: entry.result.overallStatus)
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
                pipelineSection(title: "发现链路", steps: result.exploreSteps,
                                expanded: $exploreExpanded)
            }

            // Search steps
            if !result.searchSteps.isEmpty {
                pipelineSection(title: "搜索链路", steps: result.searchSteps,
                                expanded: $searchExpanded)
            }

            // Continue search button (single-source mode only)
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
                    DeepCheckStepRow(step: step).padding(.leading, 36)
                }
            }
        }
    }

    @ViewBuilder
    private func sourceStatusIcon(for status: SourceCheckStatus) -> some View {
        switch status {
        case .passed:
            Image(systemName: "checkmark.circle.fill").foregroundColor(.green).font(.title3)
        case .partial:
            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange).font(.title3)
        case .failed:
            Image(systemName: "xmark.circle.fill").foregroundColor(.red).font(.title3)
        case .skipped:
            Image(systemName: "minus.circle").foregroundColor(.secondary).font(.title3)
        case .running, .awaitingSearch:
            ProgressView().scaleEffect(0.8)
        case .pending:
            Image(systemName: "circle").foregroundColor(.secondary).font(.title3)
        }
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
