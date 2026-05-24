# Legado iOS 实现情况全面审计报告

**审计日期：** 2026-05-24
**分支：** IOS
**审计范围：** `IOS/Legado/` 目录下全部 Swift 源码（49 个文件）

---

## 一、项目结构总览

```
IOS/
├── Legado/
│   ├── Package.swift              # SPM 包描述（iOS 15+，macOS 13+）
│   ├── App/
│   │   ├── LegadoApp.swift        # @main 入口
│   │   ├── ContentView.swift      # 根视图（直接转发至 MainTabView）
│   │   ├── UI/
│   │   │   ├── MainTabView.swift          # 底部 Tab 导航（书架/搜索/书源/设置）
│   │   │   ├── SettingsView.swift         # 设置界面
│   │   │   └── SettingsViewModel.swift    # 设置逻辑
│   │   ├── Core/
│   │   │   ├── Database/
│   │   │   │   ├── DatabaseManager.swift         # GRDB 数据库管理 + DAO
│   │   │   │   └── DatabaseModels+GRDB.swift     # 模型的 GRDB 协议符合
│   │   │   ├── Network/
│   │   │   │   ├── NetworkManager.swift           # Alamofire 网络层
│   │   │   │   ├── LegadoInterceptor.swift        # 请求拦截（UA/Cookie 注入）
│   │   │   │   ├── CookieManager.swift            # Cookie 持久化（UserDefaults）
│   │   │   │   ├── EncodingHelper.swift           # GBK/UTF-8 自动识别
│   │   │   │   └── BackgroundDownloadManager.swift # 后台下载（URLSession）
│   │   │   ├── Engine/
│   │   │   │   ├── RuleParser.swift        # 规则片段解析（CSS/XPath/JSON/JS/Regex）
│   │   │   │   ├── RuleExecutor.swift      # 链式规则执行调度
│   │   │   │   ├── AnalyzeContext.swift    # 解析上下文（书源/结果/变量/页码）
│   │   │   │   ├── JSONPathEngine.swift    # 简易 JSONPath 实现
│   │   │   │   ├── BookContentParser.swift # 正文提取 + HTML 转纯文本
│   │   │   │   └── ContentProcessor.swift  # 净化规则处理器
│   │   │   ├── HTML/
│   │   │   │   └── HTMLParser.swift        # SwiftSoup CSS + XPath 解析
│   │   │   └── JSBridge/
│   │   │       ├── LegadoJSEngine.swift    # JavaScriptCore 引擎封装
│   │   │       └── JSJavaHelper.swift      # JS 侧 java.* API 实现
│   │   └── Features/
│   │       ├── BookSource/
│   │       │   ├── Models/
│   │       │   │   ├── BookSource.swift    # 书源数据模型
│   │       │   │   └── SearchResult.swift  # 搜索结果模型
│   │       │   ├── ViewModels/
│   │       │   │   ├── BookSourceViewModel.swift  # 书源管理逻辑 + 导入
│   │       │   │   └── SearchViewModel.swift      # 搜索执行逻辑
│   │       │   └── Views/
│   │       │       ├── BookSourceListView.swift   # 书源列表界面
│   │       │       └── SearchView.swift           # 搜索界面
│   │       ├── Reading/
│   │       │   ├── Models/
│   │       │   │   ├── Book.swift           # 书籍模型
│   │       │   │   ├── Chapter.swift        # 章节模型
│   │       │   │   ├── ReaderSettings.swift # 阅读器设置（持久化）
│   │       │   │   └── ReplaceRule.swift    # 内容净化规则
│   │       │   ├── ViewModels/
│   │       │   │   ├── ReaderViewModel.swift      # 阅读器核心逻辑
│   │       │   │   └── BookshelfViewModel.swift   # 书架逻辑
│   │       │   └── Views/
│   │       │       ├── BookshelfView.swift        # 书架界面（3 列网格）
│   │       │       ├── BookInfoView.swift         # 书籍详情 + 加入书架
│   │       │       ├── ReaderView.swift           # 阅读器容器
│   │       │       ├── SimulationPagingView.swift # UIPageViewController 仿真翻页
│   │       │       ├── TOCView.swift              # 目录视图
│   │       │       └── ReaderSettingsSheet.swift  # 排版/主题设置面板
│   │       └── TTS/
│   │           └── ViewModels/
│   │               └── TTSManager.swift    # 语音朗读管理（AVSpeechSynthesizer）
│   └── Tests/
│       ├── Unit/
│       │   ├── RuleExecutorTests.swift    # 规则引擎单元测试
│       │   └── NetworkManagerTests.swift  # 网络编码/Cookie 单元测试
│       └── Integration/
│           └── IntegrationTests.swift     # 搜索到书架集成测试
└── Phase0/
    └── Test/                              # 早期验证测试（Phase0 遗留）
        ├── HTMLParserTests.swift
        ├── JavaScriptCoreTests.swift
        ├── RhinoAPITests.swift
        ├── RuleParserTests.swift
        └── ValidationRunner.swift
```

**第三方依赖（Package.swift）：**
- `Alamofire 5.8.1` — 网络请求
- `SwiftSoup 2.7.2` — HTML 解析（CSS + XPath）
- `GRDB.swift 6.24.2` — SQLite 数据库 ORM

---

## 二、已实现的功能列表

### 2.1 核心引擎层

| 功能 | 文件 | 完成度 |
|------|------|--------|
| CSS 选择器解析（单体/列表） | `HTMLParser.swift` | 完整 |
| XPath 解析（SwiftSoup 原生） | `HTMLParser.swift` | 基础可用，见限制说明 |
| JSONPath 提取 | `JSONPathEngine.swift` | 简化实现，见限制说明 |
| 链式规则解析（`@` 分隔） | `RuleParser.swift` + `RuleExecutor.swift` | 基础支持 |
| JS 脚本执行（JavaScriptCore） | `LegadoJSEngine.swift` | 基础可用，非 Rhino |
| JS `java.*` 工具桥接 | `JSJavaHelper.swift` | 部分实现（约 10 个方法） |
| 正文提取与 HTML 转文本 | `BookContentParser.swift` | 基础可用 |
| 内容净化规则（Regex/字符串替换） | `ContentProcessor.swift` | 完整 |
| 解析上下文（变量/页码透传） | `AnalyzeContext.swift` | 完整 |

### 2.2 网络层

| 功能 | 文件 | 完成度 |
|------|------|--------|
| GET/POST 异步请求 | `NetworkManager.swift` | 完整 |
| 同步请求（JS 内调用） | `NetworkManager.swift` | 完整（DispatchSemaphore） |
| Cookie 自动注入与持久化 | `CookieManager.swift` + `LegadoInterceptor.swift` | 完整 |
| User-Agent 注入（模拟 Android） | `LegadoInterceptor.swift` | 完整 |
| GBK/UTF-8 编码自动识别 | `EncodingHelper.swift` | 完整（GB_18030_2000） |
| 书源静态 Header 注入 | `NetworkManager.swift` | 完整 |
| 后台下载 Session | `BackgroundDownloadManager.swift` | 骨架（未与正文/章节集成） |

### 2.3 数据层

| 功能 | 文件 | 完成度 |
|------|------|--------|
| SQLite 数据库初始化（GRDB） | `DatabaseManager.swift` | 完整 |
| 数据库迁移（v1） | `DatabaseManager.swift` | 完整 |
| 书源 CRUD | `DatabaseManager.swift` | 完整 |
| 书架 CRUD | `DatabaseManager.swift` | 完整 |
| 章节 CRUD | `DatabaseManager.swift` | 完整 |
| 净化规则读取 | `DatabaseManager.swift` | 只读（无写入 UI） |
| 书源 JSON 批量导入 | `BookSourceViewModel.swift` | 完整 |

### 2.4 书源功能

| 功能 | 文件 | 完成度 |
|------|------|--------|
| 书源数据模型（扁平字段） | `BookSource.swift` | 部分（见重大缺陷） |
| 书源列表展示/启用切换/删除 | `BookSourceListView.swift` + `BookSourceViewModel.swift` | 完整 |
| 书源 JSON 导入（粘贴文本） | `BookSourceViewModel.swift` | 完整 |
| 搜索执行（并发多源） | `SearchViewModel.swift` | 完整 |
| 书籍详情页加载 | `BookInfoView.swift` + `BookInfoViewModel.swift` | 基础可用（缺字段） |

### 2.5 阅读功能

| 功能 | 文件 | 完成度 |
|------|------|--------|
| 书架网格展示（3 列，封面+进度） | `BookshelfView.swift` | 完整 |
| 章节列表加载 | `ReaderViewModel.swift` | 完整（但 TOC 网络抓取未完全实现，见缺陷） |
| 章节正文加载（网络+解析） | `ReaderViewModel.swift` | 完整 |
| 章节预加载（下一章） | `ReaderViewModel.swift` | 完整（+1 预加载） |
| 阅读进度同步（数据库） | `ReaderViewModel.swift` | 完整 |
| 仿真翻页（UIPageViewController pageCurl） | `SimulationPagingView.swift` | 完整（章节级翻页） |
| 三段式点击区域（上章/菜单/下章） | `ReaderView.swift` | 完整 |
| 目录（TOC）界面 | `TOCView.swift` | 完整 |
| 字号/行高/边距调节 | `ReaderSettingsSheet.swift` + `ReaderSettings.swift` | 完整 |
| 主题切换（4 套预设） | `ReaderSettings.swift` | 完整 |
| TTS 朗读（AVSpeech） | `TTSManager.swift` | 完整 |
| TTS 锁屏控制（MPRemoteCommandCenter） | `TTSManager.swift` | 完整 |
| TTS 连读（章节结束自动下一章） | `ReaderViewModel.swift` | 完整 |

---

## 三、缺失的功能列表

### 3.1 严重缺失（阻塞实际使用）

1. **目录（TOC）网络抓取逻辑未实现**
   - `ReaderViewModel.loadChapters()` 方法在代码中被调用但**不存在**（方法体缺失）。
   - `BookshelfViewModel` 只从数据库读章节，没有触发书源的目录规则抓取。
   - 实际后果：新书加入书架后无法获取章节列表，阅读器无内容可展示。

2. **书源编辑界面完全缺失**
   - Android 版有完整的 `BookSourceEditActivity`（含规则调试器）。
   - iOS 版只有只读列表，无法创建/编辑单个书源字段。

3. **发现（Explore）功能完全缺失**
   - Android 版的 `exploreUrl` / `ruleExplore` 支持书源内置分类浏览。
   - iOS 版中 `BookSource.exploreUrl` 字段存在但无任何对应逻辑和界面。

4. **净化规则管理界面缺失**
   - `ReplaceRule` 模型和数据库表已定义，但无任何 UI 可以查看/添加/编辑净化规则。

5. **章节内分页（页内翻页）未实现**
   - 当前 `SimulationPagingView` 以**章节为粒度**翻页（每页 = 一整章）。
   - Android 版有完整的 `TextChapterLayout` 将章节按屏幕尺寸切分为多页。
   - 实际后果：长章节只能滚动，无法体验真正的翻页效果。

6. **URL 模板解析（AnalyzeUrl）缺失**
   - Android 版 `AnalyzeUrl`（851行）支持 `{{key}}`、`{{page}}`、`{{variable}}`、POST body、动态 Header 表达式等复杂模板。
   - iOS 版 `SearchViewModel` 只做了 `{{key}}` 的简单字符串替换，其他模板变量全部不支持。
   - 实际后果：大量书源的搜索、分页、目录翻页 URL 无法正确生成。

### 3.2 重要缺失（影响多数书源兼容性）

7. **书源 JSON 格式不兼容（扁平化 vs 嵌套）**
   - Android 书源 JSON 中规则是**嵌套对象**：`ruleSearch.bookList`、`ruleToc.chapterList`、`ruleContent.content`。
   - iOS `BookSource.swift` 将所有字段**平铺**（`ruleSearchList`、`ruleTocList`、`ruleContent`），且 `CodingKeys` 未做嵌套解析适配。
   - 实际后果：直接导入真实书源 JSON 后，规则字段全部解析为 `nil`，书源失效。

8. **TocRule 缺失关键字段**
   - Android `TocRule` 有 `nextTocUrl`（目录翻页）、`preUpdateJs`、`formatJs`、`isVolume` 等。
   - iOS 只有 `ruleTocList`、`ruleChapterName`、`ruleChapterUrl`、`ruleChapterVip`，缺少翻页和卷标支持。

9. **ContentRule 缺失关键字段**
   - Android `ContentRule` 有 `nextContentUrl`（正文翻页）、`webJs`（WebView JS 执行）、`sourceRegex`、`replaceRegex`、`imageStyle`、`imageDecode` 等。
   - iOS 只有单一 `ruleContent` 字符串，不支持正文翻页。

10. **BookInfoRule 缺失字段**
    - Android 有 `updateTime`、`wordCount`、`canReName`、`downloadUrls` 等。
    - iOS `BookInfoView` 中详情页规则只执行了 `intro` 和 `tocUrl`，其余字段（`name`、`author`、`coverUrl` 等）未从详情页覆盖更新。

11. **规则链 `@` 分割逻辑错误**
    - `RuleParser.parseChain()` 直接用 `components(separatedBy: "@")` 分割。
    - 问题：`@XPath:` 前缀中的 `@`、JS 代码内的字符串中的 `@`、CSS 选择器中的 `@text` / `@href` 等都会被错误切割。
    - Android 的 `RuleAnalyzer`（377行）有完整的带状态机的分割器，避免上述问题。

12. **`@text`、`@href`、`@src` 等 CSS 属性提取缺失**
    - `HTMLParser.text()` 只返回 `.text()`，不处理 `query@attr` 语法。
    - Android `AnalyzeByJSoup` 解析 `div.title@href` 等混合选择器。
    - 实际后果：所有依赖属性提取的书源规则返回空值。

13. **JSONPath `[*]` 展开和过滤器不完整**
    - `JSONPathEngine` 只处理 `$.a.b[0]` 和 `[*]` 两种情况，不支持 `$.data[?(@.type==1)]`、`$..[*]` 递归等 Legado 常用语法。

14. **并发限速（concurrentRate）未实现**
    - Android 有 `ConcurrentRateLimiter` 控制对同一书源的并发请求数。
    - iOS 的搜索使用 `withTaskGroup` 无任何限速，高并发会触发书源封禁。

15. **书源 `jsLib` 全局 JS 库注入未实现**
    - Android 书源可携带 `jsLib` 字段，为所有 JS 规则提供公共函数库。
    - iOS `LegadoJSEngine` 无此注入逻辑。

### 3.3 次要缺失（影响完整体验）

16. **RSS 源（bookSourceType=2）不支持**
17. **音频书（bookSourceType=1）不支持**
18. **书源批量导入（URL 链接导入）缺失** — 只支持粘贴 JSON 文本
19. **书架排序/分组缺失**
20. **更新检测（lastCheckTime / canUpdate）未实现**
21. **书源调试器（Debug 模式）缺失**
22. **搜索结果去重/合并多源逻辑缺失**
23. **阅读器书签功能缺失**
24. **自定义字体支持缺失**
25. **TTS 自定义语音选择缺失**（固定为 `zh-CN`）
26. **后台下载未与章节缓存集成**（`BackgroundDownloadManager` 是孤立骨架）
27. **设置页面内容稀少**（缺少阅读偏好、网络代理、备份导出等）
28. **iCloud 备份/恢复缺失**

---

## 四、书源逻辑实现情况详析

### 4.1 书源数据模型（严重缺陷）

Android 书源规则采用**嵌套对象**结构：

```kotlin
// Android: BookSource.kt
var ruleSearch: SearchRule?   // { bookList, name, author, ... }
var ruleBookInfo: BookInfoRule? // { init, name, author, tocUrl, ... }
var ruleToc: TocRule?         // { chapterList, chapterName, chapterUrl, nextTocUrl, ... }
var ruleContent: ContentRule? // { content, nextContentUrl, webJs, replaceRegex, ... }
var ruleExplore: ExploreRule? // { bookList, ... }
```

iOS 书源将字段**平铺**，且命名不完全对应：

```swift
// iOS: BookSource.swift
var ruleSearchList: String?       // 对应 ruleSearch.bookList
var ruleContent: String?          // 对应 ruleContent.content（其余字段丢失）
// 缺失: ruleContent.nextContentUrl, ruleContent.webJs, ruleContent.replaceRegex
// 缺失: ruleToc.nextTocUrl, ruleToc.formatJs, ruleToc.isVolume
// 缺失: ruleBookInfo.updateTime, ruleBookInfo.wordCount
// 缺失: ruleExplore（整块缺失）
// 缺失: bookUrlPattern（详情页URL正则）
// 缺失: jsLib（全局JS库）
// 缺失: coverDecodeJs（封面解密JS）
// 缺失: weight（智能排序权重）
```

**CodingKeys 也不映射嵌套结构**，导入真实书源 JSON 后规则字段全为 `nil`。

### 4.2 规则解析链（关键逻辑缺陷）

**问题1：`@` 分割过于简单**

```swift
// 当前实现（有缺陷）
let segments = trimmed.components(separatedBy: "@")
// 问题：".title@text" 会被切成 [".title", "text"]
// 问题："@XPath://div" 会被切成 ["", "XPath://div"]
```

Android `RuleAnalyzer` 用状态机识别 JS 块、引号内容后再分割，iOS 无此处理。

**问题2：CSS 属性提取不支持**

Android 的 `AnalyzeByJSoup` 解析 `"div.content@href"` 会提取 `href` 属性。iOS `HTMLParser.text()` 只调用 `.text()`，`@href`、`@src`、`@html`、`@outerHtml` 等均不支持，是**高频缺失项**（80%+ 的书源规则用到属性提取）。

**问题3：URL 模板不完整**

```swift
// 当前实现（仅支持 {{key}}）
let finalUrl = searchUrlTemplate.replacingOccurrences(of: "{{key}}", with: ...)
// 缺失: {{page}}, {{variable.xxx}}, encode, POST body 模板, 动态 Header 表达式
```

### 4.3 JS 引擎差异

Android 使用 **Rhino** 引擎（完整 Java 互操作），iOS 使用 **JavaScriptCore**。

| 特性 | Android (Rhino) | iOS (JavaScriptCore) | 差距 |
|------|----------------|----------------------|------|
| java.ajax() | 完整 HTTP | 有（同步 Semaphore） | 可用 |
| java.post() | 完整 POST | 有（同步 Semaphore） | 可用 |
| java.md5/sha1 | 完整 | 有（CryptoKit） | 已覆盖 |
| java.base64 | 完整 | 有 | 已覆盖 |
| java.gzip/deflate | 有 | **无** | 缺失 |
| java.readFile/writeFile | 有 | **无** | 缺失 |
| java.queryTextContent() | 有（CSS 查询） | **无** | 缺失 |
| java.getLastChapter() | 有 | **无** | 缺失 |
| java.cacheFile() | 有 | **无** | 缺失 |
| 全局 result 变量 | 自动注入 | 有（手动注入） | 基本对齐 |
| 脚本编译缓存 | 有（CompiledScript） | **无** | 性能差距 |
| WebView JS 执行 | 有（BackstageWebView） | **无** | 缺失（部分书源依赖） |

iOS 的 `JSJavaHelper` 只实现了约 10 个方法，而 Android `JsExtensions`（1003行）提供约 60+ 个方法。

---

## 五、架构问题

### 5.1 BookSource 模型设计根本性错误

书源模型采用平铺字段而非嵌套规则对象，导致：
- 无法正确导入/导出真实书源 JSON
- 数据库列过于零散，缺少对 Android `BookSource` 完整字段的对应
- 后续维护时扩展成本高

**建议**：完全重写为嵌套结构，通过 GRDB 的 JSON TypeConverter 存储嵌套对象，与 Android 结构保持 1:1 映射。

### 5.2 `RuleExecutor` 不区分 HTML/JSON 内容类型

Android `AnalyzeRule.setContent()` 会自动检测内容是否为 JSON（`content.toString().isJson()`），并分配对应的解析器。iOS `RuleExecutor` 强制将 `result` 转换为 `String` 后传入，当内容是 JSON 对象时失去类型信息。

### 5.3 `ReaderViewModel.loadChapters()` 方法缺失

`ReaderViewModel.setup()` 调用了 `await loadChapters()`，但该方法在文件中**不存在**，会导致编译/运行时错误。推测是开发时遗漏的 TODO。

### 5.4 `SimulationPagingView` 的翻页粒度错误

当前以**章节（Chapter）**为翻页单位，每个 `UIPageViewController` 页面是一整章。Android 版有 `TextChapterLayout`（834行）按字体/行高/屏幕尺寸将章节分割为多个物理页面。这是阅读体验的核心差距。

### 5.5 `ChapterPageViewController` 中存在代码拼写错误

```swift
// SimulationPagingView.swift 第 91 行
hostingController.view.autoresizingMask = [.flexibleWidth, .autoresizingMask]
// 应为: [.flexibleWidth, .flexibleHeight]
// .autoresizingMask 不是有效的 UIView.AutoresizingMask 成员
```

### 5.6 `LegadoJSEngine` 使用单例共享上下文（线程不安全）

`LegadoJSEngine.shared` 持有单一 `JSContext`，`SearchViewModel` 在并发 `TaskGroup` 中同时调用多个书源的 JS 规则，会导致 `JSContext` 竞争访问，引发崩溃或结果错误。

### 5.7 `DatabaseManager` 初始化失败使用 `fatalError`

```swift
fatalError("❌ [DB Error]: Failed to initialize database: \(error)")
```

生产环境中数据库迁移失败（如磁盘满）会直接崩溃，应改为错误状态处理。

### 5.8 `dbPool` 声明为隐式解包可选（`!`）

```swift
var dbPool: DatabasePool!
```

在多处 DAO 方法中未做 nil 检查，任何使用 `db` 属性前调用若初始化失败则崩溃。

### 5.9 搜索结果封面图未加载

`SearchResultRow` 使用占位矩形，不显示真实封面图，而 `SearchResult` 模型中已有 `coverUrl` 字段。

### 5.10 书源导入使用 Alert TextField（体验极差）

`BookSourceListView` 的导入功能弹出一个系统 Alert 并提供单行 TextField，实际书源 JSON 有数百行，无法粘贴。应改用全屏编辑器或文件选择器。

---

## 六、总体评估

### 综合评分

| 维度 | 评分 | 说明 |
|------|------|------|
| 基础架构 | 7/10 | MVVM + async/await + GRDB 选型合理，分层清晰 |
| 书源规则引擎 | 3/10 | 核心解析逻辑存在多处根本性缺陷 |
| 书源兼容性 | 2/10 | 平铺模型导致真实书源 JSON 无法正确解析 |
| 阅读器体验 | 5/10 | 仿真翻页框架有但缺乏页内分页 |
| UI 完整度 | 6/10 | 主流程界面齐全，管理类功能缺失 |
| 测试覆盖 | 4/10 | 有单元测试框架，覆盖有限 |
| 生产可用性 | 1/10 | 无法加载真实书源章节，核心流程不通 |

### 最紧迫的修复优先级

**P0 — 阻塞核心流程（必须立即修复）：**
1. 修复 `BookSource` 模型以支持嵌套 JSON 格式（`ruleSearch`、`ruleToc`、`ruleContent`、`ruleBookInfo`）
2. 实现 `ReaderViewModel.loadChapters()` 方法（目录网络抓取）
3. 修复 `RuleParser.parseChain()` 的 `@` 分割逻辑（状态机方式）
4. 在 `HTMLParser` 中支持 `selector@attr` 属性提取语法
5. 修复 `LegadoJSEngine` 并发安全问题（每个解析任务独立 JSContext）

**P1 — 严重影响书源兼容性：**
6. 扩展 `AnalyzeUrl` 支持完整的 URL 模板（`{{page}}`、`{{variable}}`、POST body）
7. 实现 `ContentRule.nextContentUrl` 正文翻页
8. 实现 `TocRule.nextTocUrl` 目录翻页
9. 补全 `JSJavaHelper` 中高频缺失的 java API（gzip、queryTextContent 等）

**P2 — 体验完善：**
10. 实现章节内分页（`TextChapterLayout` 等价实现）
11. 书源编辑界面
12. 净化规则管理界面
13. 发现（Explore）功能

### 结论

当前 iOS 实现建立了合理的架构骨架，UI 主流程完整，但**书源规则引擎的核心逻辑存在根本性缺陷**：书源 JSON 格式不兼容、规则解析链存在错误分割、CSS 属性提取缺失、AnalyzeUrl 模板不完整。这些问题导致几乎所有真实书源都无法正常工作。项目处于"架构成型但核心引擎不可用"的阶段，距离生产可用还需要至少完成 P0 和 P1 优先级的全部修复工作。
