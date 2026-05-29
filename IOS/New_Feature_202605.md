# New Feature 202605 — iOS Legado 功能开发追踪

> **冷启动必读**：每次对话开始，先读本文件 + `memory/reader_bugs_20260527.md` + `memory/reader_feature_gap.md`，了解当前工作状态后再继续。
>
> **维护规则**：用户每次提出新增/修改需求，立刻追加到本文件对应区域，状态标 ⬜，实现后更新为 ✅。

---

## 已完成功能

### F1 · 书架竞态修复 ✅
### F2 · 阅读器 TabView 重构 ✅
### F3 · 阅读器排版设置扩展 ✅
### F4 · 阅读器 Bug 批量修复（B1-B7）✅
### F5 · 预缓存并行化 ✅
### F6 · 阅读器三点菜单（刷新/缓存全本）✅
### F7 · 书源管理从文件导入 ✅
### F8 · 书源管理清空书源 ✅
### F9 · 书源检测功能 ✅
### F10 · 阅读进度页码保存/恢复 ✅
### F11 · 分页器与渲染一致性修复 ✅

### F12 · 书源行内三点菜单 ✅（登录暂缓）
- 置顶 / 编辑（sheet）/ 浏览（SFSafariViewController）/ 调试 / 禁用发现 / 删除 均已实现
- ExploreDebugView：五步管线诊断 + 智能修复按钮（JSON/HTML 结构推断）

### F13 · 书源列表拖拽排序 ✅（`.onMove` + `EditButton`）

### P2-1 · 分享 ✅（`ShareLink`）
### P2-2 · 书签 ✅（DB v8 + BookmarkListView）
### P2-3 · 书内搜索 ✅（实时搜索 + 关键词高亮，仅已缓存章节）
### P2-4 · 正文内嵌图片显示 ✅（`⟨IMG:url⟩` 标记 + MixedContentView + CoverImageView）
### P2-5 · 高亮/划线 ✅（DB v9 + iOS 16 edit menu 4色 + HighlightListView）

### 渲染引擎 · TextKit 2 升级 ✅
- `ChapterPaginator`：`NSTextLayoutManager` 替代 `CTFramesetter`
- `TextKit2TextView`：`UITextView(usingTextLayoutManager:)` 统一引擎
- 收益：CJK 禁则、消除分页/渲染不一致、支持文字选择

### 书源解析引擎修复 ✅（26 项，见 IOS_Issue_20260525.md）
### 发现功能 HTML 解析修复 ✅
- `class.xxx → .xxx`、`#imgload` 剥离、`@_src` 懒加载、`isAttributeKeyword` 修正
- `java.md5Encode()` 补全、JS 驱动书源跳过预取、`requestSync` 死锁修复
- iOS 16 部署目标升级

---

## 待实现 — 明确需求

### F12-登录 · 书源登录功能 ⬜
- **目标**：书源三点菜单"登录"，打开书源 `loginUrl`，WebView 登录后自动提取 Cookie/Token
- **复杂度**：高
- **实现要点**：
  - `WKWebView` + `WKHTTPCookieStore` 拦截 Cookie
  - `loginCheckJs` 检测登录状态（JS 注入）
  - Cookie 持久化到 `CookieManager`，后续请求携带
- **状态**：⬜ 待实现

### 正文内链接点击 ⬜
- **目标**：正文 `<a href>` 可点击（书内跳转章节或打开外链）
- **复杂度**：小
- **实现要点**：`BookContentParser` 提取链接标记；`TextKit2TextView` 通过 `UITextViewDelegate.textView(_:shouldInteractWith:in:)` 处理
- **状态**：⬜ 待实现（推荐优先实现，工作量小）

### 自定义字体 ⬜
- **目标**：用户可导入 TTF/OTF 字体文件并在阅读器使用
- **复杂度**：中
- **实现要点**：
  - 设置页加"导入字体"（`fileImporter` + `CTFontManagerRegisterFontsForURL`）
  - `ReaderSettings.fontName` 存储选中字体名
  - `ChapterPaginator` + `TextKit2TextView` 从设置读取字体
- **状态**：⬜ 待实现

### 文字颜色自定义 ⬜
- **目标**：独立于主题的正文颜色 color picker
- **复杂度**：小
- **实现要点**：`ReaderSettings.customTextColor: Color?`；`ReaderSettingsSheet` 加 `ColorPicker`；优先于主题默认色
- **状态**：⬜ 待实现

### 音量键翻页 ⬜
- **目标**：按音量键翻页（iOS 需通过 AVAudioSession 监听音量变化实现）
- **复杂度**：中
- **实现要点**：
  - 阅读模式注册 `AVAudioSession` 音量变化通知
  - 截获事件 → `nextPage()` / `prevPage()`，并还原音量
  - 设置里开关
- **状态**：⬜ 待实现

### 章节缓存策略强化 ⬜
- **目标**：对标 Android 三层缓存 + 失败重试
- **复杂度**：中
- **实现要点**：
  - 当前仅缓存当前章 + 下一章（两层），无失败重试
  - 加入指数退避重试（最多 3 次）
  - 缓存队列改为优先级队列（当前章 > 下一章 > 预缓存）
- **状态**：⬜ 待实现

### WebDAV 云同步 ⬜
- **目标**：书架/进度/书签/高亮通过 WebDAV 多设备同步
- **复杂度**：大
- **实现要点**：
  - 设置页加 WebDAV 配置（URL/用户名/密码）
  - 导出：DB → JSON → 上传 WebDAV
  - 导入：下载 JSON → 合并本地 DB（时间戳冲突处理）
  - 阅读进度实时同步（关闭章节时触发）
- **状态**：⬜ 待实现

### 自动翻页（定时）⬜
- **目标**：按设定速度自动翻页
- **复杂度**：中
- **实现要点**：`Timer` 定时触发 `nextPage()`；设置里调速；点屏暂停
- **状态**：⬜ 待实现

### 双页模式（iPad）⬜
- **目标**：iPad 横屏左右双列显示
- **复杂度**：大
- **实现要点**：`UIDevice` + 横屏检测 → `HStack` 两个 `ReaderPageView`；分页器按半屏宽度计算
- **状态**：⬜ 待实现

---

## 待强化 — 发现调试器（ExploreDebugView）

详见 `.planning/notes/explore-debug-notes.md`：

| 项目 | 优先级 |
|---|---|
| Step 3 响应完整展示（当前截断 300 字符） | 中 |
| 候选数组多选，用户手动选择而非系统推断 | 中 |
| `ruleExploreNoteUrl` URL 模板推断 | 低 |
| 非标准字段名值类型启发（URL / 中文 / 数字）| 低 |
| 一键对比 Android 版书源规则 | 低 |

---

## 技术债

| 项目 | 说明 |
|---|---|
| 书内搜索范围 | 只搜已缓存章节，未缓存需先下载 |
| 高亮定位精度 | 字体变化重新分页后，字符偏移可能轻微漂移 |
| TextKit 2 图文混排断页 | 含 `⟨IMG:url⟩` 章节断页用比例映射，精确度待提升 |
| `ruleReview` 书评规则 | BookSource 模型有字段但未接入 UI |

---

## 已知失效书源（非代码问题）

| 书源 | 原因 | 建议 |
|---|---|---|
| 看书神app | `apitt.kanshushenapp.com` API 已关闭 | 禁用或删除 |
| 🌾书阁 | 模拟器 DNS 无法解析（真机可能正常） | 真机测试 |
| 阅读助手 | 模拟器 DNS 失败（代码已修复，真机应正常）| 真机测试 |
