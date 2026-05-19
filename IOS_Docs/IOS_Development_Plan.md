# Legado iOS 版本开发计划（AI 执行版）

> **文档目的**：为 AI 提供详细的阶段化开发计划，支持冷启动执行，确保每个阶段可独立完成。

---

## 📋 文档说明

**使用原则**：
1. ✅ 每个阶段可以独立执行（冷启动）
2. ✅ 每个阶段有明确的输入、输出、验收标准
3. ✅ 每个阶段完成后可以暂停，下次继续
4. ✅ 遇到问题必须记录，不得跳过
5. ✅ 阶段间依赖关系明确

**执行流程**：
```
阶段开始 → 检查前置条件 → 执行任务清单 → 验收测试 → 生成报告 → 阶段结束
```

**文档结构**：
- 总体开发路线图
- 阶段详细计划（10个阶段）
- 冷启动检查清单
- 技术实现规范
- 质量保证标准

---

## 🗺️ 总体开发路线图

```
阶段 0: 原型验证（1 周）
  ↓
阶段 1: 项目初始化（1 周）
  ↓
阶段 2: 数据模型设计（1 周）
  ↓
阶段 3: JavaScript 引擎（2 周）
  ↓
阶段 4: 规则解析系统（1 周）
  ↓
阶段 5: 网络请求层（1 周）
  ↓
阶段 6: HTML 解析层（3 天）
  ↓
阶段 7: 数据库层（1 周）
  ↓
阶段 8: 核心功能实现（6 周）
  ↓
阶段 9: 测试和优化（3 周）
  ↓
阶段 10: 发布准备（1 周）
```

**总开发时间**：4-5 个月

---

## 🚀 阶段 0：原型验证（1 周）

### 阶段目标

验证技术方案的可行性，降低开发风险。

### 前置条件

- [ ] 已阅读 `IOS_Android_Analyze.md` 文档
- [ ] 已阅读 `IOS_可行性分析.md` 文档
- [ ] 已阅读 `IOS_设计说明书.md` 文档
- [ ] 已安装 Xcode 15.0+
- [ ] 已安装 Swift 5.9+
- [ ] 已配置 macOS 开发环境

### 输入

- Android 版本书源规则示例（至少 20 个热门书源）
- JavaScript 兼容性测试用例
- 技术栈清单

### 输出

- `阶段0_验证报告.md` - 包含验证结果和风险评估
- `阶段0_兼容性报告.md` - 包含 JavaScriptCore 兼容性统计
- `阶段0_技术方案确认.md` - 包含最终技术方案确认

### 验收标准

- [ ] JavaScriptCore 基础功能 100% 可用
- [ ] Rhino API 兼容率 > 90%
- [ ] 热门书源兼容率 > 95%
- [ ] 技术风险评估完成
- [ ] 最终技术方案确认

### 任务清单

#### 任务 0.1：创建验证项目（1 天）

**目标**：创建用于验证的 Xcode 项目

**步骤**：
1. 打开 Xcode
2. 创建新的 macOS App 项目（Command Line Tool 也可以）
3. 配置项目设置：
   - Swift Language Version: Swift 5.9
   - Deployment Target: macOS 13.0+
   - Bundle Identifier: com.legado.prototype
4. 添加必要的依赖：
   - Alamofire（网络请求）
   - SwiftSoup（HTML 解析）
5. 创建测试目录结构

**验证**：
- [ ] 项目可以成功编译
- [ ] 可以运行空的 main.swift
- [ ] 依赖库正常导入

**输出**：
- Xcode 项目文件
- 项目结构说明

---

#### 任务 0.2：JavaScriptCore 基础功能测试（1 天）

**目标**：测试 JavaScriptCore 的基础功能

**步骤**：
1. 创建 `JavaScriptCoreTest.swift` 文件
2. 测试基础 JavaScript 功能：
   ```swift
   // 测试 1: 基础算术运算
   let context = JSContext()
   let result1 = context.evaluateScript("1 + 1")
   assert(result1?.toInt32() == 2)

   // 测试 2: 函数调用
   let result2 = context.evaluateScript("function add(a, b) { return a + b; } add(1, 2)")
   assert(result2?.toInt32() == 3)

   // 测试 3: 对象操作
   let result3 = context.evaluateScript("var obj = {name: 'test'}; obj.name")
   assert(result3?.toString() == "test")

   // 测试 4: 数组操作
   let result4 = context.evaluateScript("var arr = [1, 2, 3]; arr.length")
   assert(result4?.toInt32() == 3)

   // 测试 5: 字符串操作
   let result5 = context.evaluateScript("'hello'.length")
   assert(result5?.toInt32() == 5)
   ```
3. 测试异常处理：
   ```swift
   context.exceptionHandler = { context, exception in
       print("JavaScript Error: \(exception ?? "")")
   }

   let errorResult = context.evaluateScript("undefinedVariable")
   assert(errorResult?.isUndefined ?? true)
   ```
4. 测试对象桥接：
   ```swift
   class TestClass: NSObject {
       @objc func testMethod() -> String {
           return "test"
       }
   }

   let testObj = TestClass()
   context.globalObject.setValue(testObj, forProperty: "testObj")
   let bridgeResult = context.evaluateScript("testObj.testMethod()")
   assert(bridgeResult?.toString() == "test")
   ```

**验证**：
- [ ] 所有基础功能测试通过
- [ ] 异常处理正常工作
- [ ] 对象桥接正常工作

**输出**：
- `JavaScriptCoreTest.swift` - 测试代码
- 测试结果报告

---

#### 任务 0.3：Rhino API 兼容性测试（2 天）

**目标**：测试 Rhino API 在 JavaScriptCore 中的兼容性

**步骤**：
1. 创建 `RhinoAPITest.swift` 文件
2. 实现 Rhino API 兼容层：
   ```swift
   @objc protocol JSJavaHelperProtocol: JSExport {
       func ajax(_ url: String, method: String) -> String?
       func put(_ key: String, value: Any)
       func get(_ key: String) -> Any?
       func log(_ message: String)
   }

   class JSJavaHelper: NSObject, JSJavaHelperProtocol {
       func ajax(_ url: String, method: String) -> String? {
           print("AJAX Request: \(url), Method: \(method)")
           return "mock_response"
       }

       func put(_ key: String, value: Any) {
           print("PUT: \(key) = \(value)")
           UserDefaults.standard.set(value, forKey: key)
       }

       func get(_ key: String) -> Any? {
           print("GET: \(key)")
           return UserDefaults.standard.value(forKey: key)
       }

       func log(_ message: String) {
           print("LOG: \(message)")
       }
   }
   ```
3. 测试 Rhino API 调用：
   ```swift
   let context = JSContext()
   let javaHelper = JSJavaHelper()
   context.globalObject.setValue(javaHelper, forProperty: "java")

   // 测试 1: ajax 调用
   let result1 = context.evaluateScript("java.ajax('https://example.com', 'GET')")
   assert(result1?.toString() == "mock_response")

   // 测试 2: put/get 调用
   context.evaluateScript("java.put('testKey', 'testValue')")
   let result2 = context.evaluateScript("java.get('testKey')")
   assert(result2?.toString() == "testValue")

   // 测试 3: log 调用
   context.evaluateScript("java.log('test message')")
   ```

**验证**：
- [ ] Rhino API 兼容层实现完成
- [ ] 所有 Rhino API 测试通过
- [ ] 兼容性统计完成

**输出**：
- `RhinoAPITest.swift` - 测试代码
- Rhino API 兼容性报告

---

#### 任务 0.4：书源规则执行测试（2 天）

**目标**：测试实际书源规则的执行

**步骤**：
1. 准备测试书源（至少 20 个热门书源）
2. 创建 `BookSourceRuleTest.swift` 文件
3. 实现规则解析器：
   ```swift
   enum RuleType {
       case defaultRule
       case xpath
       case json
       case regex
       case javascript
   }

   class RuleParser {
       func parseRule(_ rule: String) -> (RuleType, String) {
           if rule.hasPrefix("<js>") {
               let content = String(rule.dropFirst(4).dropLast(5))
               return (.javascript, content)
           } else if rule.hasPrefix("@XPath:") {
               let content = String(rule.dropFirst(7))
               return (.xpath, content)
           } else if rule.hasPrefix("@Json:") {
               let content = String(rule.dropFirst(6))
               return (.json, content)
           } else if rule.hasPrefix("@Regex:") {
               let content = String(rule.dropFirst(7))
               return (.regex, content)
           } else if rule.hasPrefix("@") {
               let content = String(rule.dropFirst(1))
               return (.defaultRule, content)
           } else {
               return (.defaultRule, rule)
           }
       }
   }
   ```
4. 测试各类规则：
   ```swift
   let parser = RuleParser()

   // 测试 XPath 规则
   let (type1, content1) = parser.parseRule("@XPath://div[@class='title']/text()")
   assert(type1 == .xpath)
   assert(content1 == "//div[@class='title']/text()")

   // 测试 JSON 规则
   let (type2, content2) = parser.parseRule("@Json:$.data.list[*].title")
   assert(type2 == .json)
   assert(content2 == "$.data.list[*].title")

   // 测试 JavaScript 规则
   let (type3, content3) = parser.parseRule("<js>result.map(item => item.title)</js>")
   assert(type3 == .javascript)
   assert(content3 == "result.map(item => item.title)")
   ```

**验证**：
- [ ] 规则解析器实现完成
- [ ] 所有规则类型解析正确
- [ ] 实际书源规则测试完成

**输出**：
- `BookSourceRuleTest.swift` - 测试代码
- 书源规则执行报告

---

#### 任务 0.5：生成验证报告（1 天）

**目标**：生成完整的验证报告

**步骤**：
1. 收集所有测试结果
2. 统计兼容性数据：
   - JavaScriptCore 基础功能通过率
   - Rhino API 兼容率
   - 书源规则执行通过率
3. 评估技术风险：
   - 高风险项（兼容率 < 80%）
   - 中风险项（兼容率 80-90%）
   - 低风险项（兼容率 > 90%）
4. 制定缓解措施
5. 确认最终技术方案

**验证**：
- [ ] 验证报告完整
- [ ] 兼容性数据准确
- [ ] 风险评估合理
- [ ] 缓解措施可行

**输出**：
- `阶段0_验证报告.md`
- `阶段0_兼容性报告.md`
- `阶段0_技术方案确认.md`

---

### 阶段 0 验收检查清单

- [ ] JavaScriptCore 基础功能 100% 可用
- [ ] Rhino API 兼容率 > 90%
- [ ] 热门书源兼容率 > 95%
- [ ] 验证报告完整
- [ ] 技术方案确认
- [ ] 风险评估完成

### 阶段 0 输入文档

- `IOS_Android_Analyze.md`
- `IOS_可行性分析.md`
- `IOS_设计说明书.md`

### 阶段 0 输出文档

- `阶段0_验证报告.md`
- `阶段0_兼容性报告.md`
- `阶段0_技术方案确认.md`

### 阶段 0 后续阶段依赖

- 阶段 1（项目初始化）依赖阶段 0 的技术方案确认
- 阶段 3（JavaScript 引擎）依赖阶段 0 的兼容性报告

---

## 🚀 阶段 1：项目初始化（1 周）

### 阶段目标

创建完整的 iOS 项目结构和基础配置。

### 前置条件

- [ ] 阶段 0 验证通过
- [ ] 技术方案确认
- [ ] 已安装 Xcode 15.0+
- [ ] 已安装 CocoaPods 或 SPM（Swift Package Manager）

### 输入

- `阶段0_技术方案确认.md`
- `IOS_设计说明书.md`
- `IOS_Android_Analyze.md`

### 输出

- 完整的 Xcode 项目
- 项目配置文件
- 目录结构说明
- 依赖配置说明

### 验收标准

- [ ] Xcode 项目可以成功编译
- [ ] 所有依赖正常导入
- [ ] 项目结构符合设计要求
- [ ] 基础配置完成（Info.plist、签名等）

### 任务清单

#### 任务 1.1：创建 Xcode 项目（1 天）

**目标**：创建 iOS App 项目

**步骤**：
1. 打开 Xcode
2. 选择 "App" 模板
3. 配置项目信息：
   - Product Name: Legado
   - Team: 选择开发团队
   - Organization Identifier: io.legado
   - Interface: SwiftUI
   - Language: Swift
   - Use Core Data: 不勾选
   - Include Tests: 勾选
4. 选择保存位置
5. 创建项目

**验证**：
- [ ] 项目创建成功
- [ ] 可以运行到模拟器
- [ ] 默认界面显示正常

**输出**：
- Legado.xcodeproj
- Legado 目录

---

#### 任务 1.2：配置项目结构（1 天）

**目标**：创建项目目录结构

**步骤**：
1. 在 `Legado` 目录下创建以下目录：
   ```
   Legado/
   ├── App/
   │   ├── Features/
   │   │   ├── BookSource/
   │   │   │   ├── Models/
   │   │   │   ├── Views/
   │   │   │   └── ViewModels/
   │   │   ├── Reading/
   │   │   │   ├── Models/
   │   │   │   ├── Views/
   │   │   │   └── ViewModels/
   │   │   └── TTS/
   │   │       ├── Models/
   │   │       ├── Views/
   │   │       └── ViewModels/
   │   ├── Core/
   │   │   ├── Engine/
   │   │   ├── Network/
   │   │   ├── Database/
   │   │   ├── JSBridge/
   │   │   ├── HTML/
   │   │   └── Storage/
   │   ├── UI/
   │   │   ├── Components/
   │   │   ├── Theme/
   │   │   └── Styles/
   │   └── Resources/
   └── Tests/
       ├── Unit/
       ├── Integration/
       └── E2E/
   ```
2. 在每个目录下创建对应的 Swift 文件（空文件即可）

**验证**：
- [ ] 所有目录创建成功
- [ ] 目录结构符合设计要求

**输出**：
- 完整的项目目录结构

---

#### 任务 1.3：配置依赖管理（1 天）

**目标**：配置项目依赖

**步骤**：
1. 使用 Swift Package Manager 添加依赖：
   - Alamofire: https://github.com/Alamofire/Alamofire.git
   - SwiftSoup: https://github.com/scinfu/SwiftSoup.git
   - GRDB.swift: https://github.com/groue/GRDB.swift.git
2. 在 Xcode 中添加依赖：
   - File → Add Package Dependencies
   - 输入依赖 URL
   - 选择版本规则
   - 添加到项目
3. 创建 `Package.swift` 文件（如果需要）

**验证**：
- [ ] 所有依赖成功添加
- [ ] 项目可以成功编译
- [ ] 依赖库可以正常导入

**输出**：
- 配置完成的 Xcode 项目

---

#### 任务 1.4：配置 Info.plist（1 天）

**目标**：配置应用权限和设置

**步骤**：
1. 打开 `Info.plist` 文件
2. 添加以下权限：
   - NSAppTransportSecurity: 允许 HTTP 请求（如果需要）
   - NSMicrophoneUsageDescription: 麦克风使用说明（如果需要）
   - UIFileSharingEnabled: 文件共享
   - LSSupportsOpeningDocumentsInPlace: 支持文档应用
3. 配置应用信息：
   - Bundle Display Name: Legado
   - Bundle Version: 1.0.0
   - Build Number: 1
4. 配置支持的文件类型：
   - TXT 文件
   - EPUB 文件

**验证**：
- [ ] Info.plist 配置正确
- [ ] 应用信息正确
- [ ] 权限说明完整

**输出**：
- 配置完成的 Info.plist

---

#### 任务 1.5：配置代码规范（1 天）

**目标**：配置代码格式化和检查工具

**步骤**：
1. 安装 SwiftLint：
   ```bash
   brew install swiftlint
   ```
2. 创建 `.swiftlint.yml` 文件：
   ```yaml
   disabled_rules:
     - trailing_whitespace
   opt_in_rules:
     - empty_count
     - empty_string
   excluded:
     - Pods
     - Carthage
   line_length:
     warning: 120
     error: 200
   ```
3. 配置 Xcode Build Phases：
   - 添加 New Run Script Phase
   - 添加脚本：
     ```bash
     if which swiftlint >/dev/null; then
       swiftlint
     else
       echo "warning: SwiftLint not installed, download from https://github.com/realm/SwiftLint"
     fi
     ```

**验证**：
- [ ] SwiftLint 安装成功
- [ ] 代码检查正常工作
- [ ] 可以检测代码问题

**输出**：
- `.swiftlint.yml` 配置文件
- Xcode Build Phases 配置

---

#### 任务 1.6：创建基础文件（1 天）

**目标**：创建项目基础文件

**步骤**：
1. 创建 `App/LegadoApp.swift`：
   ```swift
   import SwiftUI

   @main
   struct LegadoApp: App {
       var body: some Scene {
           WindowGroup {
               ContentView()
           }
       }
   }
   ```
2. 创建 `App/ContentView.swift`：
   ```swift
   import SwiftUI

   struct ContentView: View {
       var body: some View {
           Text("Legado iOS")
               .font(.largeTitle)
       }
   }
   ```
3. 创建 `App/Resources/Assets.xcassets`：
   - 添加应用图标
   - 添加启动图片

**验证**：
- [ ] 基础文件创建成功
- [ ] 应用可以正常运行
- [ ] 界面显示正常

**输出**：
- 基础应用文件

---

#### 任务 1.7：生成项目文档（1 天）

**目标**：生成项目文档

**步骤**：
1. 创建 `README.md`：
   ```markdown
   # Legado iOS

   ## 项目简介
   Legado iOS 版本

   ## 技术栈
   - Swift 5.9+
   - SwiftUI
   - MVVM + Combine

   ## 开发环境
   - Xcode 15.0+
   - iOS 15.0+

   ## 项目结构
   [目录结构说明]

   ## 开发指南
   [开发指南]

   ## 测试
   [测试说明]
   ```
2. 创建 `阶段1_项目初始化报告.md`：
   - 项目创建过程
   - 配置说明
   - 依赖清单
   - 目录结构说明

**验证**：
- [ ] README.md 完整
- [ ] 项目文档完整
- [ ] 说明清晰

**输出**：
- `README.md`
- `阶段1_项目初始化报告.md`

---

### 阶段 1 验收检查清单

- [ ] Xcode 项目可以成功编译
- [ ] 所有依赖正常导入
- [ ] 项目结构符合设计要求
- [ ] 基础配置完成
- [ ] 应用可以正常运行
- [ ] 项目文档完整

### 阶段 1 输入文档

- `阶段0_技术方案确认.md`
- `IOS_设计说明书.md`
- `IOS_Android_Analyze.md`

### 阶段 1 输出文档

- `阶段1_项目初始化报告.md`
- `README.md`

### 阶段 1 后续阶段依赖

- 阶段 2（数据模型设计）依赖阶段 1 的项目结构
- 所有后续阶段依赖阶段 1 的项目配置

---

## 🚀 阶段 2：数据模型设计（1 周）

### 阶段目标

设计和实现所有数据模型。

### 前置条件

- [ ] 阶段 1 完成
- [ ] 项目结构完整
- [ ] 已阅读 `IOS_Android_Analyze.md` 的数据模型部分

### 输入

- `IOS_Android_Analyze.md` - 数据模型定义
- Android 版本的数据模型代码

### 输出

- 所有数据模型 Swift 文件
- 数据模型测试文件
- 数据模型文档

### 验收标准

- [ ] 所有数据模型实现完成
- [ ] 数据模型支持 Codable 协议
- [ ] 数据模型测试通过
- [ ] 数据模型文档完整

### 任务清单

#### 任务 2.1：实现 BookSource 模型（1 天）

**目标**：实现书源数据模型

**步骤**：
1. 创建 `App/Features/BookSource/Models/BookSource.swift`：
   ```swift
   import Foundation

   struct BookSource: Codable, Identifiable, Equatable {
       var id: String { bookSourceUrl }

       var bookSourceUrl: String = ""
       var bookSourceName: String = ""
       var bookSourceGroup: String?
       var bookSourceType: Int = 0
       var bookSourceComment: String?
       var loginUrl: String?
       var loginUi: String?
       var loginCheckJs: String?
       var concurrentRate: String?
       var header: String?
       var searchUrl: String?
       var ruleSearchUrl: String?
       var ruleBookInfo: String?
       var ruleToc: String?
       var ruleContent: String?
       var exploreUrl: String?
       var enabled: Bool = true
       var enabledCookieJar: Bool = false
       var lastUpdateTime: Int64 = 0
       var variableComment: String?
       var customOrder: Int = 0
       var respondTime: Int64 = 0

       enum CodingKeys: String, CodingKey {
           case bookSourceUrl
           case bookSourceName
           case bookSourceGroup
           case bookSourceType
           case bookSourceComment
           case loginUrl
           case loginUi
           case loginCheckJs
           case concurrentRate
           case header
           case searchUrl
           case ruleSearchUrl
           case ruleBookInfo
           case ruleToc
           case ruleContent
           case exploreUrl
           case enabled
           case enabledCookieJar
           case lastUpdateTime
           case variableComment
           case customOrder
           case respondTime
       }
   }
   ```
2. 创建 `App/Features/BookSource/Models/BookSource+Extensions.swift`：
   ```swift
   import Foundation

   extension BookSource {
       static let empty = BookSource()

       var isValid: Bool {
           return !bookSourceUrl.isEmpty && !bookSourceName.isEmpty
       }

       var headerDict: [String: String] {
           guard let headerData = header?.data(using: .utf8),
                 let dict = try? JSONSerialization.jsonObject(with: headerData) as? [String: String] else {
               return [:]
           }
           return dict
       }
   }
   ```

**验证**：
- [ ] BookSource 模型实现完成
- [ ] 支持 Codable 协议
- [ ] 扩展方法正常工作

**输出**：
- `BookSource.swift`
- `BookSource+Extensions.swift`

---

#### 任务 2.2：实现 Book 模型（1 天）

**目标**：实现书籍数据模型

**步骤**：
1. 创建 `App/Features/Reading/Models/Book.swift`：
   ```swift
   import Foundation

   struct Book: Codable, Identifiable, Equatable {
       var id: String { bookUrl }

       var bookUrl: String = ""
       var name: String = ""
       var author: String = ""
       var kind: String?
       var wordCount: String?
       var intro: String?
       var coverUrl: String?
       var tocUrl: String?
       var origin: String = ""
       var originName: String = ""
       var introUrl: String?
       var variable: String?
       var infoHtml: String?
       var infoHtmlUrl: String?
       var totalChapterNum: Int = 0
       var latestChapterTitle: String?
       var latestChapterUrl: String?
       var time: Int64 = 0
       var durChapterTitle: String?
       var durChapterIndex: Int = 0
       var durChapterTime: Int64 = 0
       var durChapterPos: Int = 0
       var useReplaceRule: Bool = false

       enum CodingKeys: String, CodingKey {
           case bookUrl
           case name
           case author
           case kind
           case wordCount
           case intro
           case coverUrl
           case tocUrl
           case origin
           case originName
           case introUrl
           case variable
           case infoHtml
           case infoHtmlUrl
           case totalChapterNum
           case latestChapterTitle
           case latestChapterUrl
           case time
           case durChapterTitle
           case durChapterIndex
           case durChapterTime
           case durChapterPos
           case useReplaceRule
       }
   }
   ```
2. 创建 `App/Features/Reading/Models/Book+Extensions.swift`：
   ```swift
   import Foundation

   extension Book {
       static let empty = Book()

       var isValid: Bool {
           return !bookUrl.isEmpty && !name.isEmpty && !author.isEmpty
       }

       var displayAuthor: String {
           return author.isEmpty ? "未知作者" : author
       }

       var displayWordCount: String {
           return wordCount ?? "未知字数"
       }
   }
   ```

**验证**：
- [ ] Book 模型实现完成
- [ ] 支持 Codable 协议
- [ ] 扩展方法正常工作

**输出**：
- `Book.swift`
- `Book+Extensions.swift`

---

#### 任务 2.3：实现 Chapter 模型（1 天）

**目标**：实现章节数据模型

**步骤**：
1. 创建 `App/Features/Reading/Models/Chapter.swift`：
   ```swift
   import Foundation

   struct Chapter: Codable, Identifiable, Equatable {
       var id: String { url }

       var url: String = ""
       var title: String = ""
       var index: Int = 0
       var tag: String?
       var volume: String?
       var resourceUrl: String?
       var pay: Bool = false
       var updateTime: Int64 = 0
       var bookUrl: String = ""

       enum CodingKeys: String, CodingKey {
           case url
           case title
           case index
           case tag
           case volume
           case resourceUrl
           case pay
           case updateTime
           case bookUrl
       }
   }
   ```
2. 创建 `App/Features/Reading/Models/Chapter+Extensions.swift`：
   ```swift
   import Foundation

   extension Chapter {
       static let empty = Chapter()

       var isValid: Bool {
           return !url.isEmpty && !title.isEmpty
       }

       var displayTitle: String {
           return title.isEmpty ? "第\(index + 1)章" : title
       }
   }
   ```

**验证**：
- [ ] Chapter 模型实现完成
- [ ] 支持 Codable 协议
- [ ] 扩展方法正常工作

**输出**：
- `Chapter.swift`
- `Chapter+Extensions.swift`

---

#### 任务 2.4：实现其他模型（1 天）

**目标**：实现其他数据模型

**步骤**：
1. 创建 `App/Features/BookSource/Models/SearchResult.swift`：
   ```swift
   import Foundation

   struct SearchResult: Codable, Identifiable {
       var id: String { bookUrl }
       var bookUrl: String
       var name: String
       var author: String
       var coverUrl: String?
       var intro: String?
       var kind: String?
       var wordCount: String?
       var lastChapter: String?
       var origin: String
       var originName: String
   }
   ```

2. 创建 `App/Features/Reading/Models/BookProgress.swift`：
   ```swift
   import Foundation

   struct BookProgress: Codable {
       var bookUrl: String
       var chapterIndex: Int
       var chapterPos: Int
       var updateTime: Int64

       static let empty = BookProgress(
           bookUrl: "",
           chapterIndex: 0,
           chapterPos: 0,
           updateTime: 0
       )
   }
   ```

3. 创建 `App/Features/TTS/Models/TTSConfig.swift`：
   ```swift
   import Foundation

   struct TTSConfig: Codable {
       var rate: Float
       var pitch: Float
       var voice: String
       var enabled: Bool

       static let `default` = TTSConfig(
           rate: 0.5,
           pitch: 1.0,
           voice: "zh-CN",
           enabled: true
       )
   }
   ```

**验证**：
- [ ] 所有模型实现完成
- [ ] 支持 Codable 协议
- [ ] 默认值正确

**输出**：
- `SearchResult.swift`
- `BookProgress.swift`
- `TTSConfig.swift`

---

#### 任务 2.5：编写数据模型测试（1 天）

**目标**：编写数据模型测试

**步骤**：
1. 创建 `Tests/Unit/Models/BookSourceTests.swift`：
   ```swift
   import XCTest
   @testable import Legado

   class BookSourceTests: XCTestCase {
       func testBookSourceCoding() throws {
           let source = BookSource(
               bookSourceUrl: "https://example.com",
               bookSourceName: "测试书源",
               enabled: true
           )

           let encoder = JSONEncoder()
           let data = try encoder.encode(source)

           let decoder = JSONDecoder()
           let decoded = try decoder.decode(BookSource.self, from: data)

           XCTAssertEqual(source.bookSourceUrl, decoded.bookSourceUrl)
           XCTAssertEqual(source.bookSourceName, decoded.bookSourceName)
           XCTAssertEqual(source.enabled, decoded.enabled)
       }

       func testBookSourceExtensions() {
           let source = BookSource(
               bookSourceUrl: "https://example.com",
               bookSourceName: "测试书源"
           )

           XCTAssertTrue(source.isValid)
           XCTAssertEqual(source.id, "https://example.com")
       }
   }
   ```
2. 创建 `Tests/Unit/Models/BookTests.swift`
3. 创建 `Tests/Unit/Models/ChapterTests.swift`

**验证**：
- [ ] 所有测试通过
- [ ] 测试覆盖主要功能

**输出**：
- 数据模型测试文件

---

#### 任务 2.6：生成数据模型文档（1 天）

**目标**：生成数据模型文档

**步骤**：
1. 创建 `阶段2_数据模型报告.md`：
   - 所有数据模型说明
   - 字段说明
   - 扩展方法说明
   - 测试结果

**验证**：
- [ ] 文档完整
- [ ] 说明清晰

**输出**：
- `阶段2_数据模型报告.md`

---

### 阶段 2 验收检查清单

- [ ] 所有数据模型实现完成
- [ ] 数据模型支持 Codable 协议
- [ ] 数据模型测试通过
- [ ] 数据模型文档完整

### 阶段 2 输入文档

- `IOS_Android_Analyze.md`
- Android 版本数据模型代码

### 阶段 2 输出文档

- `阶段2_数据模型报告.md`

### 阶段 2 后续阶段依赖

- 阶段 3（JavaScript 引擎）依赖 BookSource 模型
- 阶段 7（数据库层）依赖所有数据模型
- 阶段 8（核心功能实现）依赖所有数据模型

---

## 🚀 阶段 3：JavaScript 引擎（2 周）

### 阶段目标

实现 JavaScript 引擎和 Rhino API 兼容层。

### 前置条件

- [ ] 阶段 2 完成
- [ ] BookSource 模型实现完成
- [ ] 阶段 0 验证通过

### 输入

- `阶段0_兼容性报告.md`
- `IOS_Android_Analyze.md` - JavaScript 引擎部分
- BookSource 模型

### 输出

- LegadoJSEngine 实现
- JSJavaHelper 实现
- JavaScript 引擎测试
- JavaScript 引擎文档

### 验收标准

- [ ] JavaScript 引擎实现完成
- [ ] Rhino API 兼容层实现完成
- [ ] JavaScript 引擎测试通过
- [ ] 热门书源兼容率 > 95%

### 任务清单

#### 任务 3.1：实现 LegadoJSEngine（3 天）

**目标**：实现核心 JavaScript 引擎

**步骤**：
1. 创建 `App/Core/JSBridge/LegadoJSEngine.swift`：
   ```swift
   import Foundation
   import JavaScriptCore

   class LegadoJSEngine {
       private let context: JSContext
       private var currentSource: BookSource?
       private var currentBaseUrl: String?
       private var currentHtml: String?

       init() {
           self.context = JSContext()
           setupContext()
       }

       private func setupContext() {
           // 配置异常处理
           context.exceptionHandler = { [weak self] context, exception in
               print("JavaScript Error: \(exception ?? "")")
               self?.handleException(exception)
           }

           // 注入 Rhino API 兼容层
           let javaHelper = JSJavaHelper()
           context.globalObject.setValue(javaHelper, forProperty: "java")

           // 初始化全局变量
           context.globalObject.setValue("", forProperty: "baseUrl")
           context.globalObject.setValue(nil, forProperty: "source")
           context.globalObject.setValue(nil, forProperty: "result")
       }

       func evaluateRule(
           _ rule: String,
           source: BookSource,
           html: String? = nil,
           baseUrl: String? = nil
       ) -> String? {
           // 设置当前上下文
           self.currentSource = source
           self.currentBaseUrl = baseUrl ?? source.bookSourceUrl
           self.currentHtml = html

           // 设置全局变量
           context.globalObject.setValue(source, forProperty: "source")
           context.globalObject.setValue(self.currentBaseUrl ?? "", forProperty: "baseUrl")

           // 如果有 HTML，解析并设置 result
           if let html = html {
               context.globalObject.setValue(parseHTML(html), forProperty: "result")
           }

           // 执行规则
           let result = context.evaluateScript(rule)

           // 转换结果
           return convertResult(result)
       }

       private func parseHTML(_ html: String) -> JSValue? {
           // 将 HTML 解析为 JavaScript 可操作的对象
           // 这里需要实现 HTML 到 JS 对象的转换
           return nil
       }

       private func convertResult(_ result: JSValue?) -> String? {
           guard let result = result else { return nil }

           if result.isUndefined || result.isNull {
               return nil
           }

           if result.isString {
               return result.toString()
           }

           if result.isNumber {
               return result.toString()
           }

           if result.isBoolean {
               return result.toString()
           }

           if result.isArray {
               // 处理数组
               return result.toString()
           }

           if result.isObject {
               // 处理对象
               return result.toString()
           }

           return nil
       }

       private func handleException(_ exception: JSValue?) {
           // 处理 JavaScript 异常
           guard let exception = exception else { return }
           print("JavaScript Exception: \(exception)")
       }
   }
   ```

2. 创建 `App/Core/JSBridge/LegadoJSEngine+Extensions.swift`：
   ```swift
   import Foundation
   import JavaScriptCore

   extension LegadoJSEngine {
       func evaluateFunction(
           _ function: String,
           arguments: [Any] = []
       ) -> String? {
           let args = arguments.map { JSValue(object: $0, in: context) }
           let result = context.invokeMethod(function, withArguments: args)
           return convertResult(result)
       }

       func setVariable(_ name: String, value: Any) {
           context.globalObject.setValue(value, forProperty: name)
       }

       func getVariable(_ name: String) -> Any? {
           return context.globalObject.value(forProperty: name)
       }
   }
   ```

**验证**：
- [ ] LegadoJSEngine 实现完成
- [ ] 基础功能正常
- [ ] 异常处理正常

**输出**：
- `LegadoJSEngine.swift`
- `LegadoJSEngine+Extensions.swift`

---

#### 任务 3.2：实现 JSJavaHelper（3 天）

**目标**：实现 Rhino API 兼容层

**步骤**：
1. 创建 `App/Core/JSBridge/JSJavaHelper.swift`：
   ```swift
   import Foundation
   import JavaScriptCore
   import Alamofire

   @objc protocol JSJavaHelperProtocol: JSExport {
       func ajax(_ url: String, method: String) -> String?
       func put(_ key: String, value: Any)
       func get(_ key: String) -> Any?
       func log(_ message: String)
       func toast(_ message: String)
   }

   class JSJavaHelper: NSObject, JSJavaHelperProtocol {
       private let networkManager = NetworkManager.shared

       func ajax(_ url: String, method: String = "GET") -> String? {
           print("AJAX Request: \(url), Method: \(method)")

           // 同步执行网络请求
           let semaphore = DispatchSemaphore(value: 0)
           var result: String?

           Task {
               do {
                   let httpMethod: HTTPMethod = method.uppercased() == "POST" ? .post : .get
                   result = try await networkManager.request(url, method: httpMethod)
               } catch {
                   print("AJAX Error: \(error)")
               }
               semaphore.signal()
           }

           semaphore.wait()
           return result
       }

       func put(_ key: String, value: Any) {
           print("PUT: \(key) = \(value)")
           UserDefaults.standard.set(value, forKey: key)
       }

       func get(_ key: String) -> Any? {
           print("GET: \(key)")
           return UserDefaults.standard.value(forKey: key)
       }

       func log(_ message: String) {
           print("LOG: \(message)")
       }

       func toast(_ message: String) {
           print("TOAST: \(message)")
           // 在实际应用中，这里应该显示 Toast 提示
       }
   }
   ```

2. 创建 `App/Core/JSBridge/JSJavaHelper+Extensions.swift`：
   ```swift
   import Foundation
   import JavaScriptCore

   extension JSJavaHelper {
       func ajaxPost(_ url: String, body: String) -> String? {
           print("AJAX POST: \(url), Body: \(body)")

           let semaphore = DispatchSemaphore(value: 0)
           var result: String?

           Task {
               do {
                   result = try await networkManager.request(
                       url,
                       method: .post,
                       headers: [:],
                       body: body.data(using: .utf8)
                   )
               } catch {
                   print("AJAX POST Error: \(error)")
               }
               semaphore.signal()
           }

           semaphore.wait()
           return result
       }
   }
   ```

**验证**：
- [ ] JSJavaHelper 实现完成
- [ ] 所有 Rhino API 方法实现
- [ ] 网络请求正常

**输出**：
- `JSJavaHelper.swift`
- `JSJavaHelper+Extensions.swift`

---

#### 任务 3.3：实现 HTML 解析桥接（2 天）

**目标**：实现 HTML 到 JavaScript 的桥接

**步骤**：
1. 创建 `App/Core/JSBridge/JSHTMLElement.swift`：
   ```swift
   import Foundation
   import JavaScriptCore
   import SwiftSoup

   @objc class JSHTMLElement: NSObject {
       private let element: Element

       init(element: Element) {
           self.element = element
       }

       @objc var text: String {
           return try? element.text() ?? ""
       }

       @objc var html: String {
           return try? element.html() ?? ""
       }

       @objc func attr(_ name: String) -> String? {
           return try? element.attr(name)
       }

       @objc func select(_ css: String) -> [JSHTMLElement] {
           guard let elements = try? element.select(css) else {
               return []
           }
           return elements.map { JSHTMLElement(element: $0) }
       }

       @objc func selectFirst(_ css: String) -> JSHTMLElement? {
           guard let element = try? element.selectFirst(css) else {
               return nil
           }
           return JSHTMLElement(element: element)
       }
   }
   ```

2. 创建 `App/Core/JSBridge/JSHTMLDocument.swift`：
   ```swift
   import Foundation
   import JavaScriptCore
   import SwiftSoup

   @objc class JSHTMLDocument: NSObject {
       private let document: Document

       init(html: String) throws {
           self.document = try SwiftSoup.parse(html)
       }

       @objc func select(_ css: String) -> [JSHTMLElement] {
           guard let elements = try? document.select(css) else {
               return []
           }
           return elements.map { JSHTMLElement(element: $0) }
       }

       @objc func selectFirst(_ css: String) -> JSHTMLElement? {
           guard let element = try? document.selectFirst(css) else {
               return nil
           }
           return JSHTMLElement(element: element)
       }

       @objc func text() -> String {
           return try? document.text() ?? ""
       }

       @objc func html() -> String {
           return try? document.html() ?? ""
       }
   }
   ```

3. 更新 `LegadoJSEngine.swift` 的 `parseHTML` 方法：
   ```swift
   private func parseHTML(_ html: String) -> JSValue? {
       do {
           let document = try JSHTMLDocument(html: html)
           return JSValue(object: document, in: context)
       } catch {
           print("HTML Parse Error: \(error)")
           return nil
       }
   }
   ```

**验证**：
- [ ] HTML 解析桥接实现完成
- [ ] JavaScript 可以操作 HTML
- [ ] CSS 选择器正常工作

**输出**：
- `JSHTMLElement.swift`
- `JSHTMLDocument.swift`

---

#### 任务 3.4：编写 JavaScript 引擎测试（3 天）

**目标**：编写 JavaScript 引擎测试

**步骤**：
1. 创建 `Tests/Unit/Core/LegadoJSEngineTests.swift`：
   ```swift
   import XCTest
   @testable import Legado

   class LegadoJSEngineTests: XCTestCase {
       var engine: LegadoJSEngine!
       var testSource: BookSource!

       override func setUp() {
           super.setUp()
           engine = LegadoJSEngine()
           testSource = BookSource(
               bookSourceUrl: "https://example.com",
               bookSourceName: "测试书源"
           )
       }

       func testBasicJavaScript() {
           let result = engine.evaluateRule("1 + 1", source: testSource)
           XCTAssertEqual(result, "2")
       }

       func testFunctionCall() {
           let result = engine.evaluateRule("function add(a, b) { return a + b; } add(1, 2)", source: testSource)
           XCTAssertEqual(result, "3")
       }

       func testObjectOperation() {
           let result = engine.evaluateRule("var obj = {name: 'test'}; obj.name", source: testSource)
           XCTAssertEqual(result, "test")
       }

       func testArrayOperation() {
           let result = engine.evaluateRule("var arr = [1, 2, 3]; arr.length", source: testSource)
           XCTAssertEqual(result, "3")
       }

       func testRhinoAjax() {
           let result = engine.evaluateRule("java.ajax('https://example.com', 'GET')", source: testSource)
           XCTAssertNotNil(result)
       }

       func testRhinoPutGet() {
           engine.evaluateRule("java.put('testKey', 'testValue')", source: testSource)
           let result = engine.evaluateRule("java.get('testKey')", source: testSource)
           XCTAssertEqual(result, "testValue")
       }
   }
   ```

2. 创建 `Tests/Unit/Core/JSJavaHelperTests.swift`
3. 创建 `Tests/Integration/BookSourceRuleTests.swift`

**验证**：
- [ ] 所有测试通过
- [ ] 测试覆盖主要功能

**输出**：
- JavaScript 引擎测试文件

---

#### 任务 3.5：测试热门书源（3 天）

**目标**：测试热门书源的兼容性

**步骤**：
1. 准备至少 20 个热门书源
2. 创建测试脚本
3. 逐个测试书源规则
4. 统计兼容性
5. 记录不兼容的规则

**验证**：
- [ ] 热门书源兼容率 > 95%
- [ ] 不兼容规则记录完整

**输出**：
- 书源兼容性测试报告

---

#### 任务 3.6：生成 JavaScript 引擎文档（1 天）

**目标**：生成 JavaScript 引擎文档

**步骤**：
1. 创建 `阶段3_JavaScript引擎报告.md`：
   - JavaScript 引擎实现说明
   - Rhino API 兼容层说明
   - 测试结果
   - 兼容性报告

**验证**：
- [ ] 文档完整
- [ ] 说明清晰

**输出**：
- `阶段3_JavaScript引擎报告.md`

---

### 阶段 3 验收检查清单

- [ ] JavaScript 引擎实现完成
- [ ] Rhino API 兼容层实现完成
- [ ] JavaScript 引擎测试通过
- [ ] 热门书源兼容率 > 95%

### 阶段 3 输入文档

- `阶段0_兼容性报告.md`
- `IOS_Android_Analyze.md`
- BookSource 模型

### 阶段 3 输出文档

- `阶段3_JavaScript引擎报告.md`

### 阶段 3 后续阶段依赖

- 阶段 4（规则解析系统）依赖 JavaScript 引擎
- 阶段 8（核心功能实现）依赖 JavaScript 引擎

---

## 🚀 阶段 4：规则解析系统（1 周）

### 阶段目标

实现规则解析和执行系统。

### 前置条件

- [ ] 阶段 3 完成
- [ ] JavaScript 引擎实现完成

### 输入

- `IOS_Android_Analyze.md` - 规则系统部分
- `阶段3_JavaScript引擎报告.md`

### 输出

- RuleParser 实现
- RuleExecutor 实现
- 规则系统测试
- 规则系统文档

### 验收标准

- [ ] 规则解析器实现完成
- [ ] 规则执行器实现完成
- [ ] 所有规则类型支持
- [ ] 规则系统测试通过

### 任务清单

#### 任务 4.1：实现 RuleParser（1 天）

**目标**：实现规则解析器

**步骤**：
1. 创建 `App/Core/Engine/RuleType.swift`：
   ```swift
   enum RuleType {
       case defaultRule
       case xpath
       case json
       case regex
       case javascript

       static func parse(_ rule: String) -> (RuleType, String) {
           if rule.hasPrefix("<js>") {
               let content = String(rule.dropFirst(4).dropLast(5))
               return (.javascript, content)
           } else if rule.hasPrefix("@XPath:") {
               let content = String(rule.dropFirst(7))
               return (.xpath, content)
           } else if rule.hasPrefix("@Json:") {
               let content = String(rule.dropFirst(6))
               return (.json, content)
           } else if rule.hasPrefix("@Regex:") {
               let content = String(rule.dropFirst(7))
               return (.regex, content)
           } else if rule.hasPrefix("@") {
               let content = String(rule.dropFirst(1))
               return (.defaultRule, content)
           } else {
               return (.defaultRule, rule)
           }
       }
   }
   ```

2. 创建 `App/Core/Engine/RuleParser.swift`：
   ```swift
   import Foundation

   class RuleParser {
       func parseRule(_ rule: String) -> RuleInfo {
           let (type, content) = RuleType.parse(rule)
           let parts = content.split(separator: "@").map { String($0) }

           return RuleInfo(
               type: type,
               content: content,
               cssRule: parts.first ?? content,
               attrRule: parts.count > 1 ? parts[1] : "text",
               replaceRule: parts.count > 2 ? parts[2] : nil
           )
       }

       func parseRules(_ rules: String) -> [RuleInfo] {
           return rules.split(separator: "\n")
               .map { String($0).trimmingCharacters(in: .whitespaces) }
               .filter { !$0.isEmpty }
               .map { parseRule($0) }
       }
   }

   struct RuleInfo {
       let type: RuleType
       let content: String
       let cssRule: String
       let attrRule: String
       let replaceRule: String?
   }
   ```

**验证**：
- [ ] RuleParser 实现完成
- [ ] 所有规则类型解析正确

**输出**：
- `RuleType.swift`
- `RuleParser.swift`

---

#### 任务 4.2：实现 RuleExecutor（3 天）

**目标**：实现规则执行器

**步骤**：
1. 创建 `App/Core/Engine/RuleExecutor.swift`：
   ```swift
   import Foundation

   class RuleExecutor {
       private let jsEngine: LegadoJSEngine
       private let htmlParser: HTMLParser

       init(jsEngine: LegadoJSEngine, htmlParser: HTMLParser) {
           self.jsEngine = jsEngine
           self.htmlParser = htmlParser
       }

       func executeRule(
           _ rule: String,
           source: BookSource,
           html: String? = nil,
           baseUrl: String? = nil
       ) async throws -> String? {
           let ruleInfo = RuleParser().parseRule(rule)

           switch ruleInfo.type {
           case .javascript:
               return try await executeJSRule(ruleInfo, source: source, html: html, baseUrl: baseUrl)
           case .xpath:
               return try await executeXPathRule(ruleInfo, html: html)
           case .json:
               return try await executeJSONRule(ruleInfo, html: html)
           case .regex:
               return try await executeRegexRule(ruleInfo, html: html)
           case .defaultRule:
               return try await executeDefaultRule(ruleInfo, html: html)
           }
       }

       private func executeJSRule(
           _ ruleInfo: RuleInfo,
           source: BookSource,
           html: String?,
           baseUrl: String?
       ) async throws -> String? {
           return jsEngine.evaluateRule(ruleInfo.content, source: source, html: html, baseUrl: baseUrl)
       }

       private func executeXPathRule(
           _ ruleInfo: RuleInfo,
           html: String?
       ) async throws -> String? {
           guard let html = html else { return nil }
           return htmlParser.xpath(html, xpath: ruleInfo.cssRule)
       }

       private func executeJSONRule(
           _ ruleInfo: RuleInfo,
           html: String?
       ) async throws -> String? {
           guard let html = html else { return nil }
           return htmlParser.jsonPath(html, jsonPath: ruleInfo.cssRule)
       }

       private func executeRegexRule(
           _ ruleInfo: RuleInfo,
           html: String?
       ) async throws -> String? {
           guard let html = html else { return nil }
           return htmlParser.regex(html, regex: ruleInfo.cssRule)
       }

       private func executeDefaultRule(
           _ ruleInfo: RuleInfo,
           html: String?
       ) async throws -> String? {
           guard let html = html else { return nil }
           return htmlParser.css(html, css: ruleInfo.cssRule)
       }
   }
   ```

**验证**：
- [ ] RuleExecutor 实现完成
- [ ] 所有规则类型执行正常

**输出**：
- `RuleExecutor.swift`

---

#### 任务 4.3：实现 HTML 解析器（1 天）

**目标**：实现 HTML 解析器

**步骤**：
1. 创建 `App/Core/HTML/HTMLParser.swift`：
   ```swift
   import Foundation
   import SwiftSoup

   class HTMLParser {
       static let shared = HTMLParser()

       private init() {}

       func css(_ html: String, css: String) -> String? {
           guard let doc = try? SwiftSoup.parse(html),
                 let element = try? doc.selectFirst(css) else {
               return nil
           }
           return try? element.text()
       }

       func xpath(_ html: String, xpath: String) -> String? {
           guard let doc = try? SwiftSoup.parse(html),
                 let elements = try? doc.xpath(xpath),
                 let first = elements.first() else {
               return nil
           }
           return try? first.text()
       }

       func jsonPath(_ json: String, jsonPath: String) -> String? {
           // 实现 JSONPath 查询
           return nil
       }

       func regex(_ html: String, regex: String) -> String? {
           guard let regex = try? NSRegularExpression(pattern: regex) else {
               return nil
           }
           let range = NSRange(html.startIndex..., in: html)
           guard let match = regex.firstMatch(in: html, range: range),
                 let range = match.range(at: 1) else {
               return nil
           }
           return (html as NSString).substring(with: range)
       }
   }
   ```

**验证**：
- [ ] HTMLParser 实现完成
- [ ] 所有解析方法正常

**输出**：
- `HTMLParser.swift`

---

#### 任务 4.4：编写规则系统测试（2 天）

**目标**：编写规则系统测试

**步骤**：
1. 创建 `Tests/Unit/Core/RuleParserTests.swift`
2. 创建 `Tests/Unit/Core/RuleExecutorTests.swift`
3. 创建 `Tests/Integration/RuleSystemTests.swift`

**验证**：
- [ ] 所有测试通过
- [ ] 测试覆盖主要功能

**输出**：
- 规则系统测试文件

---

#### 任务 4.5：生成规则系统文档（1 天）

**目标**：生成规则系统文档

**步骤**：
1. 创建 `阶段4_规则系统报告.md`：
   - 规则系统实现说明
   - 规则类型说明
   - 测试结果

**验证**：
- [ ] 文档完整
- [ ] 说明清晰

**输出**：
- `阶段4_规则系统报告.md`

---

### 阶段 4 验收检查清单

- [ ] 规则解析器实现完成
- [ ] 规则执行器实现完成
- [ ] 所有规则类型支持
- [ ] 规则系统测试通过

### 阶段 4 输入文档

- `IOS_Android_Analyze.md`
- `阶段3_JavaScript引擎报告.md`

### 阶段 4 输出文档

- `阶段4_规则系统报告.md`

### 阶段 4 后续阶段依赖

- 阶段 8（核心功能实现）依赖规则系统

---

## 🚀 阶段 5：网络请求层（1 周）

### 阶段目标

实现网络请求层，支持 OkHttp 的核心功能。

### 前置条件

- [ ] 阶段 4 完成
- [ ] 项目依赖已配置（Alamofire）

### 输入

- `IOS_Android_Analyze.md` - 网络请求部分
- BookSource 模型

### 输出

- NetworkManager 实现
- 拦截器实现
- Cookie 管理器实现
- 网络层测试
- 网络层文档

### 验收标准

- [ ] NetworkManager 实现完成
- [ ] 拦截器链实现完成
- [ ] Cookie 管理正常
- [ ] 网络层测试通过

### 任务清单

#### 任务 5.1：实现 NetworkManager（2 天）

**目标**：实现网络请求管理器

**步骤**：
1. 创建 `App/Core/Network/NetworkManager.swift`：
   ```swift
   import Foundation
   import Alamofire

   class NetworkManager {
       static let shared = NetworkManager()

       private let session: Session
       private let timeout: TimeInterval = 30

       private init() {
           let configuration = URLSessionConfiguration.default
           configuration.timeoutIntervalForRequest = timeout
           configuration.timeoutIntervalForResource = timeout

           let interceptor = Interceptor(
               adapter: RequestAdapter { [weak self] request in
                   // 添加 Cookie
                   if let cookies = CookieManager.shared.getCookies(for: request.url) {
                       request.setValue(cookies, forHTTPHeaderField: "Cookie")
                   }
                   return .success(request)
               },
               retrier: RetryHandler()
           )

           session = Session(
               configuration: configuration,
               interceptor: interceptor
           )
       }

       func request(
           _ url: String,
           method: HTTPMethod = .get,
           headers: HTTPHeaders = [:],
           body: Data? = nil
       ) async throws -> String {
           let request = AF.request(
               url,
               method: method,
               parameters: nil,
               encoding: JSONEncoding.default,
               headers: headers
           )

           let response = await request.serializingData().response

           switch response.result {
           case .success(let data):
               // 保存 Cookie
               if let httpResponse = response.response,
                  let cookies = httpResponse.allHeaderFields["Set-Cookie"] as? [String] {
                   CookieManager.shared.saveCookies(for: url, cookies: cookies)
               }
               return String(data: data, encoding: .utf8) ?? ""
           case .failure(let error):
               throw error
           }
       }

       func download(
           _ url: String,
           destination: URL
       ) async throws -> URL {
           let destination: DownloadRequest.Destination = { _, _ in
               return (destination, [.removePreviousFile, .createIntermediateDirectories])
           }

           let request = AF.download(url, to: destination)
           let response = await request.serializingDownloadedFileURL().response

           switch response.result {
           case .success(let url):
               return url
           case .failure(let error):
               throw error
           }
       }
   }
   ```

**验证**：
- [ ] NetworkManager 实现完成
- [ ] 基础请求功能正常

**输出**：
- `NetworkManager.swift`

---

#### 任务 5.2：实现拦截器（2 天）

**目标**：实现请求拦截器

**步骤**：
1. 创建 `App/Core/Network/RetryHandler.swift`：
   ```swift
   import Foundation
   import Alamofire

   class RetryHandler: RequestRetrier {
       private let maxRetry = 3
       private let delay: TimeInterval = 1.0

       func retry(
           _ request: Request,
           for session: Session,
           dueTo error: Error,
           completion: @escaping (RetryResult) -> Void
       ) {
           guard request.retryCount < maxRetry else {
               completion(.doNotRetry)
               return
           }

           print("Retry request: \(request.request?.url?.absoluteString ?? ""), count: \(request.retryCount + 1)")
           completion(.retryWithDelay(delay))
       }
   }
   ```

2. 创建 `App/Core/Network/LoggingInterceptor.swift`：
   ```swift
   import Foundation
   import Alamofire

   class LoggingInterceptor: RequestInterceptor {
       func adapt(_ urlRequest: URLRequest, for session: Session, completion: @escaping (Result<URLRequest, Error>) -> Void) {
           print("Request: \(urlRequest.httpMethod ?? "") \(urlRequest.url?.absoluteString ?? "")")
           if let headers = urlRequest.allHTTPHeaderFields {
               print("Headers: \(headers)")
           }
           completion(.success(urlRequest))
       }

       func retry(_ request: Request, for session: Session, dueTo error: Error, completion: @escaping (RetryResult) -> Void) {
           print("Request failed: \(error)")
           completion(.doNotRetry)
       }
   }
   ```

**验证**：
- [ ] 拦截器实现完成
- [ ] 重试机制正常

**输出**：
- `RetryHandler.swift`
- `LoggingInterceptor.swift`

---

#### 任务 5.3：实现 Cookie 管理器（2 天）

**目标**：实现 Cookie 管理器

**步骤**：
1. 创建 `App/Core/Network/CookieManager.swift`：
   ```swift
   import Foundation

   class CookieManager {
       static let shared = CookieManager()

       private let userDefaults = UserDefaults.standard
       private let cookieKey = "cookies"

       private init() {}

       func saveCookies(for url: String, cookies: [String]) {
           var allCookies = getAllCookies()
           allCookies[url] = cookies
           userDefaults.set(allCookies, forKey: cookieKey)
       }

       func getCookies(for url: String) -> String? {
           guard let cookies = getAllCookies()[url] else {
               return nil
           }
           return cookies.joined(separator: "; ")
       }

       func clearCookies(for url: String) {
           var allCookies = getAllCookies()
           allCookies.removeValue(forKey: url)
           userDefaults.set(allCookies, forKey: cookieKey)
       }

       func clearAllCookies() {
           userDefaults.removeObject(forKey: cookieKey)
       }

       private func getAllCookies() -> [String: [String]] {
           return userDefaults.dictionary(forKey: cookieKey) as? [String: [String]] ?? [:]
       }
   }
   ```

**验证**：
- [ ] Cookie 管理器实现完成
- [ ] Cookie 保存和读取正常

**输出**：
- `CookieManager.swift`

---

#### 任务 5.4：编写网络层测试（1 天）

**目标**：编写网络层测试

**步骤**：
1. 创建 `Tests/Unit/Core/NetworkManagerTests.swift`
2. 创建 `Tests/Unit/Core/CookieManagerTests.swift`

**验证**：
- [ ] 所有测试通过
- [ ] 测试覆盖主要功能

**输出**：
- 网络层测试文件

---

#### 任务 5.5：生成网络层文档（1 天）

**目标**：生成网络层文档

**步骤**：
1. 创建 `阶段5_网络层报告.md`：
   - 网络层实现说明
   - 拦截器说明
   - Cookie 管理说明
   - 测试结果

**验证**：
- [ ] 文档完整
- [ ] 说明清晰

**输出**：
- `阶段5_网络层报告.md`

---

### 阶段 5 验收检查清单

- [ ] NetworkManager 实现完成
- [ ] 拦截器链实现完成
- [ ] Cookie 管理正常
- [ ] 网络层测试通过

### 阶段 5 输入文档

- `IOS_Android_Analyze.md`
- BookSource 模型

### 阶段 5 输出文档

- `阶段5_网络层报告.md`

### 阶段 5 后续阶段依赖

- 阶段 8（核心功能实现）依赖网络层

---

## 🚀 阶段 6：HTML 解析层（3 天）

### 阶段目标

完善 HTML 解析功能，支持所有需要的解析方法。

### 前置条件

- [ ] 阶段 5 完成
- [ ] SwiftSoup 依赖已配置

### 输入

- `IOS_Android_Analyze.md` - HTML 解析部分

### 输出

- 完整的 HTMLParser 实现
- 解析器测试
- 解析器文档

### 验收标准

- [ ] HTMLParser 实现完成
- [ ] 支持 XPath、CSS、Regex、JSONPath
- [ ] 解析器测试通过

### 任务清单

#### 任务 6.1：完善 HTMLParser（2 天）

**目标**：完善 HTML 解析器

**步骤**：
1. 更新 `App/Core/HTML/HTMLParser.swift`，添加更多解析方法：
   ```swift
   import Foundation
   import SwiftSoup

   class HTMLParser {
       static let shared = HTMLParser()

       private init() {}

       // CSS 选择器
       func css(_ html: String, css: String) -> String? {
           guard let doc = try? SwiftSoup.parse(html),
                 let element = try? doc.selectFirst(css) else {
               return nil
           }
           return try? element.text()
       }

       func cssList(_ html: String, css: String) -> [String] {
           guard let doc = try? SwiftSoup.parse(html),
                 let elements = try? doc.select(css) else {
               return []
           }
           return (try? elements.map { try $0.text() }) ?? []
       }

       // XPath 查询
       func xpath(_ html: String, xpath: String) -> String? {
           guard let doc = try? SwiftSoup.parse(html),
                 let elements = try? doc.xpath(xpath),
                 let first = elements.first() else {
               return nil
           }
           return try? first.text()
       }

       func xpathList(_ html: String, xpath: String) -> [String] {
           guard let doc = try? SwiftSoup.parse(html),
                 let elements = try? doc.xpath(xpath) else {
               return []
           }
           return (try? elements.map { try $0.text() }) ?? []
       }

       // 正则表达式
       func regex(_ html: String, regex: String) -> String? {
           guard let regex = try? NSRegularExpression(pattern: regex) else {
               return nil
           }
           let range = NSRange(html.startIndex..., in: html)
           guard let match = regex.firstMatch(in: html, range: range),
                 let range = match.range(at: 1) else {
               return nil
           }
           return (html as NSString).substring(with: range)
       }

       func regexList(_ html: String, regex: String) -> [String] {
           guard let regex = try? NSRegularExpression(pattern: regex) else {
               return []
           }
           let range = NSRange(html.startIndex..., in: html)
           let matches = regex.matches(in: html, range: range)
           return matches.compactMap { match -> String? in
               guard let range = match.range(at: 1) else { return nil }
               return (html as NSString).substring(with: range)
           }
       }

       // JSONPath 查询
       func jsonPath(_ json: String, jsonPath: String) -> String? {
           guard let data = json.data(using: .utf8),
                 let jsonObject = try? JSONSerialization.jsonObject(with: data) else {
               return nil
           }
           return readJSONPath(jsonObject, path: jsonPath)
       }

       func jsonPathList(_ json: String, jsonPath: String) -> [String] {
           guard let data = json.data(using: .utf8),
                 let jsonObject = try? JSONSerialization.jsonObject(with: data) else {
               return []
           }
           return readJSONPathList(jsonObject, path: jsonPath)
       }

       private func readJSONPath(_ json: Any, path: String) -> String? {
           // 简化的 JSONPath 实现
           let parts = path.split(separator: ".").map { String($0) }
           var current: Any = json

           for part in parts {
               if let dict = current as? [String: Any] {
                   current = dict[part] ?? NSNull()
               } else if let array = current as? [Any] {
                   if let index = Int(part), index < array.count {
                       current = array[index]
                   } else {
                       return nil
                   }
               } else {
                   return nil
               }
           }

           if let result = current as? String {
               return result
           } else if let result = current as? Int {
               return String(result)
           } else if current is NSNull {
               return nil
           } else {
               return String(describing: current)
           }
       }

       private func readJSONPathList(_ json: Any, path: String) -> [String] {
           // 简化的 JSONPath 列表实现
           let parts = path.split(separator: ".").map { String($0) }
           var current: Any = json

           for part in parts.dropLast() {
               if let dict = current as? [String: Any] {
                   current = dict[part] ?? NSNull()
               } else if let array = current as? [Any] {
                   if let index = Int(part), index < array.count {
                       current = array[index]
                   } else {
                       return []
                   }
               } else {
                   return []
               }
           }

           let lastPart = parts.last ?? ""
           if let dict = current as? [String: Any],
              let value = dict[lastPart] {
               if let array = value as? [Any] {
                   return array.compactMap { item -> String? in
                       if let string = item as? String {
                           return string
                       } else if let number = item as? Int {
                           return String(number)
                       }
                       return nil
                   }
               }
           }

           return []
       }
   }
   ```

**验证**：
- [ ] HTMLParser 实现完成
- [ ] 所有解析方法正常

**输出**：
- 更新的 `HTMLParser.swift`

---

#### 任务 6.2：编写解析器测试（1 天）

**目标**：编写解析器测试

**步骤**：
1. 创建 `Tests/Unit/Core/HTMLParserTests.swift`：
   ```swift
   import XCTest
   @testable import Legado

   class HTMLParserTests: XCTestCase {
       var parser: HTMLParser!

       override func setUp() {
           super.setUp()
           parser = HTMLParser.shared
       }

       func testCSS() {
           let html = "<html><body><div class='title'>Test</div></body></html>"
           let result = parser.css(html, css: ".title")
           XCTAssertEqual(result, "Test")
       }

       func testXPath() {
           let html = "<html><body><div class='title'>Test</div></body></html>"
           let result = parser.xpath(html, xpath: "//div[@class='title']/text()")
           XCTAssertEqual(result, "Test")
       }

       func testRegex() {
           let html = "<title>Test Title</title>"
           let result = parser.regex(html, regex: "<title>(.*?)</title>")
           XCTAssertEqual(result, "Test Title")
       }

       func testJSONPath() {
           let json = "{\"data\": {\"title\": \"Test\"}}"
           let result = parser.jsonPath(json, jsonPath: "$.data.title")
           XCTAssertEqual(result, "Test")
       }
   }
   ```

**验证**：
- [ ] 所有测试通过
- [ ] 测试覆盖主要功能

**输出**：
- `HTMLParserTests.swift`

---

#### 任务 6.3：生成解析器文档（1 天）

**目标**：生成解析器文档

**步骤**：
1. 创建 `阶段6_解析器报告.md`：
   - 解析器实现说明
   - 解析方法说明
   - 测试结果

**验证**：
- [ ] 文档完整
- [ ] 说明清晰

**输出**：
- `阶段6_解析器报告.md`

---

### 阶段 6 验收检查清单

- [ ] HTMLParser 实现完成
- [ ] 支持 XPath、CSS、Regex、JSONPath
- [ ] 解析器测试通过

### 阶段 6 输入文档

- `IOS_Android_Analyze.md`

### 阶段 6 输出文档

- `阶段6_解析器报告.md`

### 阶段 6 后续阶段依赖

- 阶段 8（核心功能实现）依赖解析器

---

## 🚀 阶段 7：数据库层（1 周）

### 阶段目标

实现数据库层，支持数据持久化。

### 前置条件

- [ ] 阶段 2 完成
- [ ] 所有数据模型实现完成
- [ ] GRDB.swift 依赖已配置

### 输入

- `IOS_Android_Analyze.md` - 数据库部分
- 所有数据模型

### 输出

- DatabaseManager 实现
- 数据库迁移脚本
- 数据库测试
- 数据库文档

### 验收标准

- [ ] DatabaseManager 实现完成
- [ ] 数据库迁移正常
- [ ] CRUD 操作正常
- [ ] 数据库测试通过

### 任务清单

#### 任务 7.1：实现 DatabaseManager（3 天）

**目标**：实现数据库管理器

**步骤**：
1. 创建 `App/Core/Database/DatabaseManager.swift`：
   ```swift
   import Foundation
   import GRDB

   class DatabaseManager {
       static let shared = DatabaseManager()

       private let db: DatabasePool

       private init() {
           let path = NSSearchPathForDirectoriesInDomains(
               .documentDirectory,
               .userDomainMask,
               true
           ).first! + "/legado.db"

           var config = Configuration()
           config.prepareDatabase { db in
               try db.execute(sql: "PRAGMA foreign_keys = ON")
           }

           db = try! DatabasePool(path: path, configuration: config)

           try! migrator.migrate(db)
       }

       private var migrator: DatabaseMigrator {
           var migrator = DatabaseMigrator()

           migrator.registerMigration("v1") { db in
               try db.create(table: "book_source") { t in
                   t.column("bookSourceUrl", .text).primaryKey()
                   t.column("bookSourceName", .text).notNull()
                   t.column("bookSourceGroup", .text)
                   t.column("bookSourceType", .integer).defaults(to: 0)
                   t.column("bookSourceComment", .text)
                   t.column("loginUrl", .text)
                   t.column("loginUi", .text)
                   t.column("loginCheckJs", .text)
                   t.column("concurrentRate", .text)
                   t.column("header", .text)
                   t.column("searchUrl", .text)
                   t.column("ruleSearchUrl", .text)
                   t.column("ruleBookInfo", .text)
                   t.column("ruleToc", .text)
                   t.column("ruleContent", .text)
                   t.column("exploreUrl", .text)
                   t.column("enabled", .boolean).defaults(to: true)
                   t.column("enabledCookieJar", .boolean).defaults(to: false)
                   t.column("lastUpdateTime", .integer).defaults(to: 0)
                   t.column("variableComment", .text)
                   t.column("customOrder", .integer).defaults(to: 0)
                   t.column("respondTime", .integer).defaults(to: 0)
               }

               try db.create(table: "book") { t in
                   t.column("bookUrl", .text).primaryKey()
                   t.column("name", .text).notNull()
                   t.column("author", .text).notNull()
                   t.column("kind", .text)
                   t.column("wordCount", .text)
                   t.column("intro", .text)
                   t.column("coverUrl", .text)
                   t.column("tocUrl", .text)
                   t.column("origin", .text).notNull()
                   t.column("originName", .text)
                   t.column("introUrl", .text)
                   t.column("variable", .text)
                   t.column("infoHtml", .text)
                   t.column("infoHtmlUrl", .text)
                   t.column("totalChapterNum", .integer).defaults(to: 0)
                   t.column("latestChapterTitle", .text)
                   t.column("latestChapterUrl", .text)
                   t.column("time", .integer).defaults(to: 0)
                   t.column("durChapterTitle", .text)
                   t.column("durChapterIndex", .integer).defaults(to: 0)
                   t.column("durChapterTime", .integer).defaults(to: 0)
                   t.column("durChapterPos", .integer).defaults(to: 0)
                   t.column("useReplaceRule", .boolean).defaults(to: false)
               }

               try db.create(table: "book_chapter") { t in
                   t.column("url", .text).primaryKey()
                   t.column("title", .text).notNull()
                   t.column("index", .integer).notNull()
                   t.column("tag", .text)
                   t.column("volume", .text)
                   t.column("resourceUrl", .text)
                   t.column("pay", .boolean).defaults(to: false)
                   t.column("updateTime", .integer).defaults(to: 0)
                   t.column("bookUrl", .text).notNull()
                       .references("book", column: "bookUrl", onDelete: .cascade)
               }
           }

           return migrator
       }

       // BookSource 操作
       func saveBookSource(_ source: BookSource) throws {
           try db.write { db in
               try source.insert(db)
           }
       }

       func getBookSources() -> [BookSource] {
           try! db.read { db in
               try BookSource.fetchAll(db)
           }
       }

       func getEnabledSources() -> [BookSource] {
           try! db.read { db in
               try BookSource
                   .filter(Column("enabled") == true)
                   .order(Column("customOrder").asc)
                   .fetchAll(db)
           }
       }

       func deleteBookSource(_ url: String) throws {
           try db.write { db in
               try BookSource.filter(Column("bookSourceUrl") == url).deleteAll(db)
           }
       }

       // Book 操作
       func saveBook(_ book: Book) throws {
           try db.write { db in
               try book.insert(db)
           }
       }

       func getBooks() -> [Book] {
           try! db.read { db in
               try Book
                   .order(Column("durChapterTime").desc)
                   .fetchAll(db)
           }
       }

       func getBook(_ url: String) -> Book? {
           try! db.read { db in
               try Book.filter(Column("bookUrl") == url).fetchOne(db)
           }
       }

       func deleteBook(_ url: String) throws {
           try db.write { db in
               try Book.filter(Column("bookUrl") == url).deleteAll(db)
           }
       }

       // BookChapter 操作
       func saveChapters(_ chapters: [BookChapter]) throws {
           try db.write { db in
               for chapter in chapters {
                   try chapter.insert(db, onConflict: .replace)
               }
           }
       }

       func getChapters(_ bookUrl: String) -> [BookChapter] {
           try! db.read { db in
               try BookChapter
                   .filter(Column("bookUrl") == bookUrl)
                   .order(Column("index").asc)
                   .fetchAll(db)
           }
       }

       func getChapter(_ url: String) -> BookChapter? {
           try! db.read { db in
               try BookChapter.filter(Column("url") == url).fetchOne(db)
           }
       }

       func deleteChapters(_ bookUrl: String) throws {
           try db.write { db in
               try BookChapter.filter(Column("bookUrl") == bookUrl).deleteAll(db)
           }
       }
   }
   ```

2. 为数据模型添加 GRDB 支持：
   ```swift
   // App/Features/BookSource/Models/BookSource+GRDB.swift
   import Foundation
   import GRDB

   extension BookSource: FetchableRecord, PersistableRecord {
       enum Columns {
           static let bookSourceUrl = Column(CodingKeys.bookSourceUrl)
           static let bookSourceName = Column(CodingKeys.bookSourceName)
           // ... 其他列
       }

       init(row: Row) {
           bookSourceUrl = row[Columns.bookSourceUrl]
           bookSourceName = row[Columns.bookSourceName]
           // ... 其他字段
       }

       func encode(to container: inout PersistenceContainer) {
           container[Columns.bookSourceUrl] = bookSourceUrl
           container[Columns.bookSourceName] = bookSourceName
           // ... 其他字段
       }
   }

   // App/Features/Reading/Models/Book+GRDB.swift
   // App/Features/Reading/Models/Chapter+GRDB.swift
   ```

**验证**：
- [ ] DatabaseManager 实现完成
- [ ] 数据库迁移正常
- [ ] CRUD 操作正常

**输出**：
- `DatabaseManager.swift`
- 数据模型 GRDB 扩展

---

#### 任务 7.2：编写数据库测试（2 天）

**目标**：编写数据库测试

**步骤**：
1. 创建 `Tests/Unit/Core/DatabaseManagerTests.swift`：
   ```swift
   import XCTest
   @testable import Legado

   class DatabaseManagerTests: XCTestCase {
       var db: DatabaseManager!

       override func setUp() {
           super.setUp()
           db = DatabaseManager.shared
       }

       func testSaveAndGetBookSource() throws {
           let source = BookSource(
               bookSourceUrl: "https://test.com",
               bookSourceName: "测试书源"
           )

           try db.saveBookSource(source)

           let sources = db.getBookSources()
           XCTAssertTrue(sources.contains(where: { $0.bookSourceUrl == "https://test.com" }))
       }

       func testUpdateBookSource() throws {
           let source = BookSource(
               bookSourceUrl: "https://test.com",
               bookSourceName: "测试书源"
           )

           try db.saveBookSource(source)

           var updatedSource = source
           updatedSource.bookSourceName = "更新后的书源"

           try db.saveBookSource(updatedSource)

           let sources = db.getBookSources()
           let retrieved = sources.first { $0.bookSourceUrl == "https://test.com" }
           XCTAssertEqual(retrieved?.bookSourceName, "更新后的书源")
       }

       func testDeleteBookSource() throws {
           let source = BookSource(
               bookSourceUrl: "https://test.com",
               bookSourceName: "测试书源"
           )

           try db.saveBookSource(source)
           try db.deleteBookSource("https://test.com")

           let sources = db.getBookSources()
           XCTAssertFalse(sources.contains(where: { $0.bookSourceUrl == "https://test.com" }))
       }
   }
   ```

**验证**：
- [ ] 所有测试通过
- [ ] 测试覆盖主要功能

**输出**：
- 数据库测试文件

---

#### 任务 7.3：生成数据库文档（1 天）

**目标**：生成数据库文档

**步骤**：
1. 创建 `阶段7_数据库报告.md`：
   - 数据库设计说明
   - 表结构说明
   - CRUD 操作说明
   - 测试结果

**验证**：
- [ ] 文档完整
- [ ] 说明清晰

**输出**：
- `阶段7_数据库报告.md`

---

### 阶段 7 验收检查清单

- [ ] DatabaseManager 实现完成
- [ ] 数据库迁移正常
- [ ] CRUD 操作正常
- [ ] 数据库测试通过

### 阶段 7 输入文档

- `IOS_Android_Analyze.md`
- 所有数据模型

### 阶段 7 输出文档

- `阶段7_数据库报告.md`

### 阶段 7 后续阶段依赖

- 阶段 8（核心功能实现）依赖数据库层

---

## 🚀 阶段 8：核心功能实现（6 周）

### 阶段目标

实现所有核心功能。

### 前置条件

- [ ] 阶段 3-7 全部完成
- [ ] 所有基础组件实现完成

### 输入

- `IOS_设计说明书.md`
- `IOS_Android_Analyze.md`
- 所有前置阶段的输出

### 输出

- 书源管理功能
- 书架管理功能
- 搜索功能
- 阅读功能
- TTS 功能
- 本地文件阅读功能
- 核心功能测试
- 核心功能文档

### 验收标准

- [ ] 所有核心功能实现完成
- [ ] 功能与 Android 版本一致
- [ ] 核心功能测试通过
- [ ] 性能指标达标

### 任务清单

#### 任务 8.1：实现书源管理功能（1 周）

**目标**：实现书源导入、导出、编辑功能

**步骤**：
1. 创建 `App/Features/BookSource/ViewModels/BookSourceViewModel.swift`
2. 创建 `App/Features/BookSource/Views/BookSourceListView.swift`
3. 创建 `App/Features/BookSource/Views/BookSourceEditView.swift`
4. 创建 `App/Features/BookSource/Views/BookSourceImportView.swift`

**验证**：
- [ ] 书源列表显示正常
- [ ] 书源导入导出正常
- [ ] 书源编辑功能正常

**输出**：
- 书源管理相关文件

---

#### 任务 8.2：实现书架管理功能（1 周）

**目标**：实现书架列表、添加、删除功能

**步骤**：
1. 创建 `App/Features/Reading/ViewModels/BookshelfViewModel.swift`
2. 创建 `App/Features/Reading/Views/BookshelfView.swift`
3. 创建 `App/Features/Reading/Views/BookCoverView.swift`

**验证**：
- [ ] 书架列表显示正常
- [ ] 书籍添加删除正常
- [ ] 书籍封面加载正常

**输出**：
- 书架管理相关文件

---

#### 任务 8.3：实现搜索功能（1 周）

**目标**：实现书籍搜索功能

**步骤**：
1. 创建 `App/Features/Reading/ViewModels/SearchViewModel.swift`
2. 创建 `App/Features/Reading/Views/SearchView.swift`
3. 创建 `App/Features/Reading/Views/SearchResultView.swift`

**验证**：
- [ ] 搜索功能正常
- [ ] 搜索结果显示正常
- [ ] 搜索性能达标

**输出**：
- 搜索相关文件

---

#### 任务 8.4：实现阅读功能（1.5 周）

**目标**：实现章节列表、内容阅读功能

**步骤**：
1. 创建 `App/Features/Reading/ViewModels/ReadingViewModel.swift`
2. 创建 `App/Features/Reading/Views/ReadingView.swift`
3. 创建 `App/Features/Reading/Views/ChapterListView.swift`
4. 创建 `App/Features/Reading/Views/WebView.swift`

**验证**：
- [ ] 章节列表显示正常
- [ ] 章节内容加载正常
- [ ] 翻页功能正常

**输出**：
- 阅读相关文件

---

#### 任务 8.5：实现 TTS 功能（1 周）

**目标**：实现 TTS 听书功能

**步骤**：
1. 创建 `App/Features/TTS/ViewModels/TTSViewModel.swift`
2. 创建 `App/Features/TTS/Views/TTSControlView.swift`
3. 创建 `App/Features/TTS/Models/TTSManager.swift`

**验证**：
- [ ] TTS 播放正常
- [ ] 语速音调调节正常
- [ ] 后台播放正常

**输出**：
- TTS 相关文件

---

#### 任务 8.6：实现本地文件阅读功能（0.5 周）

**目标**：实现本地 TXT、EPUB 文件阅读

**步骤**：
1. 创建 `App/Features/Reading/ViewModels/LocalFileViewModel.swift`
2. 创建 `App/Features/Reading/Views/LocalFileView.swift`

**验证**：
- [ ] 文件选择正常
- [ ] TXT 文件阅读正常
- [ ] EPUB 文件阅读正常

**输出**：
- 本地文件阅读相关文件

---

#### 任务 8.7：编写核心功能测试（1 周）

**目标**：编写核心功能测试

**步骤**：
1. 创建 `Tests/Integration/BookSourceTests.swift`
2. 创建 `Tests/Integration/BookshelfTests.swift`
3. 创建 `Tests/Integration/SearchTests.swift`
4. 创建 `Tests/Integration/ReadingTests.swift`
5. 创建 `Tests/Integration/TTSTests.swift`

**验证**：
- [ ] 所有测试通过
- [ ] 测试覆盖主要功能

**输出**：
- 核心功能测试文件

---

#### 任务 8.8：生成核心功能文档（1 周）

**目标**：生成核心功能文档

**步骤**：
1. 创建 `阶段8_核心功能报告.md`：
   - 功能实现说明
   - 功能对比（iOS vs Android）
   - 测试结果
   - 性能指标

**验证**：
- [ ] 文档完整
- [ ] 说明清晰

**输出**：
- `阶段8_核心功能报告.md`

---

### 阶段 8 验收检查清单

- [ ] 所有核心功能实现完成
- [ ] 功能与 Android 版本一致
- [ ] 核心功能测试通过
- [ ] 性能指标达标

### 阶段 8 输入文档

- `IOS_设计说明书.md`
- `IOS_Android_Analyze.md`
- 所有前置阶段的输出

### 阶段 8 输出文档

- `阶段8_核心功能报告.md`

### 阶段 8 后续阶段依赖

- 阶段 9（测试和优化）依赖核心功能

---

## 🚀 阶段 9：测试和优化（3 周）

### 阶段目标

进行全面测试和性能优化。

### 前置条件

- [ ] 阶段 8 完成
- [ ] 所有核心功能实现完成

### 输入

- `IOS_设计说明书.md`
- `阶段8_核心功能报告.md`

### 输出

- 兼容性测试报告
- 性能测试报告
- 优化后的代码
- 测试和优化文档

### 验收标准

- [ ] 兼容性测试通过
- [ ] 性能测试通过
- [ ] 所有已知问题修复
- [ ] 性能指标达标

### 任务清单

#### 任务 9.1：兼容性测试（1 周）

**目标**：测试书源兼容性

**步骤**：
1. 导入至少 100 个书源
2. 测试每个书源的搜索功能
3. 测试每个书源的阅读功能
4. 统计兼容性
5. 记录不兼容的书源

**验证**：
- [ ] 书源兼容率 > 95%
- [ ] 不兼容书源记录完整

**输出**：
- 兼容性测试报告

---

#### 任务 9.2：性能测试（1 周）

**目标**：测试应用性能

**步骤**：
1. 测试应用启动时间
2. 测试搜索响应时间
3. 测试页面加载时间
4. 测试内存使用
5. 测试电池消耗

**验证**：
- [ ] 启动时间 < 2 秒
- [ ] 搜索响应时间 < 3 秒
- [ ] 页面加载时间 < 2 秒
- [ ] 内存使用 < 100MB

**输出**：
- 性能测试报告

---

#### 任务 9.3：性能优化（1 周）

**目标**：优化应用性能

**步骤**：
1. 优化图片加载
2. 优化网络请求
3. 优化数据库查询
4. 优化内存使用
5. 优化 UI 渲染

**验证**：
- [ ] 性能指标达标
- [ ] 无明显卡顿

**输出**：
- 优化后的代码

---

#### 任务 9.4：生成测试和优化文档（1 周）

**目标**：生成测试和优化文档

**步骤**：
1. 创建 `阶段9_测试和优化报告.md`：
   - 兼容性测试结果
   - 性能测试结果
   - 优化说明
   - 性能指标对比

**验证**：
- [ ] 文档完整
- [ ] 说明清晰

**输出**：
- `阶段9_测试和优化报告.md`

---

### 阶段 9 验收检查清单

- [ ] 兼容性测试通过
- [ ] 性能测试通过
- [ ] 所有已知问题修复
- [ ] 性能指标达标

### 阶段 9 输入文档

- `IOS_设计说明书.md`
- `阶段8_核心功能报告.md`

### 阶段 9 输出文档

- `阶段9_测试和优化报告.md`

### 阶段 9 后续阶段依赖

- 阶段 10（发布准备）依赖测试和优化

---

## 🚀 阶段 10：发布准备（1 周）

### 阶段目标

准备应用发布。

### 前置条件

- [ ] 阶段 9 完成
- [ ] 所有测试通过

### 输入

- `阶段9_测试和优化报告.md`
- App Store 发布指南

### 输出

- 发布版本
- App Store 截图
- 应用描述
- 发布文档

### 验收标准

- [ ] 发布版本可以正常安装
- [ ] App Store 材料准备完成
- [ ] 发布文档完整

### 任务清单

#### 任务 10.1：准备发布版本（2 天）

**目标**：准备发布版本

**步骤**：
1. 更新版本号
2. 更新构建号
3. 生成发布证书
4. 构建 Release 版本
5. 测试发布版本

**验证**：
- [ ] 发布版本可以正常安装
- [ ] 所有功能正常

**输出**：
- 发布版本

---

#### 任务 10.2：准备 App Store 材料（2 天）

**目标**：准备 App Store 发布材料

**步骤**：
1. 准备应用图标
2. 准备应用截图
3. 准备应用描述
4. 准备关键词
5. 准备审核说明

**验证**：
- [ ] 所有材料准备完成
- [ ] 材料符合 App Store 要求

**输出**：
- App Store 材料

---

#### 任务 10.3：生成发布文档（1 天）

**目标**：生成发布文档

**步骤**：
1. 创建 `阶段10_发布报告.md`：
   - 版本说明
   - 更新日志
   - 发布检查清单
   - 发布步骤

**验证**：
- [ ] 文档完整
- [ ] 说明清晰

**输出**：
- `阶段10_发布报告.md`

---

### 阶段 10 验收检查清单

- [ ] 发布版本可以正常安装
- [ ] App Store 材料准备完成
- [ ] 发布文档完整

### 阶段 10 输入文档

- `阶段9_测试和优化报告.md`
- App Store 发布指南

### 阶段 10 输出文档

- `阶段10_发布报告.md`

---

## 📋 冷启动检查清单

### 任意阶段冷启动前的检查

在开始任意阶段之前，必须完成以下检查：

#### 1. 前置条件检查

- [ ] 前置阶段是否全部完成？
- [ ] 前置阶段的输出文档是否齐全？
- [ ] 前置阶段的验收标准是否全部通过？

#### 2. 环境检查

- [ ] Xcode 版本是否符合要求？
- [ ] Swift 版本是否符合要求？
- [ ] 所有依赖是否已安装？
- [ ] 项目是否可以成功编译？

#### 3. 输入文档检查

- [ ] 阶段输入文档是否齐全？
- [ ] 输入文档是否已阅读？
- [ ] 输入文档是否理解？

#### 4. 任务清单检查

- [ ] 任务清单是否完整？
- [ ] 每个任务的步骤是否清晰？
- [ ] 每个任务的验证标准是否明确？

#### 5. 输出文档检查

- [ ] 阶段输出文档是否明确？
- [ ] 输出文档的格式是否清楚？
- [ ] 输出文档的内容要求是否明确？

### 冷启动流程

1. **检查前置条件**
   - 确认前置阶段已完成
   - 确认前置阶段的验收标准已通过

2. **检查环境**
   - 确认开发环境符合要求
   - 确认项目可以成功编译

3. **阅读输入文档**
   - 阅读所有输入文档
   - 理解输入文档的内容

4. **理解任务清单**
   - 理解每个任务的目标
   - 理解每个任务的步骤
   - 理解每个任务的验证标准

5. **开始执行**
   - 按照任务清单执行
   - 完成每个任务的验证
   - 记录遇到的问题

6. **生成输出文档**
   - 生成阶段报告
   - 记录测试结果
   - 记录遇到的问题和解决方案

---

## 📊 质量保证标准

### 代码质量标准

- [ ] 代码符合 Swift 编码规范
- [ ] 所有公开 API 有文档注释
- [ ] 代码通过 SwiftLint 检查
- [ ] 代码通过单元测试
- [ ] 代码通过集成测试

### 功能质量标准

- [ ] 所有功能与 Android 版本一致
- [ ] 所有功能测试通过
- [ ] 兼容性测试通过
- [ ] 性能测试通过

### 文档质量标准

- [ ] 所有阶段报告完整
- [ ] 所有文档说明清晰
- [ ] 所有文档格式统一
- [ ] 所有文档准确无误

---

## 🎯 成功标准

### 功能完整性

- ✅ 所有核心功能都已实现
- ✅ 所有功能都与 Android 版本兼容
- ✅ 所有功能都经过测试

### 性能标准

- ✅ 搜索响应时间 < 3 秒
- ✅ 页面加载时间 < 2 秒
- ✅ 应用启动时间 < 2 秒
- ✅ 内存使用 < 100MB

### 兼容性标准

- ✅ 书源兼容率 > 95%
- ✅ 搜索成功率 > 90%
- ✅ 支持 iOS 15.0+

### 用户体验标准

- ✅ 用户迁移成本 = 0
- ✅ 功能完整度 > 80%
- ✅ 用户满意度 > 4.0/5.0

---

## 📝 问题记录和解决

### 问题记录模板

```markdown
### 问题 [编号]

**问题描述**：
[问题描述]

**影响范围**：
[影响范围]

**严重程度**：
- [ ] 高（阻塞开发）
- [ ] 中（影响功能）
- [ ] 低（优化项）

**解决方案**：
[解决方案]

**解决状态**：
- [ ] 已解决
- [ ] 待解决
- [ ] 已记录

**解决时间**：
[解决时间]
```

---

## 📞 联系方式

如有问题或建议，请参考：
- 官方网站: https://gedoor.github.io
- 帮助文档: https://www.yuque.com/legado/wiki
- Telegram 群组: https://t.me/yueduguanfang
- Discord: https://discord.gg/VtUfRyzRXn

---

**文档更新时间**：2025年12月28日
**版本**：v1.0
**总开发时间**：4-5 个月