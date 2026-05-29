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
        case .parseSearchFields: return "解析搜索书目字段"
        }
    }
}

// MARK: - Single step result
struct DeepCheckStepResult: Identifiable, Equatable {
    var id: DeepCheckStepKind { kind }
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
        // All skipped with no passed/failed → Step 1 failed and cascaded; treat as failed
        if all.allSatisfy({ $0.status == .skipped }) { return .failed }
        // Still have pending steps (e.g. search pipeline not yet started) → still in progress
        if all.contains(where: { $0.status == .pending }) { return .running }
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
