# 阅读器 NewLook — Plan B+E：工具栏按钮 + 设置重组

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在菜单工具栏加入"换源"和"书签"快捷按钮；将设置弹窗精简为字体排版+主题，新增自定义主题（背景色+文字色），原有页眉信息/高级/缓存/亮度迁移到独立"阅读偏好"页面。

**Architecture:** ReaderMenuView.topBar 增加两个 Button；ReaderSettingsSheet 删除多余 Section，新增自定义主题 ColorPicker；新建 ReadingPreferencesView 承载迁出的设置项；ReaderSettings 增加 customBgColor/customTextColor/ttsVoiceIdentifier 三个字段（Custom 主题）。

**Tech Stack:** SwiftUI ColorPicker, @AppStorage (hex string 持久化), NavigationStack/Sheet present

**前置条件：** Plan A 已完成（BatteryMonitor 已提取，ReaderMenuView 代码结构已知）

**分支：** `IOS-NewLook`

---

## 文件变更清单

| 操作 | 文件 | 说明 |
|---|---|---|
| 修改 | `App/Features/Reading/Views/ReaderView.swift` | topBar 加两个按钮；SettingsSheet 简化；增加 ReadingPreferencesView |
| 修改 | `App/Features/Reading/Models/ReaderSettings.swift` | 新增 custom 主题字段和 Color↔hex 工具 |
| 修改 | `App/Features/Reading/Models/ReaderTheme.swift` (或 ReaderSettings.swift 内) | 新增 custom ReaderTheme |

---

## Task 6：ReaderSettings 新增自定义主题字段

**Files:**
- Modify: `IOS/Legado/App/Features/Reading/Models/ReaderSettings.swift`

- [ ] **Step 6.1：在 ReaderSettings.swift 末尾追加字段和 Color 工具**

在 `ReaderSettings` class 内的 `@AppStorage` 字段区域追加：

```swift
// MARK: - 自定义主题颜色（hex string 持久化）
@AppStorage("reader.customBgColorHex")   var customBgColorHex:   String = "#F5E6C8"
@AppStorage("reader.customTextColorHex") var customTextColorHex: String = "#2C1810"
@AppStorage("reader.ttsVoiceIdentifier") var ttsVoiceIdentifier: String = ""  // 空 = 系统默认

/// 自定义背景色（从 hex 读写，保证 AppStorage 可序列化）
var customBgColor: Color {
    get { Color(hex: customBgColorHex) ?? Color(red: 0.96, green: 0.90, blue: 0.78) }
    set { customBgColorHex = newValue.toHex() ?? customBgColorHex }
}

/// 自定义文字色
var customTextColor: Color {
    get { Color(hex: customTextColorHex) ?? Color(red: 0.17, green: 0.09, blue: 0.06) }
    set { customTextColorHex = newValue.toHex() ?? customTextColorHex }
}
```

- [ ] **Step 6.2：在 ReaderSettings.swift 文件末尾（class 外）追加 Color 扩展**

```swift
// MARK: - Color hex 互转工具（用于 AppStorage 持久化）

extension Color {
    /// 从 "#RRGGBB" 或 "#RRGGBBAA" 字符串构造 Color
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s = String(s.dropFirst()) }
        guard s.count == 6 || s.count == 8,
              let value = UInt64(s, radix: 16) else { return nil }
        let r, g, b, a: Double
        if s.count == 6 {
            r = Double((value >> 16) & 0xFF) / 255
            g = Double((value >>  8) & 0xFF) / 255
            b = Double( value        & 0xFF) / 255
            a = 1.0
        } else {
            r = Double((value >> 24) & 0xFF) / 255
            g = Double((value >> 16) & 0xFF) / 255
            b = Double((value >>  8) & 0xFF) / 255
            a = Double( value        & 0xFF) / 255
        }
        self.init(red: r, green: g, blue: b, opacity: a)
    }

    /// 转换为 "#RRGGBB" 字符串（忽略透明度）
    func toHex() -> String? {
        guard let components = UIColor(self).cgColor.components, components.count >= 3 else { return nil }
        let r = Int(components[0] * 255)
        let g = Int(components[1] * 255)
        let b = Int(components[2] * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
```

- [ ] **Step 6.3：在 ReaderTheme.swift（或 ReaderSettings.swift 内）新增 custom 主题**

找到 `static let allThemes = [parchment, dark, eyeCare, fresh]` 这行，**替换为**：

```swift
/// 自定义主题占位，颜色在运行时从 ReaderSettings 读取
static func customTheme() -> ReaderTheme {
    let s = ReaderSettings.shared
    return ReaderTheme(
        id: "custom",
        name: "自定义",
        backgroundColor: s.customBgColor,
        textColor: s.customTextColor
    )
}

static let builtinThemes: [ReaderTheme] = [parchment, dark, eyeCare, fresh]

/// 含自定义主题的完整列表（每次调用以获取最新颜色）
static func allThemes() -> [ReaderTheme] {
    builtinThemes + [customTheme()]
}
```

**同步修改** `ReaderSettings.currentTheme`：

```swift
var currentTheme: ReaderTheme {
    ReaderTheme.allThemes().first { $0.id == themeId } ?? .parchment
}
```

**同步修改** `ReaderSettingsSheet` 和任何使用 `ReaderTheme.allThemes` 的地方（改为 `ReaderTheme.allThemes()`）。

- [ ] **Step 6.4：构建验证**

```bash
cd /Users/alina/Documents/Lei/legado/IOS
xcodebuild -project Legado.xcodeproj -scheme Legado \
  -destination 'platform=iOS Simulator,id=962E405B-C2DC-463C-889D-FC51D1438E83' \
  -quiet build 2>&1 | grep -E "error:|BUILD"
```

期望：`** BUILD SUCCEEDED **`

- [ ] **Step 6.5：Commit**

```bash
cd /Users/alina/Documents/Lei/legado
git add IOS/Legado/App/Features/Reading/Models/ReaderSettings.swift
git commit -m "feat(reader): ReaderSettings 新增自定义主题字段 + Color hex 工具"
```

---

## Task 7：精简 ReaderSettingsSheet + 自定义主题 UI

**Files:**
- Modify: `IOS/Legado/App/Features/Reading/Views/ReaderView.swift`（ReaderSettingsSheet，约第 609–710 行）

- [ ] **Step 7.1：替换 ReaderSettingsSheet 整体内容**

找到 `struct ReaderSettingsSheet: View {` 整个 struct，**整体替换**为：

```swift
struct ReaderSettingsSheet: View {
    @StateObject private var settings = ReaderSettings.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showCustomColorPicker = false
    @State private var showPreferences = false

    var body: some View {
        NavigationView {
            Form {
                // ── 字体排版 ─────────────────────────────────
                Section("字体排版") {
                    stepperRow(title: "字号",   value: $settings.fontSize,        range: 12...40, step: 1)
                    stepperRow(title: "行高",   value: $settings.lineSpacing,      range: 0...30,  step: 1)
                    stepperRow(title: "字间距", value: $settings.letterSpacing,    range: -3...10, step: 0.5)
                    stepperRow(title: "段间距", value: $settings.paragraphSpacing, range: 0...50,  step: 2)
                }

                // ── 主题 ─────────────────────────────────────
                Section("主题") {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible()), count: 5),
                        spacing: 12
                    ) {
                        // 内置主题
                        ForEach(ReaderTheme.builtinThemes) { theme in
                            themeCircle(theme: theme)
                        }
                        // 自定义主题
                        customThemeCircle
                    }
                    .padding(.vertical, 4)

                    // 自定义颜色选择器（选中 custom 时展开）
                    if settings.themeId == "custom" {
                        VStack(spacing: 8) {
                            ColorPicker("背景色", selection: Binding(
                                get: { settings.customBgColor },
                                set: { settings.customBgColor = $0 }
                            ), supportsOpacity: false)
                            ColorPicker("文字颜色", selection: Binding(
                                get: { settings.customTextColor },
                                set: { settings.customTextColor = $0 }
                            ), supportsOpacity: false)
                        }
                        .padding(.top, 4)
                    }
                }

                // ── 更多设置入口 ──────────────────────────────
                Section {
                    Button {
                        showPreferences = true
                    } label: {
                        HStack {
                            Text("更多阅读设置")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .foregroundColor(.primary)
                }
            }
            .navigationTitle("阅读设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .sheet(isPresented: $showPreferences) {
                ReadingPreferencesView()
            }
        }
    }

    // MARK: - 主题圆

    @ViewBuilder
    private func themeCircle(theme: ReaderTheme) -> some View {
        VStack(spacing: 4) {
            Circle()
                .fill(theme.backgroundColor)
                .frame(width: 44, height: 44)
                .overlay(
                    Circle().stroke(
                        settings.themeId == theme.id ? Color.blue : Color.clear,
                        lineWidth: 2.5
                    )
                )
            Text(theme.name)
                .font(.caption2)
                .foregroundColor(.primary)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if theme.id != "dark" { settings.preNightThemeId = theme.id }
            settings.themeId = theme.id
        }
    }

    @ViewBuilder
    private var customThemeCircle: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(
                        settings.themeId == "custom"
                            ? settings.customBgColor
                            : LinearGradient(colors: [.pink, .purple, .blue],
                                             startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .frame(width: 44, height: 44)
                    .overlay(
                        Circle().stroke(
                            settings.themeId == "custom" ? Color.blue : Color.clear,
                            lineWidth: 2.5
                        )
                    )
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(settings.themeId == "custom"
                        ? settings.customTextColor
                        : .white)
            }
            Text("自定义")
                .font(.caption2)
                .foregroundColor(.primary)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            settings.themeId = "custom"
        }
    }

    // MARK: - Stepper 行（复用原有实现，保持不变）

    private func stepperRow(title: String, value: Binding<CGFloat>,
                             range: ClosedRange<CGFloat>, step: CGFloat) -> some View {
        HStack {
            Text(title)
            Spacer()
            Button {
                if value.wrappedValue > range.lowerBound { value.wrappedValue -= step }
            } label: {
                Image(systemName: "minus.circle").foregroundColor(.blue)
            }.buttonStyle(.plain)
            Text(String(format: step < 1 ? "%.1f" : "%.0f", value.wrappedValue))
                .frame(width: 36, alignment: .center)
                .monospacedDigit()
            Button {
                if value.wrappedValue < range.upperBound { value.wrappedValue += step }
            } label: {
                Image(systemName: "plus.circle").foregroundColor(.blue)
            }.buttonStyle(.plain)
        }
    }
}
```

- [ ] **Step 7.2：构建验证**

```bash
cd /Users/alina/Documents/Lei/legado/IOS
xcodebuild -project Legado.xcodeproj -scheme Legado \
  -destination 'platform=iOS Simulator,id=962E405B-C2DC-463C-889D-FC51D1438E83' \
  -quiet build 2>&1 | grep -E "error:|BUILD"
```

- [ ] **Step 7.3：Commit**

```bash
cd /Users/alina/Documents/Lei/legado
git add "IOS/Legado/App/Features/Reading/Views/ReaderView.swift"
git commit -m "feat(reader): 精简设置弹窗 + 自定义主题 ColorPicker"
```

---

## Task 8：新建 ReadingPreferencesView

**Files:**
- Modify: `IOS/Legado/App/Features/Reading/Views/ReaderView.swift`（末尾追加新 struct）

- [ ] **Step 8.1：在 ReaderView.swift 末尾追加 ReadingPreferencesView**

在文件末尾（所有现有 struct 之后）追加：

```swift
// MARK: - ReadingPreferencesView（阅读偏好）

/// 从阅读器设置弹窗的"更多阅读设置"进入，也可从 App 设置中访问。
/// 包含：亮度、布局预设、页眉信息、高级、缓存。
struct ReadingPreferencesView: View {
    @StateObject private var settings = ReaderSettings.shared
    @Environment(\.dismiss) private var dismiss
    @State private var brightness: Double = Double(UIScreen.main.brightness)

    var body: some View {
        NavigationView {
            Form {
                // ── 布局预设 ──────────────────────────────────
                Section("布局预设") {
                    HStack(spacing: 12) {
                        presetButton(label: "正常",  fontSize: 18, lineSpacing: 8,  sideMargin: 20)
                        presetButton(label: "舒适",  fontSize: 19, lineSpacing: 12, sideMargin: 24)
                        presetButton(label: "紧凑",  fontSize: 17, lineSpacing: 6,  sideMargin: 16)
                    }
                    .padding(.vertical, 4)
                }

                // ── 亮度 ──────────────────────────────────────
                Section("亮度") {
                    HStack(spacing: 8) {
                        Image(systemName: "sun.min").font(.caption).foregroundColor(.secondary)
                        Slider(value: $brightness, in: 0.05...1.0) { _ in
                            UIScreen.main.brightness = CGFloat(brightness)
                        }
                        Image(systemName: "sun.max").font(.caption).foregroundColor(.secondary)
                    }
                }

                // ── 页眉信息 ──────────────────────────────────
                Section("页眉信息") {
                    Toggle("显示章节进度", isOn: $settings.showHeaderProgress)
                    Toggle("显示右上电量", isOn: $settings.showHeaderBattery)
                }

                // ── 高级 ──────────────────────────────────────
                Section("高级") {
                    Toggle("屏幕常亮", isOn: $settings.keepScreenOn)
                        .onChange(of: settings.keepScreenOn) { val in
                            UIApplication.shared.isIdleTimerDisabled = val
                        }
                    Toggle("繁体中文", isOn: $settings.useTraditionalChinese)
                }

                // ── 缓存 ──────────────────────────────────────
                Section("缓存") {
                    HStack {
                        Text("预缓存章节数")
                        Spacer()
                        Button {
                            settings.prefetchCount = max(1, settings.prefetchCount - 1)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.plain)
                        Text("\(settings.prefetchCount)章")
                            .frame(width: 40, alignment: .center)
                            .monospacedDigit()
                        Button {
                            settings.prefetchCount = min(50, settings.prefetchCount + 1)
                        } label: {
                            Image(systemName: "plus.circle")
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("阅读偏好")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .onAppear { brightness = Double(UIScreen.main.brightness) }
        }
    }

    // MARK: 预设按钮
    private func presetButton(label: String, fontSize: CGFloat,
                               lineSpacing: CGFloat, sideMargin: CGFloat) -> some View {
        let isActive = abs(settings.fontSize - fontSize) < 0.5
                    && abs(settings.lineSpacing - lineSpacing) < 0.5
                    && abs(settings.sideMargin - sideMargin) < 0.5
        return Button {
            settings.fontSize     = fontSize
            settings.lineSpacing  = lineSpacing
            settings.sideMargin   = sideMargin
        } label: {
            Text(label)
                .font(.subheadline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(isActive ? Color.blue : Color(.systemGray5))
                .foregroundColor(isActive ? .white : .primary)
                .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 8.2：构建验证**

```bash
cd /Users/alina/Documents/Lei/legado/IOS
xcodebuild -project Legado.xcodeproj -scheme Legado \
  -destination 'platform=iOS Simulator,id=962E405B-C2DC-463C-889D-FC51D1438E83' \
  -quiet build 2>&1 | grep -E "error:|BUILD"
```

期望：`** BUILD SUCCEEDED **`

- [ ] **Step 8.3：Commit**

```bash
cd /Users/alina/Documents/Lei/legado
git add "IOS/Legado/App/Features/Reading/Views/ReaderView.swift"
git commit -m "feat(reader): 新增 ReadingPreferencesView（阅读偏好页面）"
```

---

## Task 9：ReaderMenuView topBar 新增"换源"和"书签"按钮

**Files:**
- Modify: `IOS/Legado/App/Features/Reading/Views/ReaderView.swift`（ReaderMenuView.topBar，约第 395–425 行）

- [ ] **Step 9.1：在 ReaderMenuView 中添加状态变量**

在 `ReaderMenuView` 的 `@State` 变量区域（约第 376–384 行）追加：

```swift
@State private var showingSourceSelection = false
@State private var bookmarkAdded = false       // 用于短暂显示已添加反馈
```

- [ ] **Step 9.2：在 topBar 的三点菜单左侧插入两个按钮**

找到 `topBar` 内 `Menu { ... } label: { Image(systemName: "ellipsis.circle") }` 这段代码，在 `Menu { ... }` 的**前面**插入：

```swift
// 书签按钮
Button {
    Task {
        await addBookmark()
        withAnimation { bookmarkAdded = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation { bookmarkAdded = false }
        }
    }
} label: {
    Image(systemName: bookmarkAdded ? "bookmark.fill" : "bookmark")
        .font(.title2)
        .foregroundColor(bookmarkAdded ? .yellow : .primary)
}

// 换源按钮
Button {
    showingSourceSelection = true
} label: {
    Image(systemName: "arrow.triangle.2.circlepath.circle")
        .font(.title2)
}
```

- [ ] **Step 9.3：在 topBar 末尾的 sheet 修饰符处追加换源 sheet**

在现有 `.sheet(isPresented: $showingSettings)` 之后追加：

```swift
.sheet(isPresented: $showingSourceSelection) {
    // Plan C 实现的 SourceSelectionView，此处占位保证编译通过
    NavigationView {
        Text("换源功能（Plan C 实现）")
            .navigationTitle("选择来源")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { showingSourceSelection = false }
                }
            }
    }
}
```

- [ ] **Step 9.4：构建验证**

```bash
cd /Users/alina/Documents/Lei/legado/IOS
xcodebuild -project Legado.xcodeproj -scheme Legado \
  -destination 'platform=iOS Simulator,id=962E405B-C2DC-463C-889D-FC51D1438E83' \
  -quiet build 2>&1 | grep -E "error:|BUILD"
```

期望：`** BUILD SUCCEEDED **`

- [ ] **Step 9.5：模拟器视觉验证**

安装并启动 App，进入阅读器，点击屏幕中央弹出菜单，验证：
- [ ] 右上角从左到右：换源图标 → 书签图标 → 三点菜单
- [ ] 点击书签图标：图标变为 `bookmark.fill`（黄色）约 1.5 秒后恢复
- [ ] 打开设置弹窗：只有字体排版 + 主题 + 更多入口
- [ ] 点击"更多阅读设置"：进入阅读偏好页面
- [ ] 阅读偏好页面：正常/舒适/紧凑预设、亮度、页眉信息、高级、缓存

- [ ] **Step 9.6：最终 Commit**

```bash
cd /Users/alina/Documents/Lei/legado
git add "IOS/Legado/App/Features/Reading/Views/ReaderView.swift"
git commit -m "feat(reader): 菜单栏新增换源+书签按钮，设置重组完成

Plan B+E 完成：
- topBar 右上新增换源（占位）和书签快捷按钮
- ReaderSettingsSheet 精简为字体排版+主题
- 自定义主题支持 ColorPicker 背景色和文字色
- ReadingPreferencesView 承载亮度/页眉信息/高级/缓存"
```

---

## 自检：规格覆盖确认

| 规格要求 | 对应 Task |
|---|---|
| 换源图标在三点左边 | Task 9 |
| 书签图标在三点左边（换源右边） | Task 9 |
| 书签点击 = 三点菜单"添加书签"功能一致 | Task 9（复用 addBookmark()） |
| 设置弹窗只保留字体排版+主题 | Task 7 |
| 主题新增自定义选项（+圆形色块） | Task 7 |
| 自定义主题含背景色+文字色 ColorPicker | Task 7 |
| 自定义主题颜色持久化 | Task 6（hex string AppStorage） |
| 亮度迁移到阅读偏好 | Task 8 |
| 布局预设正常/舒适/紧凑 | Task 8（字号/行高/边距组合） |
| 页眉信息迁移（2项 Toggle）到阅读偏好 | Task 8 |
| 高级设置迁移到阅读偏好 | Task 8 |
| 缓存设置迁移到阅读偏好 | Task 8 |
| 朗读语速从设置弹窗移除 | Task 7（不在新 SettingsSheet 中） |
