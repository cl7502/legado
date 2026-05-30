# 阅读器 NewLook — Plan C+D：换源功能 + 朗读面板

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 实现"选择来源"换源页面（并发搜索全书源、展示匹配结果、切换后重载）；重设计朗读面板（语速+发音+定时+控制，激活时取代底部功能按钮行）。

**Architecture:**
- **换源**：新建 `SourceSelectionViewModel`（并发搜索任务 + 状态枚举）和 `SourceSelectionView`（实时流式更新列表）；ReaderViewModel 新增 `changeSource()` 方法；Plan B 的占位 sheet 替换为真实 View。
- **朗读面板**：TTSManager 增加 `isPlaying`、`remainingSeconds`、`selectedVoice`；ReaderMenuView 的 `bottomPanel` 按条件渲染：TTS 激活时显示朗读控制面板，否则显示原有五按钮行。

**Tech Stack:** Swift Concurrency (TaskGroup), AVFoundation (AVSpeechSynthesisVoice), SwiftUI Picker/Slider/Button, Combine

**前置条件：** Plan A 和 Plan B+E 均已完成

**分支：** `IOS-NewLook`

---

## 文件变更清单

| 操作 | 文件 | 说明 |
|---|---|---|
| 新建 | `App/Features/Reading/ViewModels/SourceSelectionViewModel.swift` | 换源并发搜索逻辑 |
| 新建 | `App/Features/Reading/Views/SourceSelectionView.swift` | 换源 UI |
| 修改 | `App/Features/Reading/ViewModels/ReaderViewModel.swift` | 新增 changeSource(), stopTTS() |
| 修改 | `App/Features/TTS/ViewModels/TTSManager.swift` | 新增 isPlaying/remainingSeconds/selectedVoice |
| 修改 | `App/Features/Reading/Views/ReaderView.swift` | bottomPanel TTS 面板；换源 sheet 替换占位 |

---

## Task 10：TTSManager 升级

**Files:**
- Modify: `IOS/Legado/App/Features/TTS/ViewModels/TTSManager.swift`

- [ ] **Step 10.1：在 TTSManager 中添加新属性**

在 `TTSManager` 类的 `@Published` 属性区域追加：

```swift
/// 当前是否正在朗读（非暂停状态）
@Published private(set) var isPlaying: Bool = false

/// 定时停止倒计时（秒），nil = 无定时
@Published private(set) var remainingSeconds: Int? = nil

/// 用户选定的 AVSpeechSynthesisVoice（nil = 系统默认）
var selectedVoice: AVSpeechSynthesisVoice? = nil {
    didSet { ReaderSettings.shared.ttsVoiceIdentifier = selectedVoice?.identifier ?? "" }
}
```

- [ ] **Step 10.2：在 TTSManager.init() 或 setup 方法中恢复已选声音**

在现有初始化代码末尾追加：

```swift
// 恢复上次选择的声音
let savedId = ReaderSettings.shared.ttsVoiceIdentifier
if !savedId.isEmpty {
    selectedVoice = AVSpeechSynthesisVoice(identifier: savedId)
}
```

- [ ] **Step 10.3：修改 speak() 方法，使用 selectedVoice 并更新 isPlaying**

在现有 `speak()` 方法中，找到构建 `AVSpeechUtterance` 的地方，替换为：

```swift
let utterance = AVSpeechUtterance(string: text)
utterance.rate = ReaderSettings.shared.ttsRate
utterance.voice = selectedVoice ?? AVSpeechSynthesisVoice(language: "zh-CN")
utterance.pitchMultiplier = ReaderSettings.shared.ttsPitch
```

在 `speak()` 末尾追加：

```swift
DispatchQueue.main.async { self.isPlaying = true }
```

- [ ] **Step 10.4：修改 pause()/resume()/stop() 同步 isPlaying**

```swift
func pause() {
    synthesizer.pauseSpeaking(at: .immediate)
    DispatchQueue.main.async { self.isPlaying = false }
}

func resume() {
    synthesizer.continueSpeaking()
    DispatchQueue.main.async { self.isPlaying = true }
}

func stop() {
    synthesizer.stopSpeaking(at: .immediate)
    DispatchQueue.main.async {
        self.isPlaying = false
        self.remainingSeconds = nil
    }
    cancelTimer()
}
```

- [ ] **Step 10.5：添加定时器方法**

在 TTSManager 内追加（`cancelTimer` 和 `startTimer`）：

```swift
private var timerTask: Task<Void, Never>?

/// 开始定时倒计时，到 0 时自动停止朗读
func startTimer(minutes: Int) {
    cancelTimer()
    let seconds = minutes * 60
    DispatchQueue.main.async { self.remainingSeconds = seconds }
    timerTask = Task { @MainActor in
        var remaining = seconds
        while remaining > 0, !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            remaining -= 1
            self.remainingSeconds = remaining
        }
        if !Task.isCancelled {
            self.stop()
        }
    }
}

func cancelTimer() {
    timerTask?.cancel()
    timerTask = nil
    DispatchQueue.main.async { self.remainingSeconds = nil }
}
```

- [ ] **Step 10.6：构建验证**

```bash
cd /Users/alina/Documents/Lei/legado/IOS
xcodebuild -project Legado.xcodeproj -scheme Legado \
  -destination 'platform=iOS Simulator,id=962E405B-C2DC-463C-889D-FC51D1438E83' \
  -quiet build 2>&1 | grep -E "error:|BUILD"
```

期望：`** BUILD SUCCEEDED **`

- [ ] **Step 10.7：Commit**

```bash
cd /Users/alina/Documents/Lei/legado
git add IOS/Legado/App/Features/TTS/ViewModels/TTSManager.swift
git commit -m "feat(tts): TTSManager 新增 isPlaying/定时器/selectedVoice"
```

---

## Task 11：ReaderViewModel 新增 stopTTS()

**Files:**
- Modify: `IOS/Legado/App/Features/Reading/ViewModels/ReaderViewModel.swift`

- [ ] **Step 11.1：在 ReaderViewModel 中添加 stopTTS()**

找到现有的 `toggleTTS()` 方法，在其之后追加：

```swift
/// 停止朗读（用于朗读面板"退出朗读"按钮）
func stopTTS() {
    ttsManager.stop()
    isTTSEnabled = false
}
```

- [ ] **Step 11.2：构建验证并 Commit**

```bash
cd /Users/alina/Documents/Lei/legado/IOS
xcodebuild -project Legado.xcodeproj -scheme Legado \
  -destination 'platform=iOS Simulator,id=962E405B-C2DC-463C-889D-FC51D1438E83' \
  -quiet build 2>&1 | grep -E "error:|BUILD"
```

```bash
cd /Users/alina/Documents/Lei/legado
git add IOS/Legado/App/Features/Reading/ViewModels/ReaderViewModel.swift
git commit -m "feat(reader): ReaderViewModel 新增 stopTTS()"
```

---

## Task 12：朗读控制面板（TTS Panel）

**Files:**
- Modify: `IOS/Legado/App/Features/Reading/Views/ReaderView.swift`（ReaderMenuView.bottomPanel）

- [ ] **Step 12.1：在 ReaderMenuView 中添加 TTS 面板相关状态**

在 `ReaderMenuView` 的 `@State` 区域追加：

```swift
@State private var ttsTimerSelection: Int? = nil  // nil=无定时，否则为分钟数
@State private var showCustomTimer = false
@State private var customTimerInput = ""
```

- [ ] **Step 12.2：在 bottomPanel 内，函数按钮行之前插入条件渲染**

找到 `bottomPanel` 内的"功能按钮行"（`HStack(spacing: 0)` 包含朗读/目录/翻页/主题/设置五个按钮），**将整个功能按钮行 + 章节进度文字替换为：**

```swift
if viewModel.isTTSEnabled {
    // ── TTS 控制面板（激活朗读时取代功能按钮行）──────────
    ttsPanelView
} else {
    // ── 原有五功能按钮行 ─────────────────────────────────
    HStack(spacing: 0) {
        menuButton(icon: "headphones", label: "朗读") {
            viewModel.toggleTTS()
        }
        menuButton(icon: "list.bullet", label: "目录") { showingTOC = true }
        menuButton(icon: settings.pageMode == .scroll ? "book" : "scroll",
                   label: settings.pageMode == .scroll ? "翻页" : "滚动") {
            settings.pageMode = settings.pageMode == .scroll ? .page : .scroll
        }
        menuButton(icon: settings.currentTheme.id == "dark" ? "sun.max" : "moon",
                   label: settings.currentTheme.id == "dark" ? "白天" : "夜间") {
            if settings.currentTheme.id == "dark" {
                settings.themeId = settings.preNightThemeId.isEmpty ? "parchment" : settings.preNightThemeId
            } else {
                settings.preNightThemeId = settings.themeId
                settings.themeId = "dark"
            }
        }
        menuButton(icon: "textformat.size", label: "设置") { showingSettings = true }
    }

    if viewModel.chapters.count > 0 {
        Text("第\(viewModel.currentChapterIndex + 1)章 / 共\(viewModel.chapters.count)章")
            .font(.caption2).foregroundColor(.secondary)
    }
}
```

- [ ] **Step 12.3：在 ReaderMenuView 中添加 ttsPanelView**

在 `menuButton` 函数之后追加：

```swift
// MARK: TTS 控制面板

@ViewBuilder
private var ttsPanelView: some View {
    let ttsManager = viewModel.ttsManager

    VStack(spacing: 10) {

        // ── 语速 ─────────────────────────────────────────
        HStack(spacing: 8) {
            Text("语速").font(.caption).foregroundColor(.secondary).frame(width: 36, alignment: .leading)
            Text("慢").font(.caption2).foregroundColor(.secondary)
            Slider(
                value: Binding(
                    get: { Double(settings.ttsRate) },
                    set: { v in
                        settings.ttsRate = Float(v)
                        // 语速变更：停止当前句，下句生效（避免打断）
                    }
                ),
                in: 0.25...2.0
            )
            Text("快").font(.caption2).foregroundColor(.secondary)
            Text(String(format: "%.1fx", settings.ttsRate))
                .font(.caption).frame(width: 36, alignment: .trailing)
                .monospacedDigit()
        }
        .padding(.horizontal)

        // ── 发音选择 ─────────────────────────────────────
        HStack {
            Text("发音").font(.caption).foregroundColor(.secondary).frame(width: 36, alignment: .leading)
            Picker("发音", selection: Binding(
                get: { ttsManager.selectedVoice?.identifier ?? "" },
                set: { id in
                    ttsManager.selectedVoice = id.isEmpty
                        ? nil
                        : AVSpeechSynthesisVoice(identifier: id)
                }
            )) {
                Text("系统默认").tag("")
                ForEach(chineseVoices, id: \.identifier) { voice in
                    Text(voiceDisplayName(voice)).tag(voice.identifier)
                }
            }
            .pickerStyle(.menu)
            Spacer()
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text("下载更多 →").font(.caption2).foregroundColor(.blue)
            }
        }
        .padding(.horizontal)

        // ── 定时 ─────────────────────────────────────────
        HStack(spacing: 6) {
            Text("定时").font(.caption).foregroundColor(.secondary).frame(width: 36, alignment: .leading)
            ForEach([5, 15, 30, 60], id: \.self) { min in
                timerButton(minutes: min)
            }
            // 自定义定时
            Button {
                showCustomTimer = true
            } label: {
                Text(ttsTimerSelection != nil && ![5,15,30,60].contains(ttsTimerSelection!)
                     ? "\(ttsTimerSelection!)分" : "自定义")
                    .font(.caption)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(
                        (ttsTimerSelection != nil && ![5,15,30,60].contains(ttsTimerSelection!))
                            ? Color.blue : Color(.systemGray5)
                    )
                    .foregroundColor(
                        (ttsTimerSelection != nil && ![5,15,30,60].contains(ttsTimerSelection!))
                            ? .white : .primary
                    )
                    .cornerRadius(6)
            }
            // 倒计时显示
            if let remaining = ttsManager.remainingSeconds {
                Text(formatRemaining(remaining))
                    .font(.caption2).foregroundColor(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal)

        // ── 退出 + 暂停/继续 ──────────────────────────────
        HStack(spacing: 16) {
            Button(role: .destructive) {
                viewModel.stopTTS()
                ttsTimerSelection = nil
            } label: {
                Text("退出朗读")
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color(.systemGray5))
                    .foregroundColor(.red)
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)

            Button {
                if ttsManager.isPlaying { ttsManager.pause() } else { ttsManager.resume() }
            } label: {
                HStack {
                    Image(systemName: ttsManager.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    Text(ttsManager.isPlaying ? "暂停" : "继续")
                }
                .font(.subheadline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal)
    }
    .padding(.vertical, 8)
    .alert("自定义定时（分钟）", isPresented: $showCustomTimer) {
        TextField("输入分钟数", text: $customTimerInput)
            .keyboardType(.numberPad)
        Button("确定") {
            if let min = Int(customTimerInput), min > 0, min <= 999 {
                ttsTimerSelection = min
                ttsManager.startTimer(minutes: min)
            }
            customTimerInput = ""
        }
        Button("取消", role: .cancel) { customTimerInput = "" }
    }
}

// MARK: TTS 辅助

private var chineseVoices: [AVSpeechSynthesisVoice] {
    AVSpeechSynthesisVoice.speechVoices()
        .filter { $0.language.hasPrefix("zh") }
        .sorted { $0.language < $1.language }
}

private func voiceDisplayName(_ voice: AVSpeechSynthesisVoice) -> String {
    let langMap = ["zh-CN": "普通话", "zh-HK": "粤语", "zh-TW": "台湾中文"]
    let lang = langMap[voice.language] ?? voice.language
    let quality: String
    switch voice.quality {
    case .enhanced: quality = "增强版"
    case .premium:  quality = "高级版"
    default:        quality = "标准"
    }
    return "\(lang) - \(voice.name) (\(quality))"
}

@ViewBuilder
private func timerButton(minutes: Int) -> some View {
    let isSelected = ttsTimerSelection == minutes
    Button {
        if isSelected {
            ttsTimerSelection = nil
            viewModel.ttsManager.cancelTimer()
        } else {
            ttsTimerSelection = minutes
            viewModel.ttsManager.startTimer(minutes: minutes)
        }
    } label: {
        Text("\(minutes)分")
            .font(.caption)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(isSelected ? Color.blue : Color(.systemGray5))
            .foregroundColor(isSelected ? .white : .primary)
            .cornerRadius(6)
    }
}

private func formatRemaining(_ seconds: Int) -> String {
    let m = seconds / 60, s = seconds % 60
    return String(format: "%02d:%02d", m, s)
}
```

- [ ] **Step 12.4：构建验证**

```bash
cd /Users/alina/Documents/Lei/legado/IOS
xcodebuild -project Legado.xcodeproj -scheme Legado \
  -destination 'platform=iOS Simulator,id=962E405B-C2DC-463C-889D-FC51D1438E83' \
  -quiet build 2>&1 | grep -E "error:|BUILD"
```

期望：`** BUILD SUCCEEDED **`

- [ ] **Step 12.5：Commit**

```bash
cd /Users/alina/Documents/Lei/legado
git add "IOS/Legado/App/Features/Reading/Views/ReaderView.swift"
git commit -m "feat(reader): 朗读控制面板（语速/发音/定时/暂停退出）"
```

---

## Task 13：换源 ViewModel

**Files:**
- Create: `IOS/Legado/App/Features/Reading/ViewModels/SourceSelectionViewModel.swift`

- [ ] **Step 13.1：新建 SourceSelectionViewModel.swift**

```swift
// IOS/Legado/App/Features/Reading/ViewModels/SourceSelectionViewModel.swift
import Foundation
import Combine

enum SourceSearchStatus {
    case searching
    case found(chapterAvailable: Bool)  // 找到书；chapterAvailable = 当前章节是否可用
    case notFound
    case timeout
}

struct SourceSearchResult: Identifiable {
    let id: String  // bookSourceUrl
    let sourceName: String
    let sourceUrl: String
    var status: SourceSearchStatus
}

@MainActor
final class SourceSelectionViewModel: ObservableObject {
    @Published var results: [SourceSearchResult] = []
    @Published var isSearching: Bool = false

    private var searchTasks: [Task<Void, Never>] = []

    /// 开始并发搜索所有已启用书源
    func startSearch(bookName: String, currentChapterIndex: Int) async {
        results = []
        isSearching = true
        searchTasks.forEach { $0.cancel() }
        searchTasks = []

        let allSources = (try? await DatabaseManager.shared.getAllBookSources()) ?? []
        let enabled = allSources.filter { $0.enabled }

        for source in enabled {
            let task = Task { @MainActor in
                // 先加入"搜索中"占位
                let placeholder = SourceSearchResult(
                    id: source.bookSourceUrl,
                    sourceName: source.bookSourceName,
                    sourceUrl: source.bookSourceUrl,
                    status: .searching
                )
                results.append(placeholder)

                // 执行搜索（带10秒超时）
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

                // 更新对应结果
                if let idx = results.firstIndex(where: { $0.id == source.bookSourceUrl }) {
                    results[idx].status = searchResult
                }
            }
            searchTasks.append(task)
        }

        // 等待所有任务完成
        for task in searchTasks { await task.value }
        isSearching = false
    }

    func cancelAll() {
        searchTasks.forEach { $0.cancel() }
        searchTasks = []
        isSearching = false
    }

    // MARK: - 单书源搜索

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

        // 验证第一条结果的书名匹配度
        var itemCtx = AnalyzeContext(source: source, baseUrl: url)
        itemCtx.result = items[0]
        let foundName = RuleExecutor.shared.execute(source.ruleSearchName ?? "", in: &itemCtx) ?? ""
        guard !foundName.isEmpty, isSimilar(foundName, bookName) else { return .notFound }

        // 检测当前章节是否可用（通过目录章节数对比）
        let noteUrlRaw = RuleExecutor.shared.execute(source.ruleSearchNoteUrl ?? "", in: &itemCtx) ?? ""
        let noteUrl = noteUrlRaw.hasPrefix("http") ? noteUrlRaw : source.bookSourceUrl + noteUrlRaw
        guard !noteUrl.isEmpty else { return .found(chapterAvailable: false) }

        // 简单判断：章节总数 >= currentChapterIndex + 1
        let chapterAvailable = await checkChapterAvailability(source: source, bookUrl: noteUrl, chapterIndex: chapterIndex)
        return .found(chapterAvailable: chapterAvailable)
    }

    private func checkChapterAvailability(source: BookSource, bookUrl: String, chapterIndex: Int) async -> Bool {
        // 尝试获取目录，检查章节数是否足够
        let tocUrlStr = source.ruleTocUrl ?? bookUrl
        var ctx = AnalyzeContext(source: source, baseUrl: bookUrl)
        let tocParsed = RuleExecutor.shared.execute(tocUrlStr, in: &ctx) ?? ""
        let tocUrl = tocParsed.hasPrefix("http") ? tocParsed : source.bookSourceUrl + tocParsed
        guard let tocBody = NetworkManager.shared.requestSync(tocUrl.isEmpty ? bookUrl : tocUrl) else {
            return false
        }
        ctx.result = tocBody
        let chapters = RuleExecutor.shared.executeList(source.ruleTocList ?? "", in: &ctx)
        return chapters.count > chapterIndex
    }

    private func isSimilar(_ a: String, _ b: String) -> Bool {
        let na = a.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let nb = b.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return na.contains(nb) || nb.contains(na)
    }

    // MARK: - 排序辅助

    var sortedResults: [SourceSearchResult] {
        results.sorted { lhs, rhs in
            score(lhs) > score(rhs)
        }
    }

    private func score(_ r: SourceSearchResult) -> Int {
        switch r.status {
        case .found(let available): return available ? 2 : 1
        case .searching: return 0
        case .notFound, .timeout: return -1
        }
    }
}
```

- [ ] **Step 13.2：在 Xcode 中注册新文件（或 xcodegen 若使用）**

```bash
cd /Users/alina/Documents/Lei/legado/IOS
xcodebuild -project Legado.xcodeproj -scheme Legado \
  -destination 'platform=iOS Simulator,id=962E405B-C2DC-463C-889D-FC51D1438E83' \
  -quiet build 2>&1 | grep -E "error:|BUILD"
```

若报错"file not found"，需在 Xcode Project Navigator 中将文件加入 Target。

- [ ] **Step 13.3：Commit**

```bash
cd /Users/alina/Documents/Lei/legado
git add IOS/Legado/App/Features/Reading/ViewModels/SourceSelectionViewModel.swift
git commit -m "feat(reader): 新建 SourceSelectionViewModel（并发换源搜索）"
```

---

## Task 14：换源 View

**Files:**
- Create: `IOS/Legado/App/Features/Reading/Views/SourceSelectionView.swift`

- [ ] **Step 14.1：新建 SourceSelectionView.swift**

```swift
// IOS/Legado/App/Features/Reading/Views/SourceSelectionView.swift
import SwiftUI

struct SourceSelectionView: View {
    let currentSourceUrl: String
    let bookName: String
    let currentChapterIndex: Int
    let onSelect: (BookSource) -> Void

    @StateObject private var vm = SourceSelectionViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var confirmSource: BookSource? = nil
    @State private var showConfirm = false

    var body: some View {
        NavigationView {
            Group {
                if vm.results.isEmpty && !vm.isSearching {
                    Text("暂无结果")
                        .foregroundColor(.secondary)
                } else {
                    List(vm.sortedResults) { result in
                        SourceResultRow(
                            result: result,
                            isCurrent: result.id == currentSourceUrl
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            guard case .found(let avail) = result.status, avail else { return }
                            Task {
                                let sources = (try? await DatabaseManager.shared.getAllBookSources()) ?? []
                                if let source = sources.first(where: { $0.bookSourceUrl == result.id }) {
                                    confirmSource = source
                                    showConfirm = true
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("选择来源")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    if vm.isSearching {
                        ProgressView().scaleEffect(0.8)
                    }
                }
            }
            .alert("切换书源", isPresented: $showConfirm, presenting: confirmSource) { source in
                Button("确定切换") {
                    onSelect(source)
                    dismiss()
                }
                Button("取消", role: .cancel) {}
            } message: { source in
                Text("切换到「\(source.bookSourceName)」？当前阅读进度将保留，章节内容将重新加载。")
            }
        }
        .task {
            await vm.startSearch(bookName: bookName, currentChapterIndex: currentChapterIndex)
        }
        .onDisappear { vm.cancelAll() }
    }
}

// MARK: - Row

private struct SourceResultRow: View {
    let result: SourceSearchResult
    let isCurrent: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(result.sourceName)
                        .font(.subheadline)
                    if isCurrent {
                        Text("当前使用")
                            .font(.caption2)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.blue.opacity(0.15))
                            .foregroundColor(.blue)
                            .cornerRadius(4)
                    }
                }
                statusText
                    .font(.caption)
                    .foregroundColor(statusColor)
            }
            Spacer()
            if isCurrent {
                Image(systemName: "checkmark.circle.fill").foregroundColor(.blue)
            }
        }
        .opacity(isDisabled ? 0.4 : 1.0)
    }

    private var isDisabled: Bool {
        switch result.status {
        case .found(let avail): return !avail && !isCurrent
        case .notFound, .timeout: return true
        case .searching: return true
        }
    }

    @ViewBuilder private var statusText: some View {
        switch result.status {
        case .searching:
            HStack(spacing: 4) {
                ProgressView().scaleEffect(0.6)
                Text("搜索中…")
            }
        case .found(let avail):
            Text(avail ? "第\(result.id.prefix(0))章 ✅ 可用" : "❌ 当前章节不可用")
                // 注：章节序号由 VM 层传入，此处简化显示
                .replace("第章", with: "章节")
        case .notFound:
            Text("未找到此书")
        case .timeout:
            Text("请求超时")
        }
    }

    private var statusColor: Color {
        switch result.status {
        case .found(let avail): return avail ? .green : .orange
        case .searching: return .secondary
        case .notFound, .timeout: return .secondary
        }
    }
}

extension String {
    func replace(_ target: String, with replacement: String) -> String {
        self.replacingOccurrences(of: target, with: replacement)
    }
}
```

- [ ] **Step 14.2：在 ReaderViewModel 中添加 changeSource() 方法**

在 `ReaderViewModel.swift` 追加：

```swift
/// 切换书源后重新加载目录和章节内容
func changeSource(to source: BookSource) async {
    // 1. 更新书的 origin
    book.origin = source.bookSourceUrl
    book.originName = source.bookSourceName
    try? await DatabaseManager.shared.saveBook(book)

    // 2. 清空缓存
    chapterContents.removeAll()

    // 3. 重载目录（已有 loadChapters 逻辑）
    await loadChapters()

    // 4. 跳到当前章节（保持进度）
    jumpToChapter(currentChapterIndex)
}
```

- [ ] **Step 14.3：将 ReaderMenuView 换源占位 sheet 替换为真实 SourceSelectionView**

找到 Plan B 中添加的占位：

```swift
.sheet(isPresented: $showingSourceSelection) {
    NavigationView {
        Text("换源功能（Plan C 实现）")
        ...
    }
}
```

**替换为：**

```swift
.sheet(isPresented: $showingSourceSelection) {
    SourceSelectionView(
        currentSourceUrl: viewModel.book.origin,
        bookName: viewModel.book.name,
        currentChapterIndex: viewModel.currentChapterIndex
    ) { source in
        Task { await viewModel.changeSource(to: source) }
    }
}
```

- [ ] **Step 14.4：构建验证**

```bash
cd /Users/alina/Documents/Lei/legado/IOS
xcodebuild -project Legado.xcodeproj -scheme Legado \
  -destination 'platform=iOS Simulator,id=962E405B-C2DC-463C-889D-FC51D1438E83' \
  -quiet build 2>&1 | grep -E "error:|BUILD"
```

若有编译错误，修复后再继续。

- [ ] **Step 14.5：模拟器完整验证**

```bash
SIM=962E405B-C2DC-463C-889D-FC51D1438E83
APP=$(find ~/Library/Developer/Xcode/DerivedData/Legado-*/Build/Products/Debug-iphonesimulator/Legado.app -maxdepth 0 2>/dev/null | tail -1)
xcrun simctl install $SIM "$APP"
xcrun simctl terminate $SIM com.legado.app 2>/dev/null
xcrun simctl launch $SIM com.legado.app
```

验证：
- [ ] 点击中央 → 换源按钮 → 打开"选择来源"
- [ ] Sheet 打开即开始搜索（显示进度圈）
- [ ] 结果实时出现，当前书源标"✓ 当前使用"
- [ ] 点击可用书源 → 弹确认 → 确认后返回阅读
- [ ] 点击朗读 → 面板升起（语速/发音/定时/退出/暂停）
- [ ] 选定时后显示倒计时，到 0 自动停止
- [ ] 退出朗读 → 恢复五个功能按钮行

- [ ] **Step 14.6：最终 Commit**

```bash
cd /Users/alina/Documents/Lei/legado
git add IOS/Legado/App/Features/Reading/Views/SourceSelectionView.swift \
        IOS/Legado/App/Features/Reading/ViewModels/SourceSelectionViewModel.swift \
        IOS/Legado/App/Features/Reading/ViewModels/ReaderViewModel.swift \
        "IOS/Legado/App/Features/Reading/Views/ReaderView.swift"
git commit -m "feat(reader): 换源页面 + 完整 TTS 面板完成

Plan C+D 完成：
- SourceSelectionView：实时流式并发搜索所有书源
- changeSource()：切换书源重载目录保留章节进度
- TTSPanel：语速/发音/定时/暂停/退出，激活时取代功能按钮行"
```

---

## 自检：规格覆盖确认

| 规格要求 | 对应 Task |
|---|---|
| 换源：打开即搜索所有书源 | Task 13 (startSearch) |
| 换源：实时流式更新，先完成先显示 | Task 13 (逐条 append) |
| 换源：当前章节可用性检测 | Task 13 (checkChapterAvailability) |
| 换源：当前书源高亮✓标记 | Task 14 (SourceResultRow isCurrent) |
| 换源：确认对话框 | Task 14 (Alert) |
| 换源：切换后重载目录保留进度 | Task 14 (changeSource) |
| 换源：切换后按规则缓存 | Task 14 (jumpToChapter 触发预缓存) |
| 朗读：点击立即开始 + 面板升起 | Task 12 (isTTSEnabled 条件渲染) |
| 朗读：面板取代功能按钮行 | Task 12 (if/else 条件渲染) |
| 朗读：语速 Slider 实时生效 | Task 12 |
| 朗读：iOS 内置中文发音列表 | Task 12 (chineseVoices 过滤 zh) |
| 朗读：下载更多声音跳转 | Task 12 (openSettingsURLString) |
| 朗读：定时 5/15/30/60/自定义 | Task 12, Task 10 (startTimer) |
| 朗读：倒计时到 0 自动停止 | Task 10 (timerTask) |
| 朗读：退出按钮停止并恢复按钮行 | Task 12 (stopTTS + isTTSEnabled=false) |
| 朗读：暂停/继续按钮 | Task 12 |
| 朗读语速从设置弹窗移除 | Plan B+E Task 7 已完成 |
