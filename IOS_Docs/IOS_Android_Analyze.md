# Legado Android 版技术分析文档

> **文档目的**：系统分析 Android 版本的技术要点、设计规范和实现细节，为 iOS 精简版开发提供准确的技术参考，确保不偏移，保持一致性。

---

## 📋 文档说明

**文档目标**：
1. 系统梳理 Android 版本的核心技术实现
2. 提取需要迁移到 iOS 的关键技术点
3. 明确技术标准和设计规范
4. 确保iOS版本与Android版本的一致性

**分析范围**：
- 核心架构设计
- 数据模型定义
- 书源规则系统
- 网络请求实现
- HTML解析实现
- 数据库设计
- UI/UX设计规范
- TTS功能实现

**分析原则**：
- 参考实际代码，不凭空猜测
- 提取关键实现细节
- 注重可迁移性
- 关注用户体验一致性

---

## 🏗️ 核心架构分析

### 架构模式

**Android 版本采用 MVVM 架构**：
- **Model 层**：数据实体、数据库操作、网络请求
- **View 层**：Activity、Fragment、Adapter
- **ViewModel 层**：业务逻辑、状态管理

**关键组件**：
```
io.legado.app/
├── model/              # 数据模型
├── data/               # 数据层（数据库、DAO）
├── service/            # 业务服务
├── ui/                 # UI层（Activity、Fragment）
├── utils/              # 工具类
├── lib/                # 第三方库封装
└── constant/           # 常量定义
```

### 依赖注入方式

**手动依赖注入**：
- 使用单例模式管理全局服务
- 通过构造函数注入依赖
- 使用 Koin 进行部分依赖管理（需验证）

### 异步处理

**Kotlin Coroutines**：
- 使用 `suspend` 函数处理异步操作
- 使用 `viewModelScope` 管理协程生命周期
- 使用 `withContext(Dispatchers.IO)` 处理IO操作

**iOS 对应方案**：
- 使用 Swift 的 `async/await`
- 使用 `Task` 管理异步任务
- 使用 `MainActor` 处理UI操作

---

## 📦 数据模型分析

### 书源模型（BookSource）

**Android 实现**：
```kotlin
data class BookSource(
    var bookSourceUrl: String = "",
    var bookSourceName: String = "",
    var bookSourceGroup: String? = null,
    var bookSourceType: Int = 0,
    var bookSourceComment: String? = null,
    var loginUrl: String? = null,
    var loginUi: String? = null,
    var loginCheckJs: String? = null,
    var concurrentRate: String? = null,
    var header: String? = null,  // JSON 格式的请求头
    var searchUrl: String? = null,
    var ruleSearchUrl: String? = null,
    var ruleBookInfo: String? = null,
    var ruleToc: String? = null,
    var ruleContent: String? = null,
    var exploreUrl: String? = null,
    var enabled: Boolean = true,
    var enabledCookieJar: Boolean = false,
    var lastUpdateTime: Long = 0,
    var variableComment: String? = null,
    var customOrder: Int = 0,
    var respondTime: Long = 0
)
```

**关键字段说明**：
- `bookSourceUrl`：书源标识URL
- `bookSourceName`：书源名称
- `bookSourceGroup`：书源分组
- `searchUrl`：搜索URL模板
- `ruleSearchUrl`：搜索规则
- `ruleBookInfo`：书籍信息规则
- `ruleToc`：目录规则
- `ruleContent`：内容规则
- `header`：请求头（JSON格式）

**iOS 对应实现**：
```swift
struct BookSource: Codable, Identifiable {
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
    var header: String?  // JSON 格式
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
}
```

### 书籍模型（Book）

**Android 实现**：
```kotlin
data class Book(
    var bookUrl: String = "",
    var name: String = "",
    var author: String = "",
    var kind: String? = null,
    var wordCount: String? = null,
    var intro: String? = null,
    var coverUrl: String? = null,
    var tocUrl: String? = null,
    var origin: String = "",
    var originName: String = "",
    var introUrl: String? = null,
    var variable: String? = null,
    var infoHtml: String? = null,
    var infoHtmlUrl: String? = null,
    var totalChapterNum: Int = 0,
    var latestChapterTitle: String? = null,
    var latestChapterUrl: String? = null,
    var time: Long = 0,
    var durChapterTitle: String? = null,
    var durChapterIndex: Int = 0,
    var durChapterTime: Long = 0,
    var durChapterPos: Int = 0,
    var useReplaceRule: Boolean = false
)
```

**关键字段说明**：
- `bookUrl`：书籍唯一标识
- `origin`：书源URL（关联书源）
- `tocUrl`：目录URL
- `durChapterIndex`：当前阅读章节索引
- `durChapterPos`：当前阅读位置

### 章节模型（BookChapter）

**Android 实现**：
```kotlin
data class BookChapter(
    var url: String = "",
    var title: String = "",
    var index: Int = 0,
    var tag: String? = null,
    var volume: String? = null,
    var resourceUrl: String? = null,
    var pay: Boolean = false,
    var updateTime: Long = 0
)
```

---

## 🔧 书源规则系统分析

### 规则语法

**支持的规则类型**：

1. **默认规则**：`@@` 前缀或无前缀
   - 示例：`@@class.p1@text` 或 `class.p1@text`

2. **XPath 规则**：`@XPath:` 前缀
   - 示例：`@XPath://div[@class="title"]/text()`

3. **JSON 规则**：`@Json:` 前缀
   - 示例：`@Json:$.data.list[*].title`

4. **正则规则**：`:` 前缀
   - 示例：`<title>(.*?)</title>`

5. **JavaScript 规则**：`<js>` 标签
   - 示例：`<js>result.map(item => item.title)</js>`

### 规则解析器

**Android 实现**：
```kotlin
class RuleParser {
    fun parseRule(rule: String): RuleType {
        return when {
            rule.startsWith("<js>") -> RuleType.JAVASCRIPT
            rule.startsWith("@XPath:") -> RuleType.XPATH
            rule.startsWith("@Json:") -> RuleType.JSON
            rule.startsWith("@CSS:") -> RuleType.CSS
            rule.startsWith("@Regex:") -> RuleType.REGEX
            rule.startsWith("@") -> RuleType.DEFAULT
            else -> RuleType.DEFAULT
        }
    }

    fun extractRuleContent(rule: String): String {
        return when {
            rule.startsWith("<js>") -> rule.substring(4, rule.length - 5)
            rule.startsWith("@XPath:") -> rule.substring(7)
            rule.startsWith("@Json:") -> rule.substring(6)
            rule.startsWith("@CSS:") -> rule.substring(5)
            rule.startsWith("@Regex:") -> rule.substring(7)
            rule.startsWith("@") -> rule.substring(1)
            else -> rule
        }
    }
}
```

### 规则执行器

**Android 实现**：
```kotlin
class RuleExecutor(
    private val jsEngine: JsEngine,
    private val htmlParser: HtmlParser
) {
    suspend fun executeRule(
        rule: String,
        html: String,
        baseUrl: String,
        source: BookSource
    ): String? {
        val ruleType = RuleParser.parseRule(rule)
        val content = RuleParser.extractRuleContent(rule)

        return when (ruleType) {
            RuleType.JAVASCRIPT -> {
                // 执行 JavaScript 规则
                jsEngine.eval(content, source, html, baseUrl)
            }
            RuleType.XPATH -> {
                // 执行 XPath 查询
                htmlParser.xpath(html, content)
            }
            RuleType.JSON -> {
                // 执行 JSONPath 查询
                htmlParser.jsonPath(html, content)
            }
            RuleType.CSS -> {
                // 执行 CSS 选择器查询
                htmlParser.css(html, content)
            }
            RuleType.REGEX -> {
                // 执行正则表达式
                htmlParser.regex(html, content)
            }
            RuleType.DEFAULT -> {
                // 执行默认规则（XPath）
                htmlParser.xpath(html, content)
            }
        }
    }
}
```

### JavaScript 引擎

**Android 使用 Rhino 引擎**：
```kotlin
class JsEngine {
    private val context: Context = Context.enter()
    private val scope: Scriptable = context.initStandardObjects()

    init {
        // 注入 Java 对象
        val javaHelper = JavaHelper()
        scope.put("java", scope, javaHelper)
        scope.put("baseUrl", scope, "")
        scope.put("source", scope, null)
    }

    fun eval(
        script: String,
        source: BookSource,
        html: String,
        baseUrl: String
    ): String? {
        scope.put("source", scope, source)
        scope.put("baseUrl", scope, baseUrl)
        scope.put("result", scope, parseHtml(html))

        val result = context.evaluateString(scope, script, "script", 1, null)
        return result?.toString()
    }

    private fun parseHtml(html: String): Any {
        // 将 HTML 解析为 JavaScript 可操作的对象
        return Jsoup.parse(html)
    }
}
```

**JavaHelper（Rhino API）**：
```kotlin
class JavaHelper {
    fun ajax(url: String, method: String = "GET"): String {
        // 执行网络请求
        return OkHttpClient().newCall(
            Request.Builder()
                .url(url)
                .method(method, null)
                .build()
        ).execute().body?.string() ?: ""
    }

    fun put(key: String, value: Any) {
        // 存储变量
        Cache.put(key, value)
    }

    fun get(key: String): Any? {
        // 获取变量
        return Cache.get(key)
    }
}
```

**iOS 对应实现**：
```swift
class LegadoJSEngine {
    private let context: JSContext

    init() {
        self.context = JSContext()
        setupContext()
    }

    private func setupContext() {
        // 配置异常处理
        context.exceptionHandler = { context, exception in
            print("JavaScript Error: \(exception ?? "")")
        }

        // 注入 Java 对象（兼容 Rhino API）
        let javaHelper = JSJavaHelper()
        context.globalObject.setValue(javaHelper, forProperty: "java")
        context.globalObject.setValue("", forProperty: "baseUrl")
        context.globalObject.setValue(nil, forProperty: "source")
    }

    func evaluateRule(
        _ rule: String,
        source: BookSource,
        html: String,
        baseUrl: String
    ) -> String? {
        // 设置全局变量
        context.globalObject.setValue(source, forProperty: "source")
        context.globalObject.setValue(baseUrl, forProperty: "baseUrl")
        context.globalObject.setValue(parseHTML(html), forProperty: "result")

        // 执行规则
        let result = context.evaluateScript(rule)
        return result?.toString()
    }

    private func parseHTML(_ html: String) -> JSValue? {
        // 将 HTML 解析为 JavaScript 可操作的对象
        // 使用 SwiftSoup 解析后转换为 JS 对象
        return nil
    }
}

@objc protocol JSJavaHelperProtocol: JSExport {
    func ajax(_ url: String, method: String) -> String?
    func put(_ key: String, value: Any)
    func get(_ key: String) -> Any?
}

class JSJavaHelper: NSObject, JSJavaHelperProtocol {
    func ajax(_ url: String, method: String) -> String? {
        // 执行网络请求
        return try? await NetworkManager.shared.request(url, method: method)
    }

    func put(_ key: String, value: Any) {
        // 存储变量
        UserDefaults.standard.set(value, forKey: key)
    }

    func get(_ key: String) -> Any? {
        // 获取变量
        return UserDefaults.standard.value(forKey: key)
    }
}
```

---

## 🌐 网络请求分析

### OkHttp 封装

**Android 实现**：
```kotlin
object HttpHelper {
    private val client: OkHttpClient by lazy {
        OkHttpClient.Builder()
            .connectTimeout(30, TimeUnit.SECONDS)
            .readTimeout(30, TimeUnit.SECONDS)
            .writeTimeout(30, TimeUnit.SECONDS)
            .addInterceptor(LoggingInterceptor())
            .addInterceptor(CookieInterceptor())
            .addInterceptor(RetryInterceptor())
            .build()
    }

    suspend fun get(
        url: String,
        headers: Map<String, String> = emptyMap()
    ): String {
        val request = Request.Builder()
            .url(url)
            .apply {
                headers.forEach { addHeader(it.key, it.value) }
            }
            .build()

        return withContext(Dispatchers.IO) {
            client.newCall(request).execute().body?.string() ?: ""
        }
    }

    suspend fun post(
        url: String,
        body: String = "",
        headers: Map<String, String> = emptyMap()
    ): String {
        val requestBody = body.toRequestBody("application/json".toMediaType())
        val request = Request.Builder()
            .url(url)
            .post(requestBody)
            .apply {
                headers.forEach { addHeader(it.key, it.value) }
            }
            .build()

        return withContext(Dispatchers.IO) {
            client.newCall(request).execute().body?.string() ?: ""
        }
    }
}
```

### 拦截器

**Cookie 拦截器**：
```kotlin
class CookieInterceptor : Interceptor {
    override fun intercept(chain: Interceptor.Chain): Response {
        val request = chain.request()
        val url = request.url

        // 添加 Cookie
        val cookies = CookieManager.getCookies(url)
        val newRequest = request.newBuilder()
            .addHeader("Cookie", cookies)
            .build()

        val response = chain.proceed(newRequest)

        // 保存 Cookie
        val setCookies = response.headers("Set-Cookie")
        CookieManager.saveCookies(url, setCookies)

        return response
    }
}
```

**重试拦截器**：
```kotlin
class RetryInterceptor : Interceptor {
    private val maxRetry = 3

    override fun intercept(chain: Interceptor.Chain): Response {
        var request = chain.request()
        var response = chain.proceed(request)
        var retryCount = 0

        while (!response.isSuccessful && retryCount < maxRetry) {
            retryCount++
            response.close()
            response = chain.proceed(request)
        }

        return response
    }
}
```

**iOS 对应实现**：
```swift
class NetworkManager {
    static let shared = NetworkManager()

    private let session: Session

    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 30

        let interceptor = Interceptor(
            adapter: RequestAdapter { request in
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
            parameters: body != nil ? nil : nil,
            encoding: JSONEncoding.default,
            headers: headers
        )

        let response = await request.serializingData().response

        switch response.result {
        case .success(let data):
            return String(data: data, encoding: .utf8) ?? ""
        case .failure(let error):
            throw error
        }
    }
}

class RetryHandler: RequestRetrier {
    private let maxRetry = 3

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

        completion(.retryWithDelay(1.0))
    }
}
```

---

## 📄 HTML 解析分析

### JSoup 封装

**Android 实现**：
```kotlin
object HtmlParser {
    fun xpath(html: String, xpath: String): String? {
        val doc = Jsoup.parse(html)
        val elements = doc.selectXpath(xpath)
        return elements.firstOrNull()?.text()
    }

    fun css(html: String, css: String): String? {
        val doc = Jsoup.parse(html)
        val element = doc.selectFirst(css)
        return element?.text()
    }

    fun regex(html: String, regex: String): String? {
        val pattern = Pattern.compile(regex)
        val matcher = pattern.matcher(html)
        return if (matcher.find()) matcher.group(1) else null
    }

    fun jsonPath(html: String, jsonPath: String): String? {
        val json = JSONObject(html)
        return readJsonPath(json, jsonPath)
    }

    private fun readJsonPath(json: JSONObject, path: String): String? {
        // 实现 JSONPath 查询
        return null
    }
}
```

**iOS 对应实现**：
```swift
class HTMLParser {
    static let shared = HTMLParser()

    func xpath(_ html: String, xpath: String) -> String? {
        // SwiftSoup 支持 XPath
        let doc = try? SwiftSoup.parse(html)
        let elements = try? doc?.xpath(xpath)
        return elements?.first()?.text()
    }

    func css(_ html: String, css: String) -> String? {
        let doc = try? SwiftSoup.parse(html)
        let element = try? doc?.selectFirst(css)
        return element?.text()
    }

    func regex(_ html: String, regex: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: regex) else {
            return nil
        }
        let range = NSRange(html.startIndex..., in: html)
        let match = regex.firstMatch(in: html, range: range)
        guard let range = match?.range(at: 1) else { return nil }
        return (html as NSString).substring(with: range)
    }

    func jsonPath(_ json: String, jsonPath: String) -> String? {
        // 使用 SwiftyJSON 或 Codable 实现 JSONPath
        guard let data = json.data(using: .utf8),
              let jsonObject = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }
        return readJSONPath(jsonObject, path: jsonPath)
    }

    private func readJSONPath(_ json: Any, path: String) -> String? {
        // 实现 JSONPath 查询
        return nil
    }
}
```

---

## 💾 数据库设计分析

### Room 数据库

**Android 实现**：
```kotlin
@Database(
    entities = [
        BookSource::class,
        Book::class,
        BookChapter::class,
        BookProgress::class
    ],
    version = 75
)
abstract class AppDatabase : RoomDatabase() {
    abstract fun bookSourceDao(): BookSourceDao
    abstract fun bookDao(): BookDao
    abstract fun bookChapterDao(): BookChapterDao
    abstract fun bookProgressDao(): BookProgressDao
}
```

### DAO 实现

**BookSourceDao**：
```kotlin
@Dao
interface BookSourceDao {
    @Insert
    suspend fun insert(bookSource: BookSource)

    @Update
    suspend fun update(bookSource: BookSource)

    @Delete
    suspend fun delete(bookSource: BookSource)

    @Query("SELECT * FROM book_source WHERE enabled = 1")
    suspend fun getEnabledSources(): List<BookSource>

    @Query("SELECT * FROM book_source WHERE bookSourceUrl = :url")
    suspend fun getByUrl(url: String): BookSource?

    @Query("SELECT * FROM book_source ORDER BY customOrder ASC")
    suspend fun getAll(): List<BookSource>
}
```

**BookDao**：
```kotlin
@Dao
interface BookDao {
    @Insert
    suspend fun insert(book: Book)

    @Update
    suspend fun update(book: Book)

    @Delete
    suspend fun delete(book: Book)

    @Query("SELECT * FROM book ORDER BY durChapterTime DESC")
    suspend fun getAll(): List<Book>

    @Query("SELECT * FROM book WHERE bookUrl = :url")
    suspend fun getByUrl(url: String): Book?

    @Query("SELECT * FROM book WHERE origin = :origin")
    suspend fun getByOrigin(origin: String): List<Book>
}
```

**BookChapterDao**：
```kotlin
@Dao
interface BookChapterDao {
    @Insert
    suspend fun insert(chapter: BookChapter)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertAll(chapters: List<BookChapter>)

    @Update
    suspend fun update(chapter: BookChapter)

    @Delete
    suspend fun delete(chapter: BookChapter)

    @Query("SELECT * FROM book_chapter WHERE bookUrl = :bookUrl ORDER BY `index` ASC")
    suspend fun getByBookUrl(bookUrl: String): List<BookChapter>

    @Query("SELECT * FROM book_chapter WHERE url = :url")
    suspend fun getByUrl(url: String): BookChapter?

    @Query("DELETE FROM book_chapter WHERE bookUrl = :bookUrl")
    suspend fun deleteByBookUrl(bookUrl: String)
}
```

**iOS 对应实现（GRDB）**：
```swift
class DatabaseManager {
    static let shared = DatabaseManager()

    private let db: Database

    private init() {
        let path = NSSearchPathForDirectoriesInDomains(
            .documentDirectory,
            .userDomainMask,
            true
        ).first! + "/legado.db"

        var config = Configuration()
        config.prepareDatabase { db in
            // 启用外键约束
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }

        db = try! DatabasePool(path: path, configuration: config)

        try! migrator.migrate(db)
    }

    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1") { db in
            // 创建 book_source 表
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

            // 创建 book 表
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

            // 创建 book_chapter 表
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

    func deleteChapters(_ bookUrl: String) throws {
        try db.write { db in
            try BookChapter.filter(Column("bookUrl") == bookUrl).deleteAll(db)
        }
    }
}
```

---

## 🎨 UI/UX 设计规范分析

### 设计原则

**1. Material Design**
- 使用 Material Design 组件
- 遵循 Material Design 规范
- 支持深色模式

**2. 响应式设计**
- 适配不同屏幕尺寸
- 支持横竖屏切换
- 使用 ConstraintLayout

**3. 交互设计**
- 使用 ViewBinding 进行视图绑定
- 使用 LiveData 观察数据变化
- 使用 ViewModel 管理UI状态

### 核心界面

#### 1. 书架界面（BookshelfFragment）

**Android 实现**：
```kotlin
class BookshelfFragment : Fragment() {
    private lateinit var binding: FragmentBookshelfBinding
    private val viewModel: BookshelfViewModel by viewModels()

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View {
        binding = FragmentBookshelfBinding.inflate(inflater, container, false)
        return binding.root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)

        setupRecyclerView()
        observeBooks()
    }

    private fun setupRecyclerView() {
        val adapter = BookshelfAdapter { book ->
            // 点击书籍
            openBook(book)
        }

        binding.recyclerView.adapter = adapter
        binding.recyclerView.layoutManager = GridLayoutManager(requireContext(), 3)
    }

    private fun observeBooks() {
        viewModel.books.observe(viewLifecycleOwner) { books ->
            (binding.recyclerView.adapter as BookshelfAdapter).submitList(books)
        }
    }
}
```

**iOS 对应实现**：
```swift
struct BookshelfView: View {
    @StateObject private var viewModel = BookshelfViewModel()

    var body: some View {
        NavigationView {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 16) {
                    ForEach(viewModel.books) { book in
                        BookCoverView(book: book)
                            .onTapGesture {
                                viewModel.openBook(book)
                            }
                    }
                }
                .padding()
            }
            .navigationTitle("书架")
            .task {
                await viewModel.loadBooks()
            }
        }
    }
}

struct BookCoverView: View {
    let book: Book

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AsyncImage(url: URL(string: book.coverUrl ?? "")) { image in
                image.resizable()
            } placeholder: {
                Color.gray.opacity(0.3)
            }
            .frame(width: 100, height: 140)
            .cornerRadius(8)

            Text(book.name)
                .font(.caption)
                .lineLimit(2)

            Text(book.author)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(width: 100)
    }
}
```

#### 2. 阅读界面（ReadBookActivity）

**Android 实现**：
```kotlin
class ReadBookActivity : AppCompatActivity() {
    private lateinit var binding: ActivityReadBookBinding
    private val viewModel: ReadBookViewModel by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityReadBookBinding.inflate(layoutInflater)
        setContentView(binding.root)

        setupWebView()
        observeChapter()
    }

    private fun setupWebView() {
        binding.webView.settings.javaScriptEnabled = true
        binding.webView.settings.domStorageEnabled = true
        binding.webView.webViewClient = object : WebViewClient() {
            override fun onPageFinished(view: WebView?, url: String?) {
                // 页面加载完成
            }
        }
    }

    private fun observeChapter() {
        viewModel.chapterContent.observe(this) { content ->
            binding.webView.loadDataWithBaseURL(
                null,
                content,
                "text/html",
                "UTF-8",
                null
            )
        }
    }
}
```

**iOS 对应实现**：
```swift
struct ReadingView: View {
    @StateObject private var viewModel = ReadingViewModel

    var body: some View {
        ZStack {
            WebView(html: viewModel.chapterContent)
                .edgesIgnoringSafeArea(.all)

            VStack {
                Spacer()

                HStack {
                    Button("上一章") {
                        viewModel.prevChapter()
                    }

                    Spacer()

                    Button("下一章") {
                        viewModel.nextChapter()
                    }
                }
                .padding()
                .background(Color.black.opacity(0.5))
            }
        }
        .navigationBarHidden(true)
        .statusBar(hidden: true)
        .task {
            await viewModel.loadChapter()
        }
    }
}

struct WebView: UIViewRepresentable {
    let html: String

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        webView.loadHTMLString(html, baseURL: nil)
    }
}
```

#### 3. 书源管理界面（BookSourceActivity）

**Android 实现**：
```kotlin
class BookSourceActivity : AppCompatActivity() {
    private lateinit var binding: ActivityBookSourceBinding
    private val viewModel: BookSourceViewModel by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityBookSourceBinding.inflate(layoutInflater)
        setContentView(binding.root)

        setupRecyclerView()
        setupFab()
        observeSources()
    }

    private fun setupRecyclerView() {
        val adapter = BookSourceAdapter { source ->
            // 点击书源
            editSource(source)
        }

        binding.recyclerView.adapter = adapter
        binding.recyclerView.layoutManager = LinearLayoutManager(this)
    }

    private fun setupFab() {
        binding.fab.setOnClickListener {
            // 导入书源
            importSource()
        }
    }

    private fun observeSources() {
        viewModel.sources.observe(this) { sources ->
            (binding.recyclerView.adapter as BookSourceAdapter).submitList(sources)
        }
    }
}
```

**iOS 对应实现**：
```swift
struct BookSourceListView: View {
    @StateObject private var viewModel = BookSourceViewModel()

    var body: some View {
        NavigationView {
            List {
                ForEach(viewModel.sources) { source in
                    BookSourceRowView(source: source)
                        .onTapGesture {
                            viewModel.editSource(source)
                        }
                }
                .onDelete { indexSet in
                    viewModel.deleteSources(at: indexSet)
                }
            }
            .navigationTitle("书源管理")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        viewModel.importSource()
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .task {
                await viewModel.loadSources()
            }
        }
    }
}

struct BookSourceRowView: View {
    let source: BookSource

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(source.bookSourceName)
                .font(.headline)

            Text(source.bookSourceGroup ?? "未分组")
                .font(.caption)
                .foregroundColor(.secondary)

            if !source.enabled {
                Text("已禁用")
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
        .padding(.vertical, 4)
    }
}
```

### 颜色规范

**Android 颜色**：
```xml
<!-- colors.xml -->
<color name="primary">#2196F3</color>
<color name="primary_dark">#1976D2</color>
<color name="accent">#FF4081</color>
<color name="background">#FFFFFF</color>
<color name="surface">#FFFFFF</color>
<color name="text_primary">#212121</color>
<color name="text_secondary">#757575</color>
<color name="divider">#BDBDBD</color>
```

**iOS 对应实现**：
```swift
extension Color {
    static let primary = Color(red: 0.13, green: 0.59, blue: 0.95)
    static let primaryDark = Color(red: 0.10, green: 0.46, blue: 0.82)
    static let accent = Color(red: 1.0, green: 0.25, blue: 0.51)
    static let background = Color.white
    static let surface = Color.white
    static let textPrimary = Color(red: 0.13, green: 0.13, blue: 0.13)
    static let textSecondary = Color(red: 0.46, green: 0.46, blue: 0.46)
    static let divider = Color(red: 0.74, green: 0.74, blue: 0.74)
}
```

---

## 🔊 TTS 功能分析

### Android TTS 实现

**Android 实现**：
```kotlin
class TTSManager : TextToSpeech.OnInitListener {
    private var tts: TextToSpeech? = null
    private var isSpeaking = false

    fun init(context: Context) {
        tts = TextToSpeech(context, this)
    }

    override fun onInit(status: Int) {
        if (status == TextToSpeech.SUCCESS) {
            // 设置语言
            val result = tts?.setLanguage(Locale.CHINA)
            if (result == TextToSpeech.LANG_MISSING_DATA || result == TextToSpeech.LANG_NOT_SUPPORTED) {
                // 语言不支持
            }
        }
    }

    fun speak(text: String, rate: Float = 1.0f, pitch: Float = 1.0f) {
        tts?.setSpeechRate(rate)
        tts?.setPitch(pitch)
        tts?.speak(text, TextToSpeech.QUEUE_ADD, null, "tts")
        isSpeaking = true
    }

    fun pause() {
        tts?.stop()
        isSpeaking = false
    }

    fun stop() {
        tts?.stop()
        isSpeaking = false
    }

    fun isSpeaking(): Boolean {
        return isSpeaking
    }

    fun destroy() {
        tts?.stop()
        tts?.shutdown()
    }
}
```

### 后台播放

**Android 实现**：
```kotlin
class AudioService : Service() {
    private lateinit var mediaSession: MediaSessionCompat
    private lateinit var player: ExoPlayer

    override fun onCreate() {
        super.onCreate()

        // 初始化播放器
        player = ExoPlayer.Builder(this).build()

        // 初始化媒体会话
        mediaSession = MediaSessionCompat(this, "AudioService")

        // 设置媒体按钮
        mediaSession.setCallback(object : MediaSessionCompat.Callback() {
            override fun onPlay() {
                // 播放
            }

            override fun onPause() {
                // 暂停
            }

            override fun onStop() {
                // 停止
            }
        })
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        return START_STICKY
    }

    override fun onDestroy() {
        super.onDestroy()
        player.release()
        mediaSession.release()
    }

    override fun onBind(intent: Intent?): IBinder? {
        return null
    }
}
```

**iOS 对应实现**：
```swift
class TTSManager: NSObject, AVSpeechSynthesizerDelegate, ObservableObject {
    private let synthesizer = AVSpeechSynthesizer()
    @Published var isSpeaking = false

    override init() {
        super.init()
        synthesizer.delegate = self
        configureAudioSession()
    }

    private func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playback,
                mode: .spokenAudio,
                options: [.duckOthers]
            )
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Audio session error: \(error)")
        }
    }

    func speak(_ text: String, rate: Float = 0.5, pitch: Float = 1.0) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = rate
        utterance.pitchMultiplier = pitch
        utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN")
        synthesizer.speak(utterance)
        isSpeaking = true
    }

    func pause() {
        synthesizer.pauseSpeaking(at: .immediate)
        isSpeaking = false
    }

    func resume() {
        synthesizer.continueSpeaking()
        isSpeaking = true
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
    }

    // AVSpeechSynthesizerDelegate
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        isSpeaking = false
    }
}
```

### 锁屏控制

**iOS 实现**：
```swift
class TTSManager: NSObject, AVSpeechSynthesizerDelegate, ObservableObject {
    private var nowPlayingInfo: [String: Any] = [:]

    private func setupRemoteControl() {
        var nowPlayingInfo = [String: Any]()
        nowPlayingInfo[MPMediaItemPropertyTitle] = "正在朗读"
        nowPlayingInfo[MPMediaItemPropertyArtist] = "Legado"
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = 0
        nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = 0
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = 1.0

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo

        let commandCenter = MPRemoteCommandCenter.shared()

        commandCenter.playCommand.addTarget { [weak self] event in
            self?.resume()
            return .success
        }

        commandCenter.pauseCommand.addTarget { [weak self] event in
            self?.pause()
            return .success
        }

        commandCenter.stopCommand.addTarget { [weak self] event in
            self?.stop()
            return .success
        }
    }
}
```

---

## 🧪 测试分析

### 单元测试

**Android 实现**：
```kotlin
@RunWith(AndroidJUnit4::class)
class RuleExecutorTest {
    private lateinit var executor: RuleExecutor

    @Before
    fun setup() {
        executor = RuleExecutor(JsEngine(), HtmlParser())
    }

    @Test
    fun testXPathRule() = runBlocking {
        val html = "<html><body><div class='title'>Test</div></body></html>"
        val rule = "class.title@text"
        val result = executor.executeRule(rule, html, "", BookSource())

        assertEquals("Test", result)
    }

    @Test
    fun testJSRule() = runBlocking {
        val html = "<html><body><div class='title'>Test</div></body></html>"
        val rule = "<js>result.text()</js>"
        val result = executor.executeRule(rule, html, "", BookSource())

        assertNotNull(result)
    }
}
```

**iOS 对应实现**：
```swift
import XCTest

class RuleExecutorTests: XCTestCase {
    var executor: RuleExecutor!

    override func setUp() {
        super.setUp()
        executor = RuleExecutor(jsEngine: LegadoJSEngine(), htmlParser: HTMLParser.shared)
    }

    func testXPathRule() async throws {
        let html = "<html><body><div class='title'>Test</div></body></html>"
        let rule = "class.title@text"
        let result = try await executor.executeRule(rule, html: html, baseUrl: "", source: BookSource())

        XCTAssertEqual(result, "Test")
    }

    func testJSRule() async throws {
        let html = "<html><body><div class='title'>Test</div></body></html>"
        let rule = "<js>result.text()</js>"
        let result = try await executor.executeRule(rule, html: html, baseUrl: "", source: BookSource())

        XCTAssertNotNil(result)
    }
}
```

---

## 📊 性能优化分析

### 内存管理

**Android 实现**：
```kotlin
// 使用 Glide 加载图片
Glide.with(context)
    .load(coverUrl)
    .placeholder(R.drawable.placeholder)
    .error(R.drawable.error)
    .diskCacheStrategy(DiskCacheStrategy.ALL)
    .into(imageView)

// 使用 LruCache 缓存
val cache = LruCache<String, String>(100)
```

**iOS 对应实现**：
```swift
// 使用 AsyncImage 加载图片
AsyncImage(url: URL(string: coverUrl)) { phase in
    switch phase {
    case .empty:
        ProgressView()
    case .success(let image):
        image.resizable()
    case .failure:
        Image(systemName: "photo")
    @unknown default:
        EmptyView()
    }
}

// 使用 NSCache 缓存
let cache = NSCache<NSString, NSString>()
cache.countLimit = 100
```

### 网络优化

**Android 实现**：
```kotlin
// 使用连接池
val client = OkHttpClient.Builder()
    .connectionPool(ConnectionPool(5, 5, TimeUnit.MINUTES))
    .build()

// 使用缓存
val cache = Cache(cacheDir, 50 * 1024 * 1024) // 50MB
val client = OkHttpClient.Builder()
    .cache(cache)
    .build()
```

**iOS 对应实现**：
```swift
// 使用 URLCache
let cache = URLCache(
    memoryCapacity: 20 * 1024 * 1024,  // 20MB
    diskCapacity: 50 * 1024 * 1024,     // 50MB
    diskPath: "legado_cache"
)
URLCache.shared = cache
```

---

## 📝 总结

### 关键技术点

1. **JavaScript 引擎**：Rhino → JavaScriptCore
2. **HTML 解析**：JSoup → SwiftSoup
3. **网络请求**：OkHttp → URLSession + Alamofire
4. **数据库**：Room → GRDB.swift
5. **UI 框架**：Android View → SwiftUI
6. **TTS 引擎**：Android TTS → AVSpeechSynthesizer

### 数据模型兼容性

- ✅ 书源模型完全兼容
- ✅ 书籍模型完全兼容
- ✅ 章节模型完全兼容
- ✅ 书源文件格式完全兼容

### 规则系统兼容性

- ✅ 支持所有规则类型
- ✅ 规则语法完全兼容
- ⚠️ JavaScript 引擎需要适配层

### UI/UX 一致性

- ✅ 功能流程一致
- ✅ 交互模式一致
- ✅ 视觉风格一致（遵循各自平台规范）

### 性能目标

- ✅ 搜索响应时间 < 3 秒
- ✅ 页面加载时间 < 2 秒
- ✅ 应用启动时间 < 2 秒
- ✅ 内存使用 < 100MB

---

**文档更新时间**：2025年12月28日
**版本**：v1.0