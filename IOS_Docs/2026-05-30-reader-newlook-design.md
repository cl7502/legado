# 阅读器 NewLook 设计规格（v2）

**日期**：2026-05-30
**分支**：IOS-NewLook
**状态**：待实现
**实现顺序**：A → B → E → C → D

---

## 概览

对阅读器进行全面重设计，涵盖五个模块：状态栏布局（A）、工具栏按钮（B）、换源页面（C）、朗读面板（D）、设置重组与自定义主题（E）。

---

## 模块 A：阅读状态栏重布局

### A1 顶部 Header

**文件**：`ReaderView.swift` → `ReaderPageView`（约第 291–313 行）

**修改前**：`[时间][Spacer][X/Y章][电量%]`（各项受开关控制）

**修改后**：

```
[ ‹  第3章 凤凰涅槃·归来时…… ]     [ 3 / 120章 ]
```

| 区域 | 内容 | 说明 |
|---|---|---|
| 左侧 | `chevron.left` + `"第N章 章节标题"` | **始终显示，不受任何开关控制**；整个左侧可点击 → `dismiss()` 返回书架 |
| 右侧 | `当前章序号 / 总章数`（如"3 / 120章"） | 受 `showHeaderProgress` 开关控制，语义和行为不变 |

**规则**：
- 章节标题超长时单行截断加 `…`，左侧总宽度不超过屏幕宽度的 60%
- `showHeaderTime` 开关**废弃**（时间已移至底部，头部左侧固定为章节导航）；在"页眉信息"设置中移除该 Toggle，仅保留"显示章节进度"和"显示电量"两项
- 右侧电量百分比（`showHeaderBattery`）**保留不变**

### A2 底部 Footer

**文件**：`ReaderView.swift` → `ReaderPageView`（约第 280–285 行）

**修改前**：`[Spacer][1 / 10]`

**修改后**：

```
[ 🔋84%    21:30 ]                    [ 3 / 10 ]
```

| 区域 | 内容 |
|---|---|
| 左侧 | `BatteryIconView`（自绘）+ 两个 em 空格（`\u{2003}\u{2003}`）+ `HH:mm` 时间 |
| 右侧 | 现有 `pageLabel`（当前页/总页数），格式和对齐方式不变 |

### A3 BatteryIconView 规格

**绘制方式**：纯 SwiftUI Shape/Canvas，不依赖图片资源

- **尺寸**：28 × 14pt（与 footer 文字基线对齐）
- **外轮廓**：圆角矩形（圆角 2pt）+ 右侧电极凸起（宽 3pt，高 8pt）
- **内填充**：按 `batteryLevel`（0.0–1.0）比例从左向右填充
  - 电量 > 20%：填充色 = `textColor.opacity(0.6)`
  - 电量 ≤ 20%：填充色 = `.red`
- **充电状态**：填充色改为绿色，百分比数字改为 `⚡`（`bolt.fill` SF Symbol，11pt）；电量仍按实际比例填充
- **叠加数字**：`"\(Int(batteryLevel * 100))%"`，字号 9pt，颜色 `textColor.opacity(0.8)`，居中对齐
- **整体颜色**：轮廓色 = `textColor.opacity(0.5)`

**刷新机制（低损耗）**：
- View 出现时：`UIDevice.current.isBatteryMonitoringEnabled = true`
- 监听 `UIDevice.batteryLevelDidChangeNotification` 和 `UIDevice.batteryStateDidChangeNotification`，两者任一触发时刷新电量显示
- View 消失时：`UIDevice.current.isBatteryMonitoringEnabled = false`
- 时间显示：初始化时计算到下一分钟整点的剩余秒数，`DispatchQueue.main.asyncAfter` 触发首次更新，此后每 60 秒更新（递归调度，精准对齐分钟边界）
- 现有 `BatteryMonitor` 类增加 `isCharging: Bool` 属性（读取 `UIDevice.current.batteryState == .charging || .full`）

---

## 模块 B：菜单栏新增工具按钮

**触发条件**：点击屏幕中央弹出菜单

**文件**：`ReaderView.swift` → `ReaderMenuView`（顶部工具栏区域）

**修改前**：`[Spacer][ ··· ]`

**修改后**：`[Spacer][ 换源 ][ 🔖 ][ ··· ]`

### B1 换源按钮

- **图标**：`arrow.triangle.2.circlepath.circle`（24pt，与三点按钮同尺寸）
- **点击**：以 `.sheet` 方式打开「选择来源」页面（见模块 C）

### B2 书签按钮

- **图标**：`bookmark`（未标记）/ `bookmark.fill`（当前页已有书签时）
- **状态来源**：`ReaderViewModel` 新增 `isCurrentPageBookmarked: Bool`，在章节或页码变化时重算（查询 DB 匹配当前 `bookUrl + chapterIndex + pageIndex`）
- **点击**：直接调用现有 `addBookmark()` 方法；执行后显示 `Toast("书签已添加", duration: 1.5s)`，图标切换为 `bookmark.fill`

---

## 模块 C：选择来源页面（换源）

**文件**：
- 新建 `Features/Reading/Views/SourceSelectionView.swift`
- 新建 `Features/Reading/ViewModels/SourceSelectionViewModel.swift`

### C1 页面结构

```
[  选择来源                              ✕  ]
─────────────────────────────────────────────
✓  猫眼看书（优++）   第3章 ✅ 可用   [当前使用]
   笔趣阁             第3章 ✅ 可用
   番茄小说           搜索中…        [进度圈]
   QQ阅读             第3章 ❌ 无此章  [灰色]
   起点中文           未找到此书      [灰色]
─────────────────────────────────────────────
```

**分组顺序**（自上而下）：
1. 当前使用书源（✓ 标记，置顶）
2. 章节可用书源（可点击）
3. 章节不可用书源（灰色，不可点击）
4. 未找到此书的书源（灰色，折叠在"展开更多"下）

### C2 搜索逻辑

1. Sheet 打开时立即触发：遍历全部已启用书源，每个书源独立并发 Task
2. 搜索关键词：当前书的 `book.name`
3. 每个书源搜索完成后**立即追加**到列表（流式更新，`@Published` 驱动）
4. 找到匹配书名 → 进一步验证：当前 `chapterIndex` 在该书源目录中是否存在
5. 搜索超时：单个书源 10 秒超时，超时显示"请求超时"（归入灰色组）

### C3 切换逻辑

- 点击可用书源 → `Alert("切换到 XXX？", message: "当前阅读进度将保留，章节内容将重新加载。")`
- 确认后：
  1. 更新 `book.origin` / `book.originName` 并写入 DB（`DatabaseManager.shared.saveBook`）
  2. 清空当前已缓存的章节内容（`viewModel.clearCache()`）
  3. 重新从新书源加载目录（`viewModel.loadChapters()`）
  4. 从当前 `chapterIndex` 开始按现有缓存策略预缓存
  5. 关闭 Sheet，继续阅读（章节内容加载期间显示加载动画）

---

## 模块 D：朗读面板重设计

### D1 行为变化

朗读面板**取代**底部菜单中的原功能按钮行（朗读/目录/翻页切换/主题/设置）：

| 场景 | 行为 |
|---|---|
| 点击"朗读"按钮 | 立即开始朗读，**按钮行变形为朗读面板**（动画过渡） |
| 关闭菜单 | 朗读继续，面板随菜单消失 |
| 再次打开菜单且朗读中 | 直接显示朗读面板（跳过原按钮行） |
| 点击"退出朗读" | 停止朗读，面板**变形回**原功能按钮行 |

**注意**：朗读激活时，原"朗读/目录/翻页/主题/设置"五个按钮**完全隐藏**，由朗读面板替代；这五个按钮仍可通过关闭菜单再点击朗读图标（此时图标为 `headphones.circle.fill` 高亮）来切换回面板。

### D2 面板结构

```
┌─────────────────────────────────────────────┐
│  语速   慢 ────●──── 快           1.2x      │
├─────────────────────────────────────────────┤
│  发音   [ 普通话 - Tingting (增强版) ▼ ]     │
│         下载更多声音 →（跳转系统设置）       │
├─────────────────────────────────────────────┤
│  定时   [5分] [15分] [30分] [60分] [自定义]  │
├─────────────────────────────────────────────┤
│  [ 退出朗读 ]              [ ‖ 暂停 ]        │
└─────────────────────────────────────────────┘
```

### D3 各控件规格

**语速**：
- Slider（0.25–2.0），右侧实时显示倍速文字（`"\(String(format: "%.1f", rate))x"`）
- 绑定 `ReaderSettings.ttsRate`，拖动结束后（`onEditingChanged: false`）重启当前句朗读

**发音**：
- `Picker` 列出 `AVSpeechSynthesisVoice.speechVoices()` 过滤 `language.hasPrefix("zh")` 的结果
- 显示格式：`"普通话 - Tingting (增强版)"` —— 语言区域 + 名称 + 质量级别
- 默认选项：`nil`（系统默认），列表第一项为"系统默认"
- 选择保存到 `ReaderSettings.ttsVoiceIdentifier: String?`（存 `voice.identifier`）
- 底部链接："下载更多声音 →"，跳转到 App 设置中的辅助功能页
  - 优先尝试 `UIApplication.openSettingsURLString`（通用设置）
  - 备注：无法直接跳转到发音子页，用 `UIApplication.openSettingsURLString` 打开 App 设置页已足够

**定时**：
- 单选按钮组（`5 / 15 / 30 / 60 / 自定义`），选中时背景高亮
- "自定义" → `Alert` 含文本输入框（键盘类型 `.numberPad`，范围 1–999 分钟）
- 定时倒计时由 `TTSManager` 内部管理（`remainingSeconds: Int?`），到 0 时自动 `stop()`
- 未选定时无限时（`nil`）

**退出朗读**：调用 `viewModel.stopTTS()`，按钮行恢复为原五个功能按钮

**暂停/继续**：根据 `TTSManager.isPlaying` 切换图标：`pause.circle.fill` / `play.circle.fill`；点击调用 `pause()` / `resume()`

**新增 TTSManager 属性**：
- `isPlaying: Bool`（当前是否在朗读且未暂停）
- `remainingSeconds: Int?`（定时剩余秒数，nil = 无定时）
- `selectedVoice: AVSpeechSynthesisVoice?`（从 `ReaderSettings.ttsVoiceIdentifier` 读取）

---

## 模块 E：设置重组 + 自定义主题

### E1 阅读器底部"设置"按钮行为变化

- **原**：打开 `ReaderSettingsSheet`（含字体排版/主题/页眉信息/朗读/高级/缓存）
- **新**：仍打开设置弹窗，但弹窗**简化**为仅含：字体排版 + 主题（含自定义主题）

弹窗底部增加入口：**「更多阅读设置 →」**，点击后在弹窗内 push 或以新 Sheet present「阅读偏好」页面（内容见 E3）。

### E2 简化后的设置弹窗（ReaderSettingsSheet）

**保留**：

```
┌─ 字体排版 ─────────────────┐
│ 字号 / 行高 / 字间距 / 段间距│
└─────────────────────────────┘
┌─ 主题 ──────────────────────┐
│ ○羊皮 ○深色 ○护眼 ○清新 ＋自定义│
└─────────────────────────────┘
          更多阅读设置 →
```

**移除**：亮度 Slider、朗读语速、页眉信息、高级、缓存

### E3 自定义主题

**新增 ReaderTheme**：`id = "custom"`，名称"自定义"

- 色块显示：44×44pt 圆，填充 `customBgColor`，未设置时显示线性渐变
- 点击选中"自定义" → 在 Section 下方展开两行 `ColorPicker`：

```
│ 背景色  [色块预览] [ColorPicker]   │
│ 文字色  [色块预览] [ColorPicker]   │
```

- 改色后实时生效（`themeId` 自动切换为 `"custom"`）
- 关闭弹窗自动保存

**新增 ReaderSettings 字段**：

```swift
var customBgColor: Color   // 默认 Color(hex: "#F5E6C8")
var customTextColor: Color // 默认 Color(hex: "#2C1810")
```

**持久化方案**：`Color` ↔ `String` 通过现有项目中的 `Color(hex:)` 扩展（若无则新增），存入 `UserDefaults` 为 `"#RRGGBB"` 格式。

### E4 阅读偏好页面

**访问路径**：设置弹窗底部「更多阅读设置 →」

**内容**：

```
┌─ 布局预设 ─────────────────┐
│   [ 正常 ]  [ 舒适 ]  [ 紧凑 ]│
│   （字号/行高/边距预设组合）  │
└─────────────────────────────┘
┌─ 亮度 ─────────────────────┐
│  ☀️ ────●────────────── 🌙  │
│  （控制 UIScreen.main.brightness）│
└─────────────────────────────┘
┌─ 页眉信息 ─────────────────┐
│  显示章节进度    [ 开/关 ]  │  ← showHeaderProgress
│  显示电量        [ 开/关 ]  │  ← showHeaderBattery（右上角%）
└─────────────────────────────┘
┌─ 高级 ─────────────────────┐
│  屏幕常亮        [ 开/关 ]  │
│  繁体中文        [ 开/关 ]  │
└─────────────────────────────┘
┌─ 缓存 ─────────────────────┐
│  预缓存章节数   [-] 10章 [+]│
└─────────────────────────────┘
```

**注意**：「正常/舒适/紧凑」三档预设需在实现阶段确认现有代码中是否已存在；若不存在，则定义为字号/行高/边距的预设值组合（正常=默认值，舒适=略大行高，紧凑=减小边距），实现为三个 Button 设置多个 settings 字段。

`showHeaderTime` 开关从页眉信息中**移除**（章节导航始终显示，不可关闭）。

---

## 文件变更清单

| 操作 | 文件 | 说明 |
|---|---|---|
| 修改 | `ReaderView.swift` | Header 重布局、Footer 重布局、菜单按钮、TTS 面板变形逻辑、设置入口 |
| 新建（内嵌） | `BatteryIconView`（可提取至独立文件） | 自绘电池图标 |
| 修改 | `ReaderSettings.swift` | 新增 customBgColor/customTextColor/ttsVoiceIdentifier；废弃 showHeaderTime |
| 新建 | `SourceSelectionView.swift` | 换源选择页面 |
| 新建 | `SourceSelectionViewModel.swift` | 换源并发搜索逻辑 |
| 修改 | `TTSManager.swift` | 新增 isPlaying/remainingSeconds/selectedVoice |
| 修改 | `ReaderViewModel.swift` | 新增 isCurrentPageBookmarked；换源执行逻辑；stopTTS() |
| 修改/新建 | App Settings 相关 View | 新增「阅读偏好」页面（或扩展现有 SettingsView） |
| 可选提取 | `BatteryIconView.swift` | 若 ReaderView.swift 过大则独立文件 |

---

## 不在本次范围内

- 第三方 TTS 引擎（后续独立功能）
- 朗读后台播放 / 控制中心集成
- 书签跨设备同步
- 换源后历史缓存章节的智能复用

---

## 实现注意事项（给开发者）

1. `ReaderView.swift` 当前已超 800 行，建议在修改前将 `ReaderMenuView`、`ReaderSettingsSheet`、`BatteryIconView` 提取为独立文件，降低合并冲突风险
2. 电池监听必须在视图 `onAppear`/`onDisappear` 中配对开关，避免内存泄漏
3. 换源逻辑涉及书源 URL 结构差异，章节索引匹配依赖标题相似度，实现时需处理未匹配情况（降级到第一章）
4. 自定义主题的 ColorPicker 在 iOS 16+ 才支持 `supportsOpacity: false` 参数，iOS 15 需另行处理
5. "正常/舒适/紧凑"预设在实现前需读取现有代码确认是否已存在
