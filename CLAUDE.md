# Legado iOS — Agent 工作手册

## 项目概况

Android 版 Legado 小说阅读器的 iOS 移植（SwiftUI + GRDB + Alamofire + SwiftSoup）。  
主分支：`master`，开发分支：`IOS`。  
Xcode 26.0.1，部署目标 iOS 15.0。

---

## 模拟器调试流程（经过验证的有效方法）

### 背景

Claude Code 无法直接操作模拟器 UI（AppleScript 因沙盒权限受限），但可通过以下组合实现完全自主调试，**无需用户手动操作**。

### 标准步骤

#### 1. 定位模拟器

```bash
xcrun simctl list devices available | grep -E "26\.|18\."
# 记录 UUID，例如：962E405B-C2DC-463C-889D-FC51D1438E83
```

#### 2. 读取 App 数据库（了解真实数据）

App 每次重装 UUID 会变，需动态查找：

```bash
find ~/Library/Developer/CoreSimulator/Devices/<SIMULATOR_UUID> \
  -name "legado_v2.sqlite" 2>/dev/null | tail -1
```

然后用 `/usr/bin/sqlite3` 查询（注意路径含空格要加引号）：

```bash
/usr/bin/sqlite3 "$DB" "SELECT bookSourceName, exploreUrl FROM book_source WHERE enabled=1 LIMIT 3;"
```

#### 3. 加日志 → 构建 → 安装

在关键路径加 `print()` 诊断：

```swift
print("🔍 [Module] key=\(value) result=\(result)")
```

构建并安装：

```bash
xcodebuild -project Legado.xcodeproj -scheme Legado \
  -destination 'platform=iOS Simulator,id=<UUID>' build

xcrun simctl install <UUID> \
  "/Users/alina/Library/Developer/Xcode/DerivedData/Legado-*/Build/Products/Debug-iphonesimulator/Legado.app"
```

#### 4. 用 `--console-pty` 捕获 stdout（关键！）

`xcrun simctl spawn ... log stream` 只捕获 OS log，**不捕获 `print()` 的 stdout**。  
必须用 `--console-pty`：

```bash
xcrun simctl terminate <UUID> com.legado.app 2>/dev/null
sleep 1

xcrun simctl launch --console-pty <UUID> com.legado.app [--custom-flag] \
  > /tmp/legado_output.log 2>&1 &

sleep <等待时间>
grep -E "🔍|❌|✅" /tmp/legado_output.log | head -30
```

#### 5. 自动测试 flag（无需 UI 交互）

在 `LegadoApp.swift` 里加 `CommandLine.arguments` 检测，启动时自动跑测试逻辑，而无需手动点击：

```swift
@main struct LegadoApp: App {
    var body: some Scene {
        WindowGroup { MainTabView().task { await AutoTest.run() } }
    }
}

private enum AutoTest {
    static func run() async {
        guard CommandLine.arguments.contains("--my-test") else { return }
        try? await Task.sleep(nanoseconds: 3_000_000_000)  // 等待 DB 初始化
        // ... 测试逻辑，直接调用 ViewModel/Service 方法 ...
        print("✅ [AutoTest] name='\(name)' url='\(url)'")
    }
}
```

启动时传入 flag：

```bash
xcrun simctl launch --console-pty <UUID> com.legado.app --my-test > /tmp/out.log 2>&1 &
sleep 20
grep "AutoTest" /tmp/out.log
```

**调试完成后务必删除 AutoTest 代码再提交。**

#### 6. 截图辅助（确认 UI 状态）

```bash
xcrun simctl io <UUID> screenshot /tmp/screen.png
# 然后 Read /tmp/screen.png 查看
```

注意：图片坐标需乘以显示倍数（截图描述会给出 multiply 系数）。

---

### 完整调试循环示例

```
1. 加 print 日志
2. xcodebuild build
3. xcrun simctl install <UUID> <.app路径>
4. xcrun simctl terminate <UUID> com.legado.app
5. xcrun simctl launch --console-pty <UUID> com.legado.app --test > /tmp/out.log &
6. sleep N
7. grep "🔍|❌" /tmp/out.log
8. 分析 → 改代码 → 回到步骤 1
```

---

### 常见陷阱

| 问题 | 原因 | 解决方案 |
|---|---|---|
| `print()` 不出现在日志 | `log stream` 只捕获 OS log | 必须用 `--console-pty` |
| App 找不到数据库 | 每次重装 UUID 变 | 用 `find ... -name "legado_v2.sqlite" \| tail -1` 动态查 |
| 删 DerivedData 后 GRDB 子模块报错 | GRDB 有 SQLiteCustom submodule 需要 clone | `git -C ~/Library/.../GRDB.swift submodule deinit SQLiteCustom/src` |
| 模拟器启动报 RequestDenied | 模拟器状态污染 | `xcrun simctl erase <UUID>` + 清 DerivedData |
| AppleScript 点击报权限错误 | 沙盒限制，System Events 无法控制其他 App | 改用 `--console-pty` + `CommandLine.arguments` 自动测试 |

---

## 包管理注意事项

删除 DerivedData 后重新构建，GRDB 会尝试 clone `SQLiteCustom/src` 子模块（被沙盒拦截）：

```bash
# 一次性修复（我们用标准 SQLite，不需要该子模块）
git -C ~/Library/Developer/Xcode/DerivedData/SourcePackages/checkouts/GRDB.swift \
  submodule deinit SQLiteCustom/src
```

---

## iOS 26 模拟器特殊处理

- UUID：`962E405B-C2DC-463C-889D-FC51D1438E83`（iPhone 16 Pro Max iOS 26.0）
- 粘贴功能需要：模拟器菜单 `Edit → Automatically Sync Pasteboard`
- 首次安装若报 `FBSOpenApplicationServiceErrorDomain Code 1`：先 `xcrun simctl erase <UUID>`，再重装

---

## 项目结构关键路径

```
IOS/Legado/App/
├── Core/
│   ├── Engine/          RuleExecutor, RuleParser, JSONPathEngine, AnalyzeContext
│   ├── HTML/            HTMLParser (CSS/XPath)
│   ├── JSBridge/        LegadoJSEngine, JSJavaHelper
│   └── Network/         NetworkManager, HeadlessWebViewLoader
├── Features/
│   ├── BookSource/      SearchViewModel(含AnalyzeUrl), BookSourceViewModel, ExploreView
│   └── Reading/         ReaderViewModel, BookInfoView, BookContentParser
└── Core/Database/       DatabaseManager (GRDB 迁移在此)
```

**新加模型字段**必须同步加 DB 迁移（`DatabaseManager.swift` 里加新 `migrator.registerMigration("vN-...")`），否则 INSERT 时 SQLite error 1。
