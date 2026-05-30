# 阅读器 NewLook — Plan A：状态栏重布局

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 重构阅读器 Header（左上改章节导航 + 右侧保留章节进度）和 Footer（左下加自绘电池图标+时间），BatteryMonitor 补充充电状态，废弃 showHeaderTime。

**Architecture:** 提取 BatteryMonitor 到独立文件并升级；新建 BatteryIconView（Canvas 自绘）和 FooterTimeManager（分钟对齐计时）；在 ReaderPageView 内替换 Header/Footer 布局；更新 ReaderSettingsSheet 移除"显示时间"Toggle。

**Tech Stack:** SwiftUI Canvas, Combine, UIDevice battery notifications, DispatchQueue minute-boundary timer, Swift async/await

**分支：** `IOS-NewLook`
**模拟器 UUID：** `962E405B-C2DC-463C-889D-FC51D1438E83`

---

## 文件变更清单

| 操作 | 文件 | 说明 |
|---|---|---|
| 新建 | `App/UI/BatteryMonitor.swift` | 从 ReaderView.swift 提取并升级 |
| 新建 | `App/UI/BatteryIconView.swift` | 自绘电池图标 + 时间 Footer 组件 |
| 修改 | `App/Features/Reading/Views/ReaderView.swift` | 删除内嵌 BatteryMonitor；修改 ReaderPageView header/footer；修改 ReaderSettingsSheet |

---

## Task 1：提取 BatteryMonitor 并补充 isCharging

**Files:**
- Create: `IOS/Legado/App/UI/BatteryMonitor.swift`
- Modify: `IOS/Legado/App/Features/Reading/Views/ReaderView.swift:354-368`（删除内嵌定义）

- [ ] **Step 1.1：新建 `BatteryMonitor.swift`**

```swift
// IOS/Legado/App/UI/BatteryMonitor.swift
import UIKit
import Combine

/// 电量监控单例，仅在 view onAppear/onDisappear 时开关监听，避免持续唤醒。
final class BatteryMonitor: ObservableObject {
    static let shared = BatteryMonitor()

    @Published private(set) var level: Float = 1.0
    @Published private(set) var isCharging: Bool = false

    private var cancellables = Set<AnyCancellable>()

    private init() {
        refresh()
        NotificationCenter.default.publisher(for: UIDevice.batteryLevelDidChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: UIDevice.batteryStateDidChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
    }

    /// 视图出现时调用，启用系统电量监听
    func enable() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        refresh()
    }

    /// 视图消失时调用，关闭系统监听节省资源
    func disable() {
        UIDevice.current.isBatteryMonitoringEnabled = false
    }

    private func refresh() {
        let raw = UIDevice.current.batteryLevel
        if raw >= 0 { level = raw }
        let state = UIDevice.current.batteryState
        isCharging = state == .charging || state == .full
    }
}
```

- [ ] **Step 1.2：删除 ReaderView.swift 中的内嵌 BatteryMonitor**

打开 `ReaderView.swift`，找到并**删除**以下代码块（约第 354–368 行）：

```swift
// MARK: - BatteryMonitor

final class BatteryMonitor: ObservableObject {
    static let shared = BatteryMonitor()
    @Published var level: Float = 1.0

    private init() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        level = max(UIDevice.current.batteryLevel, 0)
        NotificationCenter.default.addObserver(self, selector: #selector(batteryLevelChanged),
            name: UIDevice.batteryLevelDidChangeNotification, object: nil)
    }
    @objc private func batteryLevelChanged() {
        DispatchQueue.main.async { self.level = max(UIDevice.current.batteryLevel, 0) }
    }
}
```

- [ ] **Step 1.3：在 ReaderPageView 中补充 enable/disable 调用**

在 `ReaderPageView.body` 的最外层 ZStack 上追加：

```swift
.onAppear  { battery.enable()  }
.onDisappear { battery.disable() }
```

- [ ] **Step 1.4：构建验证**

```bash
cd /Users/alina/Documents/Lei/legado/IOS
xcodebuild -project Legado.xcodeproj -scheme Legado \
  -destination 'platform=iOS Simulator,id=962E405B-C2DC-463C-889D-FC51D1438E83' \
  -quiet build 2>&1 | grep -E "error:|BUILD"
```

期望：`** BUILD SUCCEEDED **`

- [ ] **Step 1.5：Commit**

```bash
cd /Users/alina/Documents/Lei/legado
git add IOS/Legado/App/UI/BatteryMonitor.swift \
        "IOS/Legado/App/Features/Reading/Views/ReaderView.swift"
git commit -m "refactor(reader): 提取 BatteryMonitor + 补充 isCharging"
```

---

## Task 2：新建 BatteryIconView（自绘电池图标 + Footer）

**Files:**
- Create: `IOS/Legado/App/UI/BatteryIconView.swift`

- [ ] **Step 2.1：新建 `BatteryIconView.swift`**

```swift
// IOS/Legado/App/UI/BatteryIconView.swift
import SwiftUI

/// 自绘电池图标：Canvas 轮廓 + 比例填充 + 叠加百分比/充电符号。
/// 用于阅读器底部状态栏左侧。
struct BatteryIconView: View {
    let level: Float       // 0.0 – 1.0
    let isCharging: Bool
    let textColor: Color   // 与当前阅读主题文字颜色对应

    private var fillColor: Color {
        if isCharging { return .green }
        return level <= 0.2 ? .red : textColor.opacity(0.7)
    }

    var body: some View {
        ZStack {
            // Canvas 绘制轮廓 + 填充
            Canvas { ctx, size in
                let nubW: CGFloat = 3
                let bodyW = size.width - nubW
                let bodyH = size.height
                let r: CGFloat = 2
                let inset: CGFloat = 1

                // 电池本体轮廓
                ctx.stroke(
                    Path(roundedRect: CGRect(x: 0, y: 0, width: bodyW, height: bodyH),
                         cornerRadius: r),
                    with: .color(textColor.opacity(0.5)),
                    lineWidth: 1
                )

                // 右侧电极凸起
                let nubH = bodyH * 0.5
                let nubY = (bodyH - nubH) / 2
                ctx.fill(
                    Path(roundedRect: CGRect(x: bodyW, y: nubY, width: nubW, height: nubH),
                         cornerRadius: 1),
                    with: .color(textColor.opacity(0.5))
                )

                // 电量填充（从左向右）
                let maxFillW = bodyW - 2 * inset
                let fillW = maxFillW * CGFloat(max(0, min(1, level)))
                if fillW > 0.5 {
                    let fillR = max(0, r - inset)
                    ctx.fill(
                        Path(roundedRect: CGRect(x: inset, y: inset,
                                                 width: fillW, height: bodyH - 2 * inset),
                             cornerRadius: fillR),
                        with: .color(isCharging ? Color.green
                                                : (level <= 0.2 ? Color.red
                                                                : textColor.opacity(0.7)))
                    )
                }
            }
            .frame(width: 28, height: 14)

            // 叠加文字（百分比或充电符号），向左偏移 1.5pt 使其居中于电池本体
            Group {
                if isCharging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundColor(.white)
                } else {
                    Text("\(Int(level * 100))%")
                        .font(.system(size: 8))
                        .foregroundColor(.white)
                }
            }
            .offset(x: -1.5)  // 修正右侧电极凸起导致的视觉偏移
        }
        .frame(width: 28, height: 14)
    }
}

#Preview {
    VStack(spacing: 8) {
        BatteryIconView(level: 0.84, isCharging: false, textColor: .black)
        BatteryIconView(level: 0.15, isCharging: false, textColor: .black)
        BatteryIconView(level: 0.60, isCharging: true,  textColor: .black)
    }
    .padding()
}
```

- [ ] **Step 2.2：构建验证**

```bash
cd /Users/alina/Documents/Lei/legado/IOS
xcodebuild -project Legado.xcodeproj -scheme Legado \
  -destination 'platform=iOS Simulator,id=962E405B-C2DC-463C-889D-FC51D1438E83' \
  -quiet build 2>&1 | grep -E "error:|BUILD"
```

期望：`** BUILD SUCCEEDED **`

- [ ] **Step 2.3：Commit**

```bash
cd /Users/alina/Documents/Lei/legado
git add IOS/Legado/App/UI/BatteryIconView.swift
git commit -m "feat(reader): 新增自绘 BatteryIconView"
```

---

## Task 3：重构 ReaderPageView Header

**Files:**
- Modify: `IOS/Legado/App/Features/Reading/Views/ReaderView.swift`（ReaderPageView 内 header 区域，约第 291–313 行）

**目标**：左侧改为固定章节导航（chevron.left + 第N章 标题），右侧保留章节进度。

- [ ] **Step 3.1：在 ReaderPageView struct 中添加 onBack 参数和时间管理器**

在 `ReaderPageView` 的属性声明区域（第 241–254 行附近），追加：

```swift
let onBack: () -> Void          // 点击 < 返回书架
@State private var footerTime: String = {
    let f = DateFormatter(); f.dateFormat = "HH:mm"
    return f.string(from: Date())
}()
```

- [ ] **Step 3.2：替换 header 区域代码**

找到 `ReaderPageView.body` 内"页眉"注释块（约第 291–313 行）：

```swift
// 页眉
if settings.showHeaderTime || settings.showHeaderProgress || settings.showHeaderBattery {
    HStack {
        if settings.showHeaderTime {
            Text(currentTime)
                .font(.system(size: 11))
                .foregroundColor(settings.currentTheme.textColor.opacity(0.5))
        }
        Spacer()
        if settings.showHeaderProgress, totalChapters > 0 {
            Text("\(chapterIndex + 1)/\(totalChapters)章")
                .font(.system(size: 11))
                .foregroundColor(settings.currentTheme.textColor.opacity(0.5))
        }
        if settings.showHeaderBattery {
            Text("\(Int(battery.level * 100))%")
                .font(.system(size: 11))
                .foregroundColor(settings.currentTheme.textColor.opacity(0.5))
        }
    }
    .padding(.horizontal, settings.sideMargin)
    .padding(.top, 8)
}
```

**替换为：**

```swift
// 页眉：左侧章节导航（固定显示），右侧章节进度（受 showHeaderProgress 控制）
HStack(spacing: 4) {
    // 左侧：返回 + 章节标题（始终显示）
    Button(action: onBack) {
        HStack(spacing: 4) {
            Image(systemName: "chevron.left")
                .font(.system(size: 11, weight: .medium))
            Text("第\(chapterIndex + 1)章 \(applyTraditional(chapterTitle))")
                .font(.system(size: 11))
                .lineLimit(1)
        }
        .foregroundColor(settings.currentTheme.textColor.opacity(0.5))
    }
    .buttonStyle(.plain)

    Spacer()

    // 右侧：章节总进度
    if settings.showHeaderProgress, totalChapters > 0 {
        Text("\(chapterIndex + 1) / \(totalChapters)章")
            .font(.system(size: 11))
            .foregroundColor(settings.currentTheme.textColor.opacity(0.5))
    }
    if settings.showHeaderBattery {
        Text("\(Int(battery.level * 100))%")
            .font(.system(size: 11))
            .foregroundColor(settings.currentTheme.textColor.opacity(0.5))
    }
}
.padding(.horizontal, settings.sideMargin)
.padding(.top, 8)
```

- [ ] **Step 3.3：删除现在已无用的 `currentTime` 计算属性**

找到并删除（约第 342–343 行）：

```swift
private var currentTime: String {
    let f = DateFormatter(); f.dateFormat = "HH:mm"; return f.string(from: Date())
}
```

- [ ] **Step 3.4：构建验证**

```bash
cd /Users/alina/Documents/Lei/legado/IOS
xcodebuild -project Legado.xcodeproj -scheme Legado \
  -destination 'platform=iOS Simulator,id=962E405B-C2DC-463C-889D-FC51D1438E83' \
  -quiet build 2>&1 | grep -E "error:|BUILD"
```

若报错"onBack 未传入"，在下一步修正调用处。

- [ ] **Step 3.5：修复 ReaderPageView 的调用处（传入 onBack）**

全局搜索 `ReaderPageView(` 调用处（在 `ReaderView.body` 的 `pageModeView` 和 `scrollModeView` 中），在每个调用处追加 `onBack: dismiss` 参数。

例如：

```swift
// 修改前
ReaderPageView(
    content: page,
    chapterTitle: chapters[idx].title,
    ...
)

// 修改后
ReaderPageView(
    content: page,
    chapterTitle: chapters[idx].title,
    ...
    onBack: { dismiss() }
)
```

- [ ] **Step 3.6：构建验证**

```bash
xcodebuild -project Legado.xcodeproj -scheme Legado \
  -destination 'platform=iOS Simulator,id=962E405B-C2DC-463C-889D-FC51D1438E83' \
  -quiet build 2>&1 | grep -E "error:|BUILD"
```

期望：`** BUILD SUCCEEDED **`

- [ ] **Step 3.7：Commit**

```bash
cd /Users/alina/Documents/Lei/legado
git add "IOS/Legado/App/Features/Reading/Views/ReaderView.swift"
git commit -m "feat(reader): 重构 Header — 章节导航取代时间显示"
```

---

## Task 4：重构 ReaderPageView Footer

**Files:**
- Modify: `IOS/Legado/App/Features/Reading/Views/ReaderView.swift`（ReaderPageView footer 区域，约第 280–285 行）

**目标**：左侧加 BatteryIconView + 时间，右侧保留页码。

- [ ] **Step 4.1：替换 footer 的 HStack**

找到 `ReaderPageView.body` 内最底部（在 `Spacer(minLength: 0)` 之后）的 HStack：

```swift
HStack {
    Spacer()
    Text(pageLabel)
        .font(.system(size: 11))
        .foregroundColor(settings.currentTheme.textColor.opacity(0.5))
}
```

**替换为：**

```swift
HStack {
    // 左侧：电池图标 + 时间
    HStack(spacing: 0) {
        BatteryIconView(
            level: battery.level,
            isCharging: battery.isCharging,
            textColor: settings.currentTheme.textColor
        )
        Text("\u{2003}\u{2003}\(footerTime)")   // 两个 em-space + 时间
            .font(.system(size: 11))
            .foregroundColor(settings.currentTheme.textColor.opacity(0.5))
    }

    Spacer()

    // 右侧：当前页/总页数（不变）
    Text(pageLabel)
        .font(.system(size: 11))
        .foregroundColor(settings.currentTheme.textColor.opacity(0.5))
}
```

- [ ] **Step 4.2：添加分钟对齐计时器**

在 `ReaderPageView.body` 最外层 ZStack 上已有的 `.onAppear` / `.onDisappear` 修饰符处，补充时间刷新逻辑。**将原有的 `.onAppear { battery.enable() }` 替换为：**

```swift
.onAppear {
    battery.enable()
    scheduleNextMinuteUpdate()
}
.onDisappear {
    battery.disable()
}
```

- [ ] **Step 4.3：在 ReaderPageView 内添加 `scheduleNextMinuteUpdate` 方法**

在 `ReaderPageView` 的 `private func applyTraditional` 之后追加：

```swift
/// 在下一个分钟整点更新 footerTime，然后每 60 秒递归调度。
/// 对齐到分钟边界确保时间显示始终准确。
private func scheduleNextMinuteUpdate() {
    let now = Date()
    let calendar = Calendar.current
    // 下一个"秒=0"的时刻
    guard let nextMinute = calendar.nextDate(
        after: now,
        matching: DateComponents(second: 0),
        matchingPolicy: .nextTime
    ) else { return }
    let delay = nextMinute.timeIntervalSinceNow
    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        footerTime = f.string(from: Date())
        scheduleNextMinuteUpdate()  // 递归，每分钟整点触发
    }
}
```

- [ ] **Step 4.4：构建验证**

```bash
cd /Users/alina/Documents/Lei/legado/IOS
xcodebuild -project Legado.xcodeproj -scheme Legado \
  -destination 'platform=iOS Simulator,id=962E405B-C2DC-463C-889D-FC51D1438E83' \
  -quiet build 2>&1 | grep -E "error:|BUILD"
```

期望：`** BUILD SUCCEEDED **`

- [ ] **Step 4.5：Commit**

```bash
cd /Users/alina/Documents/Lei/legado
git add "IOS/Legado/App/Features/Reading/Views/ReaderView.swift"
git commit -m "feat(reader): 重构 Footer — 左侧电池图标+时间，右侧页码不变"
```

---

## Task 5：更新 ReaderSettingsSheet — 移除"显示时间"Toggle

**Files:**
- Modify: `IOS/Legado/App/Features/Reading/Views/ReaderView.swift`（ReaderSettingsSheet，约第 653–657 行）

- [ ] **Step 5.1：删除"显示时间"Toggle**

找到 `ReaderSettingsSheet` 内的"页眉信息" Section（约第 653–657 行）：

```swift
Section("页眉信息") {
    Toggle("显示时间",     isOn: $settings.showHeaderTime)
    Toggle("显示章节进度", isOn: $settings.showHeaderProgress)
    Toggle("显示电量",     isOn: $settings.showHeaderBattery)
}
```

**替换为（删除第一个 Toggle）：**

```swift
Section("页眉信息") {
    Toggle("显示章节进度", isOn: $settings.showHeaderProgress)
    Toggle("显示右上电量", isOn: $settings.showHeaderBattery)
}
```

**注意**：`showHeaderTime` 字段本身保留在 `ReaderSettings.swift` 中（避免破坏已有 AppStorage 数据），只从 UI 中移除显示入口。Header 左侧章节导航现在始终显示，不受任何开关控制。

- [ ] **Step 5.2：构建验证**

```bash
cd /Users/alina/Documents/Lei/legado/IOS
xcodebuild -project Legado.xcodeproj -scheme Legado \
  -destination 'platform=iOS Simulator,id=962E405B-C2DC-463C-889D-FC51D1438E83' \
  -quiet build 2>&1 | grep -E "error:|BUILD"
```

期望：`** BUILD SUCCEEDED **`

- [ ] **Step 5.3：模拟器视觉验证**

```bash
SIM=962E405B-C2DC-463C-889D-FC51D1438E83
APP=$(find ~/Library/Developer/Xcode/DerivedData/Legado-*/Build/Products/Debug-iphonesimulator/Legado.app -maxdepth 0 2>/dev/null | tail -1)
xcrun simctl install $SIM "$APP"
xcrun simctl terminate $SIM com.legado.app 2>/dev/null
xcrun simctl launch $SIM com.legado.app
```

在模拟器中打开任意一本书，进入阅读器，验证：
- [ ] 左上显示 `‹ 第N章 章节标题`（截断正常）
- [ ] 点击左上区域可返回书架
- [ ] 右上显示 `N / M章`（章节进度）
- [ ] 左下显示电池图标（含百分比）+ 空格 + HH:mm 时间
- [ ] 右下显示 `当前页 / 总页数`
- [ ] 设置弹窗中"页眉信息"只有两个 Toggle（无"显示时间"）

- [ ] **Step 5.4：最终 Commit**

```bash
cd /Users/alina/Documents/Lei/legado
git add "IOS/Legado/App/Features/Reading/Views/ReaderView.swift"
git commit -m "feat(reader): 移除'显示时间'Toggle，页眉信息仅保留章节进度和电量开关

Plan A 完成：状态栏重布局
- Header 左侧：固定章节导航（chevron + 第N章 标题）
- Header 右侧：章节进度 + 右上电量（受开关控制，不变）
- Footer 左侧：BatteryIconView + 分钟对齐时间
- Footer 右侧：页码（不变）
- BatteryMonitor 提取为独立文件，增加 isCharging 属性"
```

---

## 自检：规格覆盖确认

| 规格要求 | 对应 Task |
|---|---|
| 左上 < 符号（chevron.left）点击返回书架 | Task 3 |
| 左上显示第xx章 xxx标题，超长截断 | Task 3 |
| 右上保持现有显示（章节进度） | Task 3 |
| 左下电量图标含数值，图标随状态变化 | Task 2, 4 |
| 左下电量图标后空二个空格 + 时间 | Task 4 |
| 右下当前章节页码/总页数 | 已存在（pageLabel），无需修改 |
| 电量刷新仅在变化时触发（零轮询） | Task 1（notification 驱动） |
| 时间刷新对齐分钟整点 | Task 4 |
| 废弃"显示时间"Toggle | Task 5 |
