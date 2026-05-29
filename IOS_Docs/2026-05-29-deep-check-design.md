# 深度检查功能设计规格

**日期**：2026-05-29  
**状态**：待实现  
**作者**：Alina + Claude

---

## 1. 背景与目标

现有"检查书源"功能（三个菜单项）仅做 HTTP 连通性测试：能否建立连接、响应时间是否在阈值内。这无法检测书源规则是否正确——一个连通正常的书源可能因规则配置错误而完全无法使用。

**目标**：新增"深度检查"能力，验证书源的完整解析链路（分类获取→书单解析→字段提取→详情页可访问），并将此能力同时集成到批量检查菜单和单个书源三点菜单。

---

## 2. 功能范围

### 2.1 两处入口

**入口 A：书源列表右上角"检查书源"菜单**  
现有三项不变，新增第四项：

```
检测未测书源
检测未测+失败书源
检测全部书源
──────────────
深度检查...        ← 新增，弹出批量配置 Sheet
```

**入口 B：单个书源三点菜单**  
在"调试发现规则"之后新增一项：

```
调试发现规则       ← 不变（ExploreDebugView，交互式调试）
深度检查           ← 新增（DeepCheckView，自动化验证）
```

### 2.2 "调试发现规则"保持不变

ExploreDebugView 是**交互式**逐步调试工具，含手动修复建议，继续独立存在。深度检查是**自动化**验证工具，两者互补，不合并。

---

## 3. 检查管线定义

### 3.1 探索管线（5 步）——有 `exploreUrl` 的书源

| 步骤 | 标识 | 操作 | 成功判据 | detailPreview 内容 |
|---|---|---|---|---|
| 1 | `parseExploreUrl` | 解析 exploreUrl → 分类名+URL 列表 | ≥1 个分类 | "玄幻 / 都市 / 修仙 / ..." |
| 2 | `fetchCategoryPage` | HTTP GET 第一个分类 URL（page=1） | 状态 200 | 响应体前 300 字 |
| 3 | `parseBookList` | 执行 ruleExploreList → 书单 | ≥1 条 | "15 条书目" |
| 4 | `parseBookFields` | 解析第一本书 name/author/noteUrl | name 非空 | "《斗破苍穹》天蚕土豆" |
| 5 | `verifyDetailPage` | HTTP GET noteUrl（已 resolveUrl） | 状态 200 | 响应体前 300 字 |

### 3.2 搜索管线（3 步）——无 `exploreUrl` 的书源，或用户主动触发

| 步骤 | 标识 | 操作 | 成功判据 | detailPreview 内容 |
|---|---|---|---|---|
| 1 | `fetchSearchPage` | 构建搜索 URL + HTTP GET | 状态 200 | 响应体前 300 字 |
| 2 | `parseSearchList` | 执行 ruleSearchList → 书单 | ≥1 条 | "12 条搜索结果" |
| 3 | `parseSearchFields` | 解析第一本书 name/noteUrl | name 非空 | "《斗破苍穹》天蚕土豆" |

**默认搜索词**：`"小说"`（通用，批量配置弹窗可覆盖）

### 3.3 管线选择规则

| 书源类型 | 默认行为 |
|---|---|
| 有 `exploreUrl` | 自动跑探索管线；完成后可触发搜索管线 |
| 无 `exploreUrl`，有 `searchUrl` | 自动跑搜索管线 |
| 两者皆无 | 跳过，标注原因"此书源无搜索/发现规则" |

**批量模式**：配置弹窗提供"探索通过后自动跑搜索"开关（仅对有 `exploreUrl` 的书源有额外效果；无 `exploreUrl` 的书源始终跑搜索）。

**单源模式**：探索完成后（无论成功失败），若书源有 `searchUrl`，结果视图底部出现"继续跑搜索链路"按钮，用户主动触发。

### 3.4 失败级联规则

步骤 N 失败，或其必要输出（如 noteUrl）为空时，后续步骤自动置 `.skipped`：

```
parseExploreUrl 失败/分类为空    → 后续 4 步 skipped
fetchCategoryPage 失败           → 后续 3 步 skipped
parseBookList 失败/条数为0       → 后续 2 步 skipped
ruleExploreList 未配置           → parseBookList failed("ruleExploreList 未配置")，后续 2 步 skipped
parseBookFields 失败/name为空    → verifyDetailPage skipped
noteUrl 为空/无效                → verifyDetailPage skipped("无 noteUrl")
─── 探索失败不影响搜索管线 ───
fetchSearchPage 失败             → 后续 2 步 skipped
parseSearchList 失败/条数为0     → parseSearchFields skipped
ruleSearchList 未配置            → parseSearchList failed("ruleSearchList 未配置")，skipped
```

---

## 4. 数据模型

### 4.1 步骤状态与书源级状态（两套枚举）

```swift
// 步骤级
enum StepStatus { case pending, running, passed, failed, skipped }

// 书源级（区分 partial）
enum SourceCheckStatus {
    case pending          // 队列中
    case running          // 检查中
    case awaitingSearch   // 探索完成，搜索待触发（单源模式）
    case passed           // 全部已跑管线通过
    case partial          // 部分管线通过（橙色）
    case failed           // 全部已跑管线失败
    case skipped          // 无可用规则
}
```

### 4.2 核心数据结构

```swift
enum DeepCheckStepKind: Int, CaseIterable {
    case parseExploreUrl = 0, fetchCategoryPage, parseBookList,
         parseBookFields, verifyDetailPage          // 探索（0-4）
    case fetchSearchPage, parseSearchList, parseSearchFields  // 搜索（5-7）
    var pipeline: Pipeline { rawValue < 5 ? .explore : .search }
    var displayName: String { /* "解析分类 URL" 等 */ }
}

struct DeepCheckStepResult {
    let kind: DeepCheckStepKind
    var status: StepStatus
    var durationMs: Int
    var summary: String           // "15条" / "《斗破苍穹》天蚕土豆" / "HTTP 200"
    var detailPreview: String?    // HTTP步骤→响应前300字；解析步骤→字段摘要
    var errorMessage: String?
}

struct DeepCheckSourceResult: Identifiable {
    let id: String                // = sourceUrl
    let sourceName: String
    let sourceUrl: String
    let hasExplore: Bool          // exploreUrl 非空非空白
    let hasSearch: Bool           // searchUrl 非空
    var exploreSteps: [DeepCheckStepResult]   // [] 表示未跑
    var searchSteps:  [DeepCheckStepResult]   // [] 表示未跑
    var skippedReason: String?

    // 计算属性——不存储
    var overallStatus: SourceCheckStatus {
        if skippedReason != nil { return .skipped }
        let all = exploreSteps + searchSteps
        guard !all.isEmpty else { return .pending }
        if all.allSatisfy({ $0.status == .skipped }) { return .failed } // Step1失败→全skipped
        let hasFail = all.contains { $0.status == .failed }
        let hasPass = all.contains { $0.status == .passed }
        if hasFail && hasPass { return .partial }
        if hasFail            { return .failed  }
        if hasPass            { return .passed  }
        return .running
    }
}

struct DeepCheckEntry: Identifiable {
    let id: String
    var result: DeepCheckSourceResult
    var execStatus: SourceCheckStatus   // 与 overallStatus 同步
}
```

---

## 5. 服务层：DeepCheckPipeline

**位置**：`Core/Services/DeepCheckPipeline.swift`

```swift
struct DeepCheckPipeline {
    static let perSourceTimeoutSeconds: Double = 60

    // 约定：
    // - 每步触发 onStep 两次：开始时（.running）+ 完成时（最终状态）
    // - 所有错误内部捕获，不 throws
    // - 使用 NetworkManager.shared.request(source:) 保证书源请求头/Cookie/限速
    // - webView=true 的步骤自动走 HeadlessWebViewLoader
    // - noteUrl 相对路径用 resolveUrl() 补全后再请求
    // - 超过 perSourceTimeout：剩余步骤全部 .skipped

    static func runExplore(
        source: BookSource,
        onStep: @escaping (DeepCheckStepResult) -> Void
    ) async -> [DeepCheckStepResult]

    static func runSearch(
        source: BookSource,
        keyword: String = "小说",
        onStep: @escaping (DeepCheckStepResult) -> Void
    ) async -> [DeepCheckStepResult]
}
```

**依赖**：
- `ExploreUrlParser`（从 ExploreViewModel 提取，共享工具，位于 `Core/Services/`）
- `AnalyzeUrl.parse()` + `RuleExecutor.shared`
- `NetworkManager.shared` + `HeadlessWebViewLoader`
- `LegadoJSEngine`（通过 RuleExecutor 间接使用）

**AnalyzeContext 流转**：
- 初始：`baseUrl = source.bookSourceUrl`
- Step 2 后：`baseUrl = categoryUrl`，`result = responseBody`
- Step 3 后：`result = items[0]`（第一个书目的原始数据）
- Step 4 后：noteUrl 已解析，传入 Step 5

---

## 6. 视图层：DeepCheckViewModel + DeepCheckView

### 6.1 ViewModel

**位置**：`Features/BookSource/ViewModels/DeepCheckViewModel.swift`

```swift
@Observable class DeepCheckViewModel {
    var entries:    [DeepCheckEntry] = []
    var isRunning   = false
    var totalCount  = 0
    var doneCount   = 0

    // 批量配置（单源模式不使用）
    var alsoRunSearch = false    // 仅影响有 exploreUrl 的书源
    var concurrency   = 3        // 滑动窗口并发，1~5
    var searchKeyword = "小说"   // 批量配置弹窗可覆盖；单源模式固定此默认值

    // 批量入口——滑动窗口 TaskGroup（并发不超过 concurrency）
    func start(sources: [BookSource]) async

    // 单源入口：探索后用户点击"继续搜索"
    func runSearchFor(sourceUrl: String) async

    func cancel()

    // 完成后清理（结果视图底部按钮触发）
    func disableFailedSources() async
    func deleteFailedSources() async

    var summary: String { "✅\(passed)  🟠\(partial)  ❌\(failed)  ⏭\(skipped)" }
    
    // checkState 回写规则：每条管线完成时立即写库，不等另一条
    // passed→1, failed→3, 不修改→无规则或已取消
}
```

**并发实现（滑动窗口）**：
```swift
// 预填 concurrency 个任务，每完成一个补充下一个
var iter = sources.makeIterator()
await withTaskGroup(of: Void.self) { group in
    for _ in 0..<min(concurrency, sources.count) {
        if let s = iter.next() { group.addTask { await runOneSource(s) } }
    }
    for await _ in group {
        if let s = iter.next() { group.addTask { await runOneSource(s) } }
    }
}
```

### 6.2 取消行为

| 源状态 | 取消后处理 |
|---|---|
| 运行中 | Task.isCancelled 捕获，剩余步骤 `.skipped`（errorMessage: "已取消"），`execStatus → .done` |
| 队列中 | `execStatus → .done`，`skippedReason = "已取消"` |
| 已完成 | 不变 |
| checkState 回写 | 已取消的源**不**回写 checkState |

### 6.3 DeepCheckView UI 结构

**位置**：`Features/BookSource/Views/DeepCheckView.swift`

```
DeepCheckView
├── 顶部（批量模式）
│   ├── ProgressView（doneCount / totalCount）
│   └── 统计摘要（✅N 🟠N ❌N ⏭N）
│
├── 书源结果列表（DeepCheckSourceRow × N）
│   每行展开结构：
│   ┌─ 书源名 + SourceCheckStatus 图标 + 总耗时
│   │
│   ├─ [探索管线] 折叠/展开
│   │   ├─ Step 行：图标 + 步骤名 + 耗时 + summary
│   │   └─   └─ 展开：detailPreview（灰色等宽字体）
│   │
│   └─ [搜索管线] 折叠/展开（若已跑）
│       ├─ Step 行（同上）
│       └─ "继续跑搜索链路" 按钮（单源模式，execStatus=.awaitingSearch 时显示）
│
└── 底部（批量模式，完成后出现）
    ├── "禁用全部失败书源" 按钮
    └── "删除全部失败书源" 按钮
```

**颜色约定**：
- `passed` → 绿（SF Symbol: checkmark.circle.fill）
- `partial` → 橙（SF Symbol: exclamationmark.triangle.fill）
- `failed` → 红（SF Symbol: xmark.circle.fill）
- `skipped` → 灰（SF Symbol: minus.circle）
- `running` → 蓝（ProgressView 转圈）
- `pending` → 灰（SF Symbol: circle）

---

## 7. checkState 数据库回写规则

| 场景 | checkState 写入值 |
|---|---|
| 仅探索运行，探索全通过 | 1（正常） |
| 仅搜索运行，搜索全通过 | 1（正常） |
| 探索 + 搜索都运行，全通过 | 1（正常） |
| 探索通过，搜索失败 | 3（失败） |
| 探索失败，搜索通过 | 3（失败） |
| 探索通过，搜索未跑（alsoRunSearch=false） | 1（正常，未测搜索） |
| 任何已运行管线有失败 | 3（失败） |
| 无可用规则（skipped） | 不修改 |
| 用户取消 | 不修改 |

---

## 8. 批量配置 Sheet 内容

打开方式：点击"深度检查..."菜单项后弹出。

```
┌─ 深度检查配置 ──────────────────────────┐
│  检查范围         [全部] [仅未测] [未测+失败] │
│  搜索测试词       [小说         ]            │
│  探索后自动跑搜索  ○ 关                      │
│  并发数           [-] [3] [+]                │
│                  ─────────────────────────   │
│                        [开始深度检查]         │
└──────────────────────────────────────────┘
```

说明文案："探索后自动跑搜索"仅对有发现规则的书源生效；无发现规则的书源始终跑搜索链路。

---

## 9. 文件变更清单

### 新增文件
| 文件 | 说明 |
|---|---|
| `Core/Services/DeepCheckPipeline.swift` | 管线逻辑（无 UI 依赖） |
| `Core/Services/ExploreUrlParser.swift` | 从 ExploreViewModel 提取的分类解析工具 |
| `Features/BookSource/Models/DeepCheckModels.swift` | 数据类型定义 |
| `Features/BookSource/ViewModels/DeepCheckViewModel.swift` | 状态管理 |
| `Features/BookSource/Views/DeepCheckView.swift` | 主视图 + Row 组件 |
| `Features/BookSource/Views/DeepCheckConfigSheet.swift` | 批量配置弹窗 |

### 修改文件
| 文件 | 变更内容 |
|---|---|
| `BookSourceListView.swift` | 检查书源菜单新增"深度检查..."项 |
| `BookSourceListView.swift`（三点菜单部分）| 新增"深度检查"入口 |
| `ExploreViewModel.swift` / `ExploreView.swift` | 提取 `ExploreUrlParser` 工具，保持原有逻辑不变 |

---

## 10. 暂不实现（未来扩展）

- 深度检查结果持久化（当前仅内存）
- 正文解析验证（Step 5 之后的 TOC + 章节内容链路）
- 自定义搜索词（单源模式）
- 批量检查结果导出
- 定时自动深度检查
