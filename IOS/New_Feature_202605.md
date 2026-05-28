# New Feature 202605 — iOS Legado 功能开发追踪

> **冷启动必读**：每次对话开始，先读本文件 + `memory/reader_bugs_20260527.md` + `memory/reader_feature_gap.md`，了解当前工作状态后再继续。
>
> **维护规则**：用户每次提出新增/修改需求，立刻追加到本文件对应区域，状态标 ⬜，实现后更新为 ✅。

---

## 已完成功能

### F1 · 书架 `fullScreenCover(item:)` 竞态修复
- **目标**：点击书架书籍后阅读器空白，`isPresented` + `selectedBook` 存在时序竞态
- **实现**：改用 `fullScreenCover(item: $selectedBook)`，闭包直接接收非空 book
- **状态**：✅ 已完成

### F2 · 阅读器完整重构（纯 SwiftUI TabView）
- **目标**：替换 UIPageViewController + UIHostingController 方案，消除零尺寸渲染问题
- **实现**：ReaderView 用 `TabView(.page)` + 三段式点击区
- **状态**：✅ 已完成

### F3 · 阅读器排版设置扩展
- **目标**：对标 Android ReadStyleDialog，新增字间距/段间距/上下边距/翻页模式/页眉/屏幕常亮/繁体/朗读语速
- **实现**：ReaderSettings 新增字段，ReaderSettingsSheet 完整重写
- **状态**：✅ 已完成

### F4 · 阅读器 Bug 批量修复（B1-B7）
- **目标**：菜单无法关闭/上下章按钮无效/进度不保存/空白过大/主题乱跳等6个用户反馈
- **实现**：见 `memory/reader_bugs_20260527.md`
- **状态**：✅ 全部已完成

### F5 · 预缓存并行化
- **目标**：后台静默预缓存后续 N 章（默认10），翻章秒开
- **实现**：prefetch 改为每章独立 Task 并发下载；设置里可调 1-50
- **状态**：✅ 已完成

### F6 · 三点菜单（刷新/缓存全本）
- **目标**：阅读器顶部三点菜单，刷新当前章节 + 缓存全本（带进度）
- **实现**：Menu 组件 + refreshCurrentChapter / cacheAllChapters
- **状态**：✅ 已完成

### F7 · 书源管理从文件导入
- **目标**：三点菜单新增"从文件导入"，支持设备内 JSON/TXT 文件
- **实现**：SwiftUI fileImporter，支持 UTF-8/GBK 双编码，SecurityScopedResource
- **状态**：✅ 已完成

### F8 · 书源管理清空书源
- **目标**：三点菜单"清空书源"，只清书源不影响书架
- **实现**：DatabaseManager.deleteAllBookSources() + 确认弹窗
- **状态**：✅ 已完成

### F9 · 书源检测功能
- **目标**：检测书源连接状态（三种范围），显示网速（绿/红），失败/慢速的自动处理
- **实现**：BookSourceCheckView.swift（新文件），checkState 字段，DB v7 迁移
  - CheckScope: 未测/未测+失败/全部
  - InvalidAction: 禁用或删除
  - SlowAction: 保持或禁用
  - 最多5并发，8s超时，实时进度列表
  - BookSourceRow 网速徽章：正常绿/慢速红/失败红/未测不显示
- **状态**：✅ 已完成

### F10 · 阅读进度页码保存/恢复
- **目标**：退出阅读再进入，恢复到上次阅读的页码（之前只保存章节号）
- **实现**：durChapterPos 存页码；nextPage/prevPage 调 savePageProgress()；paginateCurrentChapter 恢复
- **状态**：✅ 已完成

### F11 · 分页器与渲染一致性修复（底部空白）
- **目标**：\n\n 段落分隔符在大字号下产生巨大空行，导致每页填充率仅50%
- **实现**：分页前 \n\n→\n，用 paragraphSpacing=12pt 替代；分页器/渲染器共用同一 NSAttributedString
- **状态**：✅ 已完成

---

## 进行中 / 待实现

### F12 · 书源行内操作菜单（三点按钮）
- **目标**：每个书源右侧（启用开关与">"之间）加三点菜单，含：
  - **置顶**：将当前书源移至列表顶部（修改 customOrder 字段）
  - **登录**：打开书源登录页面（loginUrl），获取 Cookie
  - **编辑**：复用现有 BookSourceEditView（替代">"）
  - **浏览**：打开书源网站（bookSourceUrl）用内置浏览器
  - **调试**：✅ 已实现 → 打开 ExploreDebugView 调试发现规则（含"修复"按钮）
  - **禁用发现**：切换 enabledExplore（不在发现页显示）
  - **删除**：删除当前书源
- **当前进度**：三点菜单按钮已加入，**调试**功能已完整实现，其余项目仍待实现
- **ExploreDebugView 功能说明**：
  - 五步管线诊断（exploreUrl解析 → URL解析 → 网络请求 → ruleExploreList → item字段提取）
  - Step 3 通过后解锁"修复"按钮，自动分析响应体并填入空白规则字段
  - "修复"按钮详见 `.planning/notes/explore-debug-notes.md`
- **状态**：🔄 部分实现（调试已完成，其他项待续）

### F13 · 书源列表拖拽排序
- **目标**：用户可调整书源前后顺序
- **方案选择**（推荐 A）：
  - **方案A（推荐）**：List 的 `.onMove` modifier — SwiftUI 原生，手指长按自动出现拖拽手柄，持久化 customOrder
  - **方案B**：自定义三横按钮（DragGesture 实现），UI 更复杂
- **实现要点**：
  - `BookSourceViewModel` 加 `moveSource(from:to:)` 方法
  - `EditButton` 在导航栏激活编辑模式
  - 移动后批量更新 customOrder → saveBookSources
- **状态**：⬜ 待实现

---

## 待实现（Priority 2 — 来自 Android 功能差距）

见 `memory/reader_feature_gap.md`：
- 书内搜索
- 书签功能
- 图片显示
- 笔记/划线
- 分享
