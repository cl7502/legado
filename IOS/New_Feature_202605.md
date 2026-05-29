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

### F12 · 书源行内操作菜单（三点按钮）✅ 已完成
- **置顶**：✅ customOrder = min - 1，移至列表顶部
- **登录**：⬜ 暂缓（需 WebView + Cookie 注入，复杂度高）
- **编辑**：✅ sheet 打开 BookSourceEditView，替代原 ">" 行导航
- **浏览**：✅ SFSafariViewController 打开 bookSourceUrl
- **调试**：✅ ExploreDebugView（含修复按钮）
- **禁用发现/启用发现**：✅ 切换 enabledExplore，标签随状态翻转
- **删除**：✅ 三点菜单内删除
- **状态**：✅ 已完成（登录功能暂缓）

### F13 · 书源列表拖拽排序 ✅ 已完成
- **实现**：List `.onMove` + 导航栏 `EditButton`；`moveSource(from:to:)` 重排 customOrder
- **状态**：✅ 已完成

---

## 待实现（Priority 2 — 来自 Android 功能差距）

### P2-1 · 分享 ✅ 已完成
- **实现**：阅读器三点菜单加 `ShareLink`，分享书籍 URL + 书名
- **状态**：✅ 已完成

### P2-2 · 书签功能 ✅ 已完成
- **实现**：Bookmark 模型 + DB v8 迁移 + DAO；阅读器三点菜单「添加书签」/「书签列表」
- **状态**：✅ 已完成

### P2-3 · 书内搜索 ✅ 已完成
- **实现**：BookSearchView 本地搜索已缓存章节，关键词高亮，最多200条，点击跳转
- **状态**：✅ 已完成

### P2-4 · 图片显示 ✅ 已完成
- **实现**：BookContentParser 保留 `<img>` 为 `⟨IMG:url⟩` 标记；MixedContentView 混合渲染文字+图片
- **状态**：✅ 已完成

### P2-5 · 笔记/划线 ✅ 已完成
- **实现**：BookHighlight 模型 + DB v9 + iOS 16 edit menu 4色高亮 + HighlightListView
- **状态**：✅ 已完成

### 渲染引擎 · TextKit 2 升级 ✅ 已完成
- **实现**：ChapterPaginator 改用 NSTextLayoutManager；UITextView(usingTextLayoutManager: true) 渲染
- **收益**：CJK 禁则、分页/渲染引擎一致、消除底部空白偏差
- **状态**：✅ 已完成
