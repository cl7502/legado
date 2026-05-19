# Legado iOS 版本设计说明书

> **重要提示**：本文档是给 AI 实现的精确设计说明书，AI 必须严格按照本文档实现，不得偏离、不得幻想、不得添加未明确指定的功能。

---

## 📋 文档说明

**文档目的**：为 AI 提供精确、详细的实现指导，确保 iOS 版本准确实现设计目标。

**使用原则**：
1. ✅ 必须严格按照本文档实现
2. ❌ 不得偏离设计目标
3. ❌ 不得添加未明确指定的功能
4. ❌ 不得假设或幻想未说明的功能
5. ✅ 遇到不明确的地方，必须询问而不是自行决定

**版本信息**：
- 版本：v1.0
- 日期：2025年12月28日
- 方案：纯 iOS 原生开发

---

## 🎯 项目目标（必须实现）

### 核心目标（不可偏离）

**目标 1**：直接使用所有现有的书源文件
- iOS 版本必须能够导入和使用 Android 版本的书源文件
- 书源文件格式必须完全兼容
- 不得修改书源文件格式

**目标 2**：保持与 Android 版本完全兼容的用户体验
- 用户操作流程必须与 Android 版本一致
- 功能实现方式必须与 Android 版本一致
- 用户体验不得低于 Android 版本

**目标 3**：利用现有的书源生态和社区资源
- 必须支持现有书源的所有规则类型
- 不得限制书源规则的使用
- 必须保持与社区书源的兼容性

**目标 4**：快速开发，快速上线
- 开发周期：4-5 个月
- 技术栈：纯 iOS 原生，不使用跨平台框架
- 优先保证核心功能的稳定性

### 非目标（不要实现）

以下功能明确不在 v1.0 范围内，AI 不得实现：
1. ❌ 完整的 Web 服务功能（HTTP API、WebSocket）
2. ❌ 复杂的第三方集成
3. ❌ 高级调试工具
4. ❌ 音频书籍播放功能（MP3 等音频格式书籍）
5. ❌ RSS 订阅功能（作为 v1.1 功能）
6. ❌ iCloud 同步功能（作为 v1.1 功能）
7. ❌ 快捷指令集成（作为 v1.1 功能）

---

## 📦 功能范围（必须实现）

### 核心功能（P0 - 必须实现）

#### 1. 书源规则执行引擎

**功能描述**：解析和执行现有书源规则

**必须支持的规则类型**：
- `@@` 默认规则
- `@XPath:` XPath 规则
- `@Json:` JSON 规则
- `:` 正则规则
- `<js>` JavaScript 规则

**实现要求**：
- 使用 JavaScriptCore 引擎
- 实现 Rhino API 兼容层
- 支持所有书源规则语法
- 规则执行结果必须与 Android 版本一致

**技术约束**：
- JavaScript 引擎：JavaScriptCore（iOS 内置）
- 不得使用其他 JavaScript 引擎
- 必须实现 Rhino API 兼容层

#### 2. 基础阅读功能

**功能描述**：搜索、阅读、书架管理

**必须实现的功能**：
- 书籍搜索（使用书源规则）
- 书籍详情展示
- 章节列表
- 章节内容阅读
- 书架管理（添加、删除、排序）
- 阅读进度保存

**实现要求**：
- 使用 SwiftUI 实现界面
- 遵循 iOS 设计规范
- 支持深色模式
- 支持横屏阅读

#### 3. 书源导入导出

**功能描述**：兼容现有书源文件格式

**必须实现的功能**：
- 导入书源文件（.json 格式）
- 导出书源文件（.json 格式）
- 书源列表展示
- 书源编辑功能
- 书源验证功能

**实现要求**：
- 书源文件格式必须与 Android 版本完全兼容
- 支持批量导入导出
- 支持书源分享

#### 4. 网络内容获取

**功能描述**：根据规则抓取网页内容

**必须实现的功能**：
- GET/POST 请求
- Header 管理
- Cookie 管理
- 请求重试机制
- 并发控制

**实现要求**：
- 使用 URLSession + Alamofire
- 支持 OkHttp 的核心功能
- 请求超时设置
- 错误处理

#### 5. 内容净化功能

**功能描述**：支持替换净化，去除广告

**必须实现的功能**：
- 替换净化规则
- 正则替换
- CSS 选择器移除
- 自定义净化规则

**实现要求**：
- 支持 Android 版本的所有净化规则
- 净化规则必须与 Android 版本一致

#### 6. 本地文件阅读

**功能描述**：支持 TXT、EPUB 等本地文件

**必须实现的功能**：
- 导入本地 TXT 文件
- 导入本地 EPUB 文件
- 本地文件书架管理
- 本地文件阅读

**实现要求**：
- EPUB 使用 FolioReaderKit 或 EPUBKit
- TXT 直接读取
- 支持文件应用集成

#### 7. TTS 听书功能

**功能描述**：使用 iOS 原生 AVSpeechSynthesizer 实现文本转语音

**必须实现的功能**：
- 文本转语音播放
- 语速调节
- 音调调节
- 后台播放
- 播放控制（播放、暂停、停止）
- 断点续播

**实现要求**：
- 使用 AVSpeechSynthesizer（iOS 原生）
- 支持后台播放
- 支持锁屏控制
- 支持音频会话管理

---

## 🛠 技术架构（必须遵循）

### 架构原则

**原则 1**：纯 iOS 原生开发
- 不得使用跨平台框架（如 React Native、Flutter、KMP）
- 不得使用混合开发方案
- 必须使用 Swift 语言
- 必须使用 SwiftUI 框架

**原则 2**：MVVM 架构模式
- View 层：SwiftUI 视图
- ViewModel 层：业务逻辑
- Model 层：数据模型

**原则 3**：模块化设计
- 每个功能模块独立
- 清晰的依赖关系
- 便于测试和维护

### 技术栈（必须使用）

```
语言: Swift 5.9+
UI框架: SwiftUI (iOS 15+)
架构模式: MVVM + Combine
数据库: GRDB.swift
网络请求: URLSession + Alamofire
JavaScript引擎: JavaScriptCore (iOS 内置)
HTML解析: SwiftSoup
TTS引擎: AVSpeechSynthesizer (iOS原生)
```

**技术约束**：
- ✅ 必须使用上述技术栈
- ❌ 不得使用其他技术栈
- ❌ 不得使用未列出的第三方库
- ❌ 如需使用其他库，必须先询问

### 项目结构（必须遵循）

```
LegadoiOS/
├── App/
│   ├── Features/       # 功能模块
│   │   ├── BookSource/
│   │   │   ├── Models/
│   │   │   │   ├── BookSource.swift
│   │   │   │   ├── Book.swift
│   │   │   │   └── Chapter.swift
│   │   │   ├── Views/
│   │   │   │   ├── BookSourceListView.swift
│   │   │   │   ├── BookSourceEditView.swift
│   │   │   │   └── BookSourceImportView.swift
│   │   │   └── ViewModels/
│   │   │       └── BookSourceViewModel.swift
│   │   ├── Reading/
│   │   │   ├── Models/
│   │   │   ├── Views/
│   │   │   │   ├── ReadingView.swift
│   │   │   │   ├── ChapterListView.swift
│   │   │   │   └── BookshelfView.swift
│   │   │   └── ViewModels/
│   │   │       └── ReadingViewModel.swift
│   │   └── TTS/
│   │       ├── Models/
│   │       ├── Views/
│   │       └── ViewModels/
│   ├── Core/           # 核心服务
│   │   ├── Engine/     # 规则引擎
│   │   │   ├── RuleParser.swift
│   │   │   ├── RuleExecutor.swift
│   │   │   └── RuleType.swift
│   │   ├── Network/
│   │   │   ├── NetworkManager.swift
│   │   │   └── Alamofire+Extensions.swift
│   │   ├── Database/
│   │   │   ├── DatabaseManager.swift
│   │   │   └── Migrations/
│   │   ├── JSBridge/
│   │   │   ├── LegadoJSEngine.swift
│   │   │   └── JSJavaHelper.swift
│   │   ├── HTML/
│   │   │   └── HTMLParser.swift
│   │   └── Storage/
│   │       └── UserDefaults+Extensions.swift
│   ├── UI/             # SwiftUI 视图
│   │   ├── Components/
│   │   ├── Theme/
│   │   └── Styles/
│   └── Resources/      # 资源文件
└── Tests/              # 测试
    ├── Unit/
    ├── Integration/
    └── E2E/
```

**结构约束**：
- ✅ 必须遵循上述项目结构
- ❌ 不得随意修改目录结构
- ❌ 不得添加未说明的目录

---

## 🔧 核心技术实现（必须遵循）

### 1. JavaScript 引擎实现

**引擎选择**：JavaScriptCore（iOS 内置）

**必须实现的组件**：

#### LegadoJSEngine.swift
```swift
class LegadoJSEngine {
    private let context: JSContext

    init() {
        self.context = JSContext()
        setupContext()
    }

    private func setupContext() {
        // 配置 JavaScript 上下文
        // 绑定原生对象
        // 设置异常处理
    }

    func evaluateRule(_ rule: String, source: BookSource) -> String? {
        // 执行 JavaScript 规则
        // 返回执行结果
    }

    private func bindNativeObjects(_ source: BookSource) {
        // 绑定书源对象
        // 绑定 java 对象（Rhino API 兼容）
        // 绑定其他全局变量
    }
}
```

#### JSJavaHelper.swift（Rhino API 兼容层）
```swift
@objc protocol JSJavaHelperProtocol: JSExport {
    func ajax(_ url: String, method: String) -> String?
    func put(_ key: String, value: Any)
    func get(_ key: String) -> Any?
    // 其他 Rhino API 方法
}

class JSJavaHelper: NSObject, JSJavaHelperProtocol {
    // 实现 Rhino API 兼容方法
    // 网络请求
    // 存储操作
    // 其他工具方法
}
```

**实现要求**：
- 必须实现 Rhino API 兼容层
- 必须支持书源中使用的所有 Rhino API
- 必须处理 JavaScript 异常
- 必须提供降级方案

### 2. 规则解析系统

**必须实现的组件**：

#### RuleType.swift
```swift
enum RuleType {
    case defaultRule
    case xpath
    case json
    case regex
    case javascript
}
```

#### RuleParser.swift
```swift
class RuleParser {
    func parseRule(_ rule: String) -> (RuleType, String) {
        // 解析规则类型
        // 提取规则内容
        // 返回规则类型和内容
    }
}
```

#### RuleExecutor.swift
```swift
class RuleExecutor {
    private let jsEngine: LegadoJSEngine
    private let htmlParser: HTMLParser

    func executeRule(_ rule: String, source: BookSource, html: String?) -> String? {
        // 执行规则
        // 根据规则类型选择执行方式
        // 返回执行结果
    }
}
```

**实现要求**：
- 必须支持所有规则类型
- 必须与 Android 版本规则执行结果一致
- 必须处理规则执行异常

### 3. 网络请求层

**必须实现的组件**：

#### NetworkManager.swift
```swift
class NetworkManager {
    static let shared = NetworkManager()
    private let session: Session

    func request(_ config: RequestConfig) async throws -> Response {
        // 实现网络请求
        // 支持拦截器
        // 支持重试机制
        // 支持 Cookie 管理
    }
}
```

**实现要求**：
- 使用 URLSession + Alamofire
- 支持 OkHttp 的核心功能
- 支持请求拦截器
- 支持请求重试
- 支持 Cookie 管理

### 4. HTML 解析层

**必须实现的组件**：

#### HTMLParser.swift
```swift
class HTMLParser {
    func parse(_ html: String, xpath: String) -> [String] {
        // 使用 SwiftSoup 解析 HTML
        // 支持 XPath 查询
        // 返回解析结果
    }

    func parseJSON(_ json: String, jsonPath: String) -> [String] {
        // 解析 JSON
        // 支持 JSONPath 查询
        // 返回解析结果
    }
}
```

**实现要求**：
- 使用 SwiftSoup
- 支持 XPath 查询
- 支持 JSONPath 查询
- 支持正则表达式

### 5. 数据库层

**必须实现的组件**：

#### DatabaseManager.swift
```swift
class DatabaseManager {
    static let shared = DatabaseManager()
    private let db: Database

    init() {
        // 初始化数据库
        // 执行迁移
    }

    // CRUD 操作
    func saveBookSource(_ source: BookSource) throws
    func getBookSources() -> [BookSource]
    func deleteBookSource(_ id: String) throws
    // 其他数据库操作
}
```

**实现要求**：
- 使用 GRDB.swift
- 支持数据库迁移
- 支持事务操作
- 性能优化

### 6. TTS 引擎

**必须实现的组件**：

#### TTSManager.swift
```swift
class TTSManager: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()

    func speak(_ text: String, rate: Float = 0.5) {
        // 实现文本转语音
        // 设置语速、音调
        // 开始播放
    }

    func configureAudioSession() {
        // 配置音频会话
        // 支持后台播放
        // 支持锁屏控制
    }
}
```

**实现要求**：
- 使用 AVSpeechSynthesizer
- 支持后台播放
- 支持锁屏控制
- 支持音频会话管理

---

## 📊 数据模型（必须实现）

### BookSource.swift
```swift
struct BookSource: Codable, Identifiable {
    var id: String
    var name: String
    var url: String
    var searchUrl: String?
    var ruleSearchUrl: String?
    var ruleBookInfo: String?
    var ruleToc: String?
    var ruleContent: String?
    // 其他书源字段
}
```

### Book.swift
```swift
struct Book: Codable, Identifiable {
    var id: String
    var name: String
    var author: String
    var coverUrl: String?
    var intro: String?
    var sourceId: String
    var bookUrl: String
    // 其他书籍字段
}
```

### Chapter.swift
```swift
struct Chapter: Codable, Identifiable {
    var id: String
    var bookId: String
    var title: String
    var url: String
    var index: Int
    // 其他章节字段
}
```

**实现要求**：
- 数据模型必须与 Android 版本兼容
- 必须支持 Codable 协议
- 必须支持数据库存储

---

## 🎨 UI 设计（必须遵循）

### 设计原则

1. **遵循 iOS 设计规范**
   - 使用系统字体
   - 使用系统颜色
   - 遵循 iOS 交互模式

2. **支持深色模式**
   - 自动跟随系统设置
   - 使用系统颜色适配

3. **响应式设计**
   - 支持不同屏幕尺寸
   - 支持横屏模式

### 核心界面

#### 1. 书架界面（BookshelfView）
```swift
struct BookshelfView: View {
    @StateObject private var viewModel = BookshelfViewModel()

    var body: some View {
        // 书架列表
        // 支持网格和列表两种显示模式
        // 支持搜索和过滤
    }
}
```

#### 2. 阅读界面（ReadingView）
```swift
struct ReadingView: View {
    @StateObject private var viewModel = ReadingViewModel()

    var body: some View {
        // 章节内容展示
        // 支持翻页
        // 支持阅读设置
    }
}
```

#### 3. 书源管理界面（BookSourceListView）
```swift
struct BookSourceListView: View {
    @StateObject private var viewModel = BookSourceViewModel()

    var body: some View {
        // 书源列表
        // 支持导入导出
        // 支持编辑和删除
    }
}
```

**实现要求**：
- 使用 SwiftUI
- 遵循 iOS 设计规范
- 支持深色模式
- 支持横屏模式

---

## 🧪 测试要求（必须实现）

### 单元测试

**必须测试的组件**：
- JavaScript 引擎（LegadoJSEngine）
- 规则解析器（RuleParser）
- 规则执行器（RuleExecutor）
- HTML 解析器（HTMLParser）
- 网络请求（NetworkManager）

### 集成测试

**必须测试的功能**：
- 书源导入导出
- 书籍搜索
- 章节获取
- 内容阅读
- TTS 播放

### 兼容性测试

**必须测试的内容**：
- 导入现有书源（至少 Top 100）
- 测试常用网站
- 测试不同规则类型

**测试目标**：
- 书源兼容率 > 95%
- 搜索成功率 > 90%
- 页面加载时间 < 3 秒

---

## 📅 开发计划（必须遵循）

### 阶段 0：原型验证（1 周）

**目标**：降低技术风险，验证可行性

**任务**：
1. JavaScriptCore 兼容性测试（3-5 天）
   - 测试热门书源的 JavaScript 规则
   - 验证 Rhino API 兼容性
   - 确定需要适配的 API 列表

2. 风险评估（2-3 天）
   - 识别技术风险点
   - 制定缓解措施
   - 确定最终技术方案

**交付物**：
- 技术验证报告
- 兼容性测试结果

### 阶段一：核心引擎开发（5-6 周）

**目标**：实现书源规则执行能力

**任务**：
1. 数据模型设计（1 周）
2. JavaScript 引擎集成（2 周）
3. 规则解析系统（1-2 周）
4. 网络请求层（1 周）
5. HTML 解析层（3-5 天）

### 阶段二：MVP 功能实现（7-8 周）

**目标**：实现完整的阅读体验

**任务**：
1. 数据库实现（1 周）
2. 书源管理（2 周）
3. 搜索和发现（2 周）
4. 阅读界面（2-3 周）
5. 内容净化（1 周）
6. TTS 功能（1-2 周）

### 阶段三：测试和优化（3-4 周）

**目标**：确保稳定性和兼容性

**任务**：
1. 兼容性测试（2 周）
2. 性能优化（1 周）
3. 发布准备（3-5 天）

**总开发时间**：4-5 个月

---

## ⚠️ 关键约束（必须遵守）

### 技术约束

1. **必须使用的技术栈**
   - Swift 5.9+
   - SwiftUI (iOS 15+)
   - MVVM + Combine
   - GRDB.swift
   - URLSession + Alamofire
   - JavaScriptCore
   - SwiftSoup
   - AVSpeechSynthesizer

2. **禁止使用的技术**
   - ❌ 跨平台框架（React Native、Flutter、KMP）
   - ❌ 混合开发方案
   - ❌ 未列出的第三方库
   - ❌ 过时的 iOS API

### 功能约束

1. **必须实现的功能**
   - 书源规则执行引擎
   - 基础阅读功能
   - 书源导入导出
   - 网络内容获取
   - 内容净化功能
   - 本地文件阅读
   - TTS 听书功能

2. **禁止实现的功能**
   - ❌ 完整的 Web 服务功能
   - ❌ 复杂的第三方集成
   - ❌ 高级调试工具
   - ❌ 音频书籍播放功能
   - ❌ RSS 订阅功能
   - ❌ iCloud 同步功能
   - ❌ 快捷指令集成

### 质量约束

1. **性能要求**
   - 搜索响应时间 < 3 秒
   - 页面加载时间 < 2 秒
   - 应用启动时间 < 2 秒
   - 内存使用 < 100MB

2. **兼容性要求**
   - 书源兼容率 > 95%
   - 搜索成功率 > 90%
   - 支持 iOS 15.0+

3. **用户体验要求**
   - 用户迁移成本 = 0（直接导入书源）
   - 功能完整度 > 80%（vs Android 版本）
   - 用户满意度 > 4.0/5.0

---

## 🚨 风险控制（必须执行）

### JavaScript 引擎兼容性风险（最高优先级）

**风险描述**：JavaScriptCore 与 Rhino API 不完全兼容

**缓解措施**：
1. 第 1 周必须进行兼容性测试
2. 实现 Rhino API 兼容层
3. 提供降级方案处理不兼容的规则
4. 建立书源白名单/黑名单

**验证标准**：
- JavaScriptCore 兼容性 > 95%
- 至少测试 Top 100 热门书源

### App Store 审核风险

**风险描述**：书源功能可能被认定为"抓取内容"

**缓解措施**：
1. 在 App 描述中明确说明用户自行管理书源
2. 仅提供书源管理工具，不内置书源
3. 提供书源导入导出功能
4. 参考成功案例（Reeder、Feedly）

**审核准备**：
- 准备详细的审核说明文档
- 明确应用的使用场景

---

## 📝 实现检查清单（必须完成）

### 核心功能检查

- [ ] JavaScript 引擎集成（JavaScriptCore）
- [ ] Rhino API 兼容层实现
- [ ] 规则解析系统
- [ ] 规则执行系统
- [ ] 网络请求层
- [ ] HTML 解析层
- [ ] 数据库层
- [ ] 书源管理功能
- [ ] 书籍搜索功能
- [ ] 章节获取功能
- [ ] 内容阅读功能
- [ ] 书架管理功能
- [ ] 内容净化功能
- [ ] 本地文件阅读
- [ ] TTS 听书功能

### 技术要求检查

- [ ] 使用 Swift 5.9+
- [ ] 使用 SwiftUI (iOS 15+)
- [ ] 使用 MVVM + Combine
- [ ] 使用 GRDB.swift
- [ ] 使用 URLSession + Alamofire
- [ ] 使用 JavaScriptCore
- [ ] 使用 SwiftSoup
- [ ] 使用 AVSpeechSynthesizer

### 质量要求检查

- [ ] 单元测试覆盖 > 80%
- [ ] 集成测试完成
- [ ] 兼容性测试完成
- [ ] 性能测试通过
- [ ] 书源兼容率 > 95%
- [ ] 搜索成功率 > 90%
- [ ] 搜索响应时间 < 3 秒
- [ ] 页面加载时间 < 2 秒
- [ ] 应用启动时间 < 2 秒
- [ ] 内存使用 < 100MB

---

## 📞 问题解决流程

### 遇到不明确的问题时

1. **第一步**：查阅本文档
   - 检查是否有明确的说明
   - 检查是否有相关的约束

2. **第二步**：参考 Android 版本
   - 查看 Android 版本的实现
   - 理解 Android 版本的设计思路
   - 确保与 Android 版本一致

3. **第三步**：询问
   - 如果文档中没有明确说明
   - 如果不确定如何实现
   - 必须询问，而不是自行决定

### 遇到技术问题时

1. **第一步**：检查技术栈约束
   - 确认是否使用了允许的技术
   - 确认是否违反了技术约束

2. **第二步**：查阅官方文档
   - 查阅 Apple 官方文档
   - 查阅第三方库文档
   - 查阅社区资源

3. **第三步**：询问
   - 如果无法解决问题
   - 如果需要使用未列出的技术
   - 必须询问，而不是自行决定

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

## 📌 重要提醒

**给 AI 的提醒**：

1. **严格按照本文档实现**
   - 不得偏离设计目标
   - 不得添加未明确指定的功能
   - 不得假设或幻想未说明的功能

2. **遇到不明确的地方必须询问**
   - 不要自行决定
   - 不要假设
   - 不要幻想

3. **优先保证核心功能的稳定性**
   - 不要追求完美
   - 不要过度设计
   - 不要添加不必要的功能

4. **保持与 Android 版本的一致性**
   - 参考Android 版本的实现
   - 理解 Android 版本的设计思路
   - 确保用户体验一致

5. **关注性能和兼容性**
   - 优化性能
   - 确保兼容性
   - 提供良好的用户体验

---

**文档结束**

如有任何疑问，请务必询问，而不是自行决定。