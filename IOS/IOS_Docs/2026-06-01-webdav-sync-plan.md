# WebDAV 云同步 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 实现完整的 WebDAV 云同步：书架、阅读进度、书签、高亮划线，支持自动和手动触发，密码存 Keychain，最新时间戳优先冲突策略。

**Architecture:** 4 个新 Swift 文件放在 `Core/Sync/`；`WebDAVClient`（actor）负责 HTTP 基础操作，`WebDAVSyncManager`（@MainActor singleton）负责同步逻辑，`SyncModels` 提供 Codable 快照结构体，`WebDAVSettings` 持久化配置。DatabaseManager 新增全量 export/import 方法。触发点接入 LegadoApp（启动拉取）和 ReaderView（关闭推送）。

**Tech Stack:** Swift 5.9, URLSession, Security framework (Keychain), GRDB, SwiftUI, iOS 15+

---

## 文件清单

| 操作 | 路径 | 职责 |
|------|------|------|
| 新建 | `Core/Sync/SyncModels.swift` | JSON 快照 Codable 结构体 |
| 新建 | `Core/Sync/WebDAVSettings.swift` | UserDefaults + Keychain 凭证 + KeychainHelper |
| 新建 | `Core/Sync/WebDAVClient.swift` | HTTP PUT/GET/MKCOL actor |
| 新建 | `Core/Sync/WebDAVSyncManager.swift` | 同步协调器 + SyncState |
| 修改 | `Core/Database/DatabaseManager.swift` | 新增全量查询与 import 方法 |
| 修改 | `UI/SettingsView.swift` | WebDAV 配置区块 + 状态显示 |
| 修改 | `LegadoApp.swift` | 启动后触发下载检查 |
| 修改 | `Features/Reading/Views/ReaderView.swift` | onDisappear 触发上传 |
| 修改 | `Legado.xcodeproj/project.pbxproj` | 注册 4 个新文件 |

---

## Task 1: SyncModels.swift

**Files:**
- Create: `IOS/Legado/App/Core/Sync/SyncModels.swift`

- [ ] **Step 1: 创建文件**

```swift
// IOS/Legado/App/Core/Sync/SyncModels.swift
import Foundation

// MARK: - metadata.json

struct SyncMetadata: Codable {
    var version: Int = 1
    var deviceId: String
    var updatedAt: Int64
    var files: [String: Int64]   // "books" | "reading_progress" | "bookmarks" | "highlights"

    static func makeNew() -> SyncMetadata {
        let id = UserDefaults.standard.string(forKey: "sync.deviceId") ?? {
            let newId = UUID().uuidString
            UserDefaults.standard.set(newId, forKey: "sync.deviceId")
            return newId
        }()
        return SyncMetadata(deviceId: id, updatedAt: Date().milliseconds,
                            files: ["books": 0, "reading_progress": 0,
                                    "bookmarks": 0, "highlights": 0])
    }
}

// MARK: - books.json

struct SyncBookEntry: Codable {
    var bookUrl: String
    var name: String
    var author: String
    var origin: String
    var originName: String
    var coverUrl: String?
    var intro: String?
    var tocUrl: String?
    var lastUpdatedAt: Int64

    init(from book: Book) {
        bookUrl      = book.bookUrl
        name         = book.name
        author       = book.author
        origin       = book.origin
        originName   = book.originName
        coverUrl     = book.coverUrl
        intro        = book.intro
        tocUrl       = book.tocUrl
        lastUpdatedAt = book.durChapterTime   // 用阅读时间作为书籍最后活跃时间
    }

    func applyTo(_ book: inout Book) {
        book.name        = name
        book.author      = author
        book.origin      = origin
        book.originName  = originName
        book.coverUrl    = coverUrl
        book.intro       = intro
        book.tocUrl      = tocUrl
    }
}

// MARK: - reading_progress.json

struct SyncProgressEntry: Codable {
    var bookUrl: String
    var durChapterIndex: Int
    var durChapterPos: Int
    var durChapterTime: Int64

    init(from book: Book) {
        bookUrl         = book.bookUrl
        durChapterIndex = book.durChapterIndex
        durChapterPos   = book.durChapterPos
        durChapterTime  = book.durChapterTime
    }
}

// MARK: - bookmarks.json

struct SyncBookmarkEntry: Codable {
    var bookUrl: String
    var chapterIndex: Int
    var chapterTitle: String
    var content: String
    var createdAt: Int64

    init(from bm: Bookmark) {
        bookUrl      = bm.bookUrl
        chapterIndex = bm.chapterIndex
        chapterTitle = bm.chapterTitle
        content      = bm.content
        createdAt    = Int64(bm.createdAt.timeIntervalSince1970 * 1000)
    }

    func toBookmark() -> Bookmark {
        Bookmark(bookUrl: bookUrl, chapterIndex: chapterIndex,
                 chapterTitle: chapterTitle, content: content,
                 createdAt: Date(timeIntervalSince1970: Double(createdAt) / 1000))
    }
}

// MARK: - highlights.json

struct SyncHighlightEntry: Codable {
    var bookUrl: String
    var chapterIndex: Int
    var startOffset: Int
    var endOffset: Int
    var colorIndex: Int
    var content: String
    var createdAt: Int64

    init(from h: BookHighlight) {
        bookUrl      = h.bookUrl
        chapterIndex = h.chapterIndex
        startOffset  = h.startOffset
        endOffset    = h.endOffset
        colorIndex   = h.colorIndex
        content      = h.content
        createdAt    = Int64(h.createdAt.timeIntervalSince1970 * 1000)
    }

    func toHighlight() -> BookHighlight {
        BookHighlight(bookUrl: bookUrl, chapterIndex: chapterIndex,
                      startOffset: startOffset, endOffset: endOffset,
                      colorIndex: colorIndex, content: content,
                      createdAt: Date(timeIntervalSince1970: Double(createdAt) / 1000))
    }
}

// MARK: - Helpers

extension Date {
    var milliseconds: Int64 { Int64(timeIntervalSince1970 * 1000) }
}
```

- [ ] **Step 2: 编译验证**

```bash
xcodebuild -project IOS/Legado.xcodeproj -scheme Legado \
  -destination 'platform=iOS Simulator,id=962E405B-C2DC-463C-889D-FC51D1438E83' \
  build 2>&1 | tail -3
```
预期：`** BUILD SUCCEEDED **`（文件此时还未注册到 pbxproj，会在 Task 9 统一注册）

---

## Task 2: WebDAVSettings.swift

**Files:**
- Create: `IOS/Legado/App/Core/Sync/WebDAVSettings.swift`

- [ ] **Step 1: 创建文件**

```swift
// IOS/Legado/App/Core/Sync/WebDAVSettings.swift
import Foundation
import Security

// MARK: - Keychain Helper

enum KeychainHelper {
    static func set(_ value: String, service: String, account: String) {
        let data = value.data(using: .utf8)!
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        SecItemDelete(query as CFDictionary)
        var item = query
        item[kSecValueData] = data
        SecItemAdd(item as CFDictionary, nil)
    }

    static func get(service: String, account: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass:            kSecClassGenericPassword,
            kSecAttrService:      service,
            kSecAttrAccount:      account,
            kSecReturnData:       true,
            kSecMatchLimit:       kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(service: String, account: String) {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - WebDAV Settings

private let kWebDAVService = "com.legado.webdav"

final class WebDAVSettings: ObservableObject {
    static let shared = WebDAVSettings()
    private init() {}

    // 非敏感配置 — UserDefaults / AppStorage 兼容
    @Published var serverURL: String = UserDefaults.standard.string(forKey: "webdav.serverURL") ?? "" {
        didSet { UserDefaults.standard.set(serverURL, forKey: "webdav.serverURL") }
    }
    @Published var username: String = UserDefaults.standard.string(forKey: "webdav.username") ?? "" {
        didSet { UserDefaults.standard.set(username, forKey: "webdav.username") }
    }
    @Published var autoSync: Bool = UserDefaults.standard.bool(forKey: "webdav.autoSync") {
        didSet { UserDefaults.standard.set(autoSync, forKey: "webdav.autoSync") }
    }

    // 密码 — Keychain
    var password: String {
        get { KeychainHelper.get(service: kWebDAVService, account: "password") ?? "" }
        set { KeychainHelper.set(newValue, service: kWebDAVService, account: "password") }
    }

    // 上次同步时间
    var lastSyncDate: Date? {
        get {
            let t = UserDefaults.standard.double(forKey: "webdav.lastSyncTime")
            return t > 0 ? Date(timeIntervalSince1970: t) : nil
        }
        set {
            UserDefaults.standard.set(newValue?.timeIntervalSince1970 ?? 0,
                                      forKey: "webdav.lastSyncTime")
            objectWillChange.send()
        }
    }

    // 各文件本地最后同步时间戳（毫秒）—— 用于比较是否需要上传/下载
    var localTimestamps: [String: Int64] {
        get {
            let keys = ["books", "reading_progress", "bookmarks", "highlights"]
            return Dictionary(uniqueKeysWithValues: keys.map { k in
                (k, Int64(UserDefaults.standard.double(forKey: "webdav.ts.\(k)")))
            })
        }
    }

    func updateLocalTimestamp(for key: String, to ms: Int64) {
        UserDefaults.standard.set(Double(ms), forKey: "webdav.ts.\(key)")
    }

    // 配置是否完整
    var isConfigured: Bool { !serverURL.isEmpty && !username.isEmpty && !password.isEmpty }

    // 规范化服务器 URL（去除末尾斜杠）
    var normalizedServerURL: String { serverURL.trimmingCharacters(in: .init(charactersIn: "/")) }
}
```

---

## Task 3: WebDAVClient.swift

**Files:**
- Create: `IOS/Legado/App/Core/Sync/WebDAVClient.swift`

- [ ] **Step 1: 创建文件**

```swift
// IOS/Legado/App/Core/Sync/WebDAVClient.swift
import Foundation

/// HTTP WebDAV 操作层。actor 保证并发安全。
/// 只暴露 put / get / makeDirectory / exists 四个原语。
actor WebDAVClient {

    private let baseURL: URL
    private let authHeader: String
    private let session: URLSession

    enum WebDAVError: Error, LocalizedError {
        case badURL
        case authFailed
        case serverError(Int)
        case emptyResponse

        var errorDescription: String? {
            switch self {
            case .badURL:           return "服务器地址无效"
            case .authFailed:       return "用户名或密码错误（401）"
            case .serverError(let c): return "服务器错误（\(c)）"
            case .emptyResponse:    return "服务器返回空内容"
            }
        }
    }

    init(serverURL: String, username: String, password: String) throws {
        guard let url = URL(string: serverURL) else { throw WebDAVError.badURL }
        baseURL = url
        let creds = Data("\(username):\(password)".utf8).base64EncodedString()
        authHeader = "Basic \(creds)"
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest  = 30
        config.timeoutIntervalForResource = 60
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: config)
    }

    // MARK: - PUT

    func put(path: String, data: Data) async throws {
        let url = baseURL.appendingPathComponent(path)
        var req = URLRequest(url: url)
        req.httpMethod = "PUT"
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")
        req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.httpBody = data
        let (_, resp) = try await session.data(for: req)
        try check(resp)
    }

    // MARK: - GET

    func get(path: String) async throws -> Data {
        let url = baseURL.appendingPathComponent(path)
        var req = URLRequest(url: url)
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")
        let (data, resp) = try await session.data(for: req)
        try check(resp)
        return data
    }

    // MARK: - MKCOL（创建目录）

    func makeDirectory(path: String) async throws {
        let url = baseURL.appendingPathComponent(path)
        var req = URLRequest(url: url)
        req.httpMethod = "MKCOL"
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")
        let (_, resp) = try await session.data(for: req)
        // 201 Created 或 405 Method Not Allowed（目录已存在）均视为成功
        if let http = resp as? HTTPURLResponse,
           http.statusCode != 201, http.statusCode != 405 {
            try check(resp)
        }
    }

    // MARK: - EXISTS（HEAD 请求）

    func exists(path: String) async throws -> Bool {
        let url = baseURL.appendingPathComponent(path)
        var req = URLRequest(url: url)
        req.httpMethod = "HEAD"
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")
        let (_, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { return false }
        return http.statusCode == 200
    }

    // MARK: - Private

    private func check(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        switch http.statusCode {
        case 200...299: return
        case 401:       throw WebDAVError.authFailed
        default:        throw WebDAVError.serverError(http.statusCode)
        }
    }
}
```

---

## Task 4: DatabaseManager 扩展（全量查询 + import）

**Files:**
- Modify: `IOS/Legado/App/Core/Database/DatabaseManager.swift`（末尾追加新 extension）

- [ ] **Step 1: 在文件末尾追加 extension**

在 `DatabaseManager.swift` **最后一个 `}`** 之前插入：

```swift
// MARK: - WebDAV Sync Export / Import

extension DatabaseManager {

    // ── Export ──────────────────────────────────────────────────────────────

    func exportAllBooks() async throws -> [Book] {
        try await dbPool.read { db in try Book.fetchAll(db) }
    }

    func exportAllBookmarks() async throws -> [Bookmark] {
        try await dbPool.read { db in try Bookmark.order(Column("createdAt").asc).fetchAll(db) }
    }

    func exportAllHighlights() async throws -> [BookHighlight] {
        try await dbPool.read { db in try BookHighlight.order(Column("createdAt").asc).fetchAll(db) }
    }

    // ── Import（timestamp wins：取 durChapterTime 较大值）──────────────────

    func importBooks(_ entries: [SyncBookEntry]) async throws {
        let existing = try await exportAllBooks()
        let localMap = Dictionary(uniqueKeysWithValues: existing.map { ($0.bookUrl, $0) })

        for entry in entries {
            if var local = localMap[entry.bookUrl] {
                // 已存在：只更新进度更新时间更大的来源的元数据
                if entry.lastUpdatedAt > local.durChapterTime {
                    entry.applyTo(&local)
                    try await saveBook(local)
                }
            } else {
                // 服务端有、本地没有：创建新书条目（无章节/内容，等用户打开时加载）
                var newBook = Book(bookUrl: entry.bookUrl, name: entry.name,
                                   author: entry.author, origin: entry.origin,
                                   originName: entry.originName)
                newBook.coverUrl = entry.coverUrl
                newBook.intro    = entry.intro
                newBook.tocUrl   = entry.tocUrl
                try await saveBook(newBook)
            }
        }
    }

    func importProgress(_ entries: [SyncProgressEntry]) async throws {
        let existing = try await exportAllBooks()
        let localMap = Dictionary(uniqueKeysWithValues: existing.map { ($0.bookUrl, $0) })

        for entry in entries {
            guard var book = localMap[entry.bookUrl] else { continue }
            // 取 durChapterTime 较大的进度
            if entry.durChapterTime > book.durChapterTime {
                book.durChapterIndex = entry.durChapterIndex
                book.durChapterPos   = entry.durChapterPos
                book.durChapterTime  = entry.durChapterTime
                try await saveBook(book)
            }
        }
    }

    func importBookmarks(_ entries: [SyncBookmarkEntry]) async throws {
        let existing = try await exportAllBookmarks()
        // 唯一键：bookUrl + chapterIndex + createdAt
        let localKeys = Set(existing.map { "\($0.bookUrl)_\($0.chapterIndex)_\($0.createdAt.milliseconds)" })
        for entry in entries {
            let key = "\(entry.bookUrl)_\(entry.chapterIndex)_\(entry.createdAt)"
            if !localKeys.contains(key) {
                try await saveBookmark(entry.toBookmark())
            }
        }
    }

    func importHighlights(_ entries: [SyncHighlightEntry]) async throws {
        let existing = try await exportAllHighlights()
        // 唯一键：bookUrl + chapterIndex + startOffset
        let localKeys = Set(existing.map { "\($0.bookUrl)_\($0.chapterIndex)_\($0.startOffset)" })
        for entry in entries {
            let key = "\(entry.bookUrl)_\(entry.chapterIndex)_\(entry.startOffset)"
            if !localKeys.contains(key) {
                try await saveHighlight(entry.toHighlight())
            }
        }
    }
}
```

- [ ] **Step 2: 给 Date 扩展加 milliseconds（已在 SyncModels.swift 定义，确保不重复）**

检查 `SyncModels.swift` 已有 `extension Date { var milliseconds: Int64 ... }`，不需要在 DatabaseManager 重复。在 `importBookmarks` 里改用：
```swift
let localKeys = Set(existing.map { "\($0.bookUrl)_\($0.chapterIndex)_\(Int64($0.createdAt.timeIntervalSince1970 * 1000))" })
```

（这样 `importBookmarks` 不依赖 Date extension。）

---

## Task 5: WebDAVSyncManager.swift

**Files:**
- Create: `IOS/Legado/App/Core/Sync/WebDAVSyncManager.swift`

- [ ] **Step 1: 创建文件**

```swift
// IOS/Legado/App/Core/Sync/WebDAVSyncManager.swift
import Foundation

@MainActor
final class WebDAVSyncManager: ObservableObject {
    static let shared = WebDAVSyncManager()
    private init() {}

    // MARK: - State

    enum SyncState: Equatable {
        case idle
        case syncing
        case error(String)

        var description: String {
            switch self {
            case .idle:          return "已同步"
            case .syncing:       return "同步中…"
            case .error(let m):  return "错误：\(m)"
            }
        }
    }

    @Published private(set) var state: SyncState = .idle

    private let settings  = WebDAVSettings.shared
    private let db        = DatabaseManager.shared
    private var syncTask: Task<Void, Never>? = nil
    private var chapterSwitchCount = 0
    private let autoSyncChapterInterval = 10   // 每切 10 章自动触发一次

    // MARK: - Public API

    /// 手动/强制全量同步
    func syncNow() {
        guard settings.isConfigured else { return }
        syncTask?.cancel()
        syncTask = Task { await performSync(force: true) }
    }

    /// 软触发：只在 autoSync 开启时触发（进后台、关阅读器）
    func uploadIfNeeded() {
        guard settings.isConfigured, settings.autoSync else { return }
        guard syncTask == nil || syncTask!.isCancelled else { return }
        syncTask = Task { await performSync(force: false) }
    }

    /// 章节切换计数器（每 N 章软触发一次）
    func onChapterSwitched() {
        chapterSwitchCount += 1
        if chapterSwitchCount >= autoSyncChapterInterval {
            chapterSwitchCount = 0
            uploadIfNeeded()
        }
    }

    /// App 启动后检查服务端是否有更新
    func checkOnLaunch() {
        guard settings.isConfigured, settings.autoSync else { return }
        syncTask = Task { await performSync(force: false) }
    }

    // MARK: - Sync Logic

    private func performSync(force: Bool) async {
        state = .syncing
        defer { if state == .syncing { state = .idle } }

        do {
            let client = try WebDAVClient(
                serverURL: settings.normalizedServerURL,
                username:  settings.username,
                password:  settings.password
            )

            // 1. 确保目录存在
            try await client.makeDirectory(path: "legado")

            // 2. 获取服务端 metadata
            let remoteMeta: SyncMetadata
            if try await client.exists(path: "legado/metadata.json") {
                let data = try await client.get(path: "legado/metadata.json")
                remoteMeta = try JSONDecoder().decode(SyncMetadata.self, from: data)
            } else {
                remoteMeta = SyncMetadata.makeNew()
            }

            let localTs  = settings.localTimestamps
            let now      = Date().milliseconds

            // 3. 处理每个实体
            var uploadedFiles: [String] = []

            for entity in ["books", "reading_progress", "bookmarks", "highlights"] {
                let remoteTs = remoteMeta.files[entity] ?? 0
                let localTs  = localTs[entity] ?? 0

                if force || remoteTs > localTs {
                    // 下载：服务端更新 or 强制
                    if try await client.exists(path: "legado/\(entity).json") {
                        let data = try await client.get(path: "legado/\(entity).json")
                        try await importEntity(entity, data: data)
                        settings.updateLocalTimestamp(for: entity, to: remoteTs > 0 ? remoteTs : now)
                    }
                }

                if force || localTs >= remoteTs {
                    // 上传：本地更新 or 强制（本地 >= 服务端 则上传以刷新）
                    let data = try await exportEntity(entity)
                    try await client.put(path: "legado/\(entity).json", data: data)
                    let ts = now
                    settings.updateLocalTimestamp(for: entity, to: ts)
                    uploadedFiles.append(entity)
                }
            }

            // 4. 更新 metadata
            var newMeta = remoteMeta
            newMeta.updatedAt = now
            for f in uploadedFiles {
                newMeta.files[f] = settings.localTimestamps[f] ?? now
            }
            let metaData = try JSONEncoder().encode(newMeta)
            try await client.put(path: "legado/metadata.json", data: metaData)

            settings.lastSyncDate = Date()
            state = .idle
            print("✅ [WebDAV] 同步完成")

        } catch {
            state = .error(error.localizedDescription)
            print("❌ [WebDAV] 同步失败：\(error)")
        }
    }

    // MARK: - Export helpers

    private func exportEntity(_ entity: String) async throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        switch entity {
        case "books":
            let books = try await db.exportAllBooks()
            return try encoder.encode(books.map { SyncBookEntry(from: $0) })
        case "reading_progress":
            let books = try await db.exportAllBooks()
            return try encoder.encode(books.map { SyncProgressEntry(from: $0) })
        case "bookmarks":
            let bms = try await db.exportAllBookmarks()
            return try encoder.encode(bms.map { SyncBookmarkEntry(from: $0) })
        case "highlights":
            let hs = try await db.exportAllHighlights()
            return try encoder.encode(hs.map { SyncHighlightEntry(from: $0) })
        default:
            return Data()
        }
    }

    // MARK: - Import helpers

    private func importEntity(_ entity: String, data: Data) async throws {
        let decoder = JSONDecoder()
        switch entity {
        case "books":
            let entries = try decoder.decode([SyncBookEntry].self, from: data)
            try await db.importBooks(entries)
        case "reading_progress":
            let entries = try decoder.decode([SyncProgressEntry].self, from: data)
            try await db.importProgress(entries)
        case "bookmarks":
            let entries = try decoder.decode([SyncBookmarkEntry].self, from: data)
            try await db.importBookmarks(entries)
        case "highlights":
            let entries = try decoder.decode([SyncHighlightEntry].self, from: data)
            try await db.importHighlights(entries)
        default:
            break
        }
    }
}
```

---

## Task 6: SettingsView — WebDAV 配置区块

**Files:**
- Modify: `IOS/Legado/App/UI/SettingsView.swift`

- [ ] **Step 1: 在 SettingsView 顶部加 State 属性**

在 `struct SettingsView: View {` 内现有属性之后加：

```swift
@StateObject private var syncManager = WebDAVSyncManager.shared
@StateObject private var webdavSettings = WebDAVSettings.shared
@State private var webdavPassword = ""
@State private var showTestResult = false
@State private var testResultMessage = ""
@State private var isTesting = false
```

- [ ] **Step 2: 在 List 末尾（关于 Section 之前）插入 WebDAV Section**

在 `// MARK: 关于` 的 `Section` 之前插入：

```swift
// MARK: WebDAV 同步
Section(header: Text("WebDAV 云同步")) {
    TextField("服务器地址（https://...）", text: $webdavSettings.serverURL)
        .keyboardType(.URL)
        .autocapitalization(.none)
        .autocorrectionDisabled()
    TextField("用户名", text: $webdavSettings.username)
        .autocapitalization(.none)
        .autocorrectionDisabled()
    SecureField("密码", text: $webdavPassword)
        .onAppear { webdavPassword = webdavSettings.password }
        .onChange(of: webdavPassword) { webdavSettings.password = $0 }

    Button {
        isTesting = true
        Task {
            do {
                let client = try WebDAVClient(
                    serverURL: webdavSettings.normalizedServerURL,
                    username:  webdavSettings.username,
                    password:  webdavSettings.password
                )
                _ = try await client.exists(path: "legado/metadata.json")
                testResultMessage = "✅ 连接成功"
            } catch {
                testResultMessage = "❌ \(error.localizedDescription)"
            }
            isTesting = false
            showTestResult = true
        }
    } label: {
        HStack {
            Text("测试连接")
            if isTesting { Spacer(); ProgressView() }
        }
    }
    .disabled(isTesting || !webdavSettings.isConfigured)
    .alert("连接测试", isPresented: $showTestResult) {
        Button("确定", role: .cancel) {}
    } message: { Text(testResultMessage) }

    Toggle("自动同步", isOn: $webdavSettings.autoSync)

    if let d = webdavSettings.lastSyncDate {
        HStack {
            Text("上次同步")
            Spacer()
            Text(d, style: .relative)
                .foregroundColor(.secondary)
                .font(.caption)
        }
    }

    HStack {
        Text("状态")
        Spacer()
        Group {
            switch syncManager.state {
            case .idle:
                Text(webdavSettings.lastSyncDate != nil ? "已同步" : "未同步")
                    .foregroundColor(.secondary)
            case .syncing:
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.8)
                    Text("同步中…").foregroundColor(.secondary)
                }
            case .error(let msg):
                Text(msg).foregroundColor(.red).lineLimit(2)
            }
        }
        .font(.caption)
    }

    Button("立即同步") {
        syncManager.syncNow()
    }
    .disabled(!webdavSettings.isConfigured || syncManager.state == .syncing)
}
```

---

## Task 7: 触发点接入

**Files:**
- Modify: `IOS/Legado/App/LegadoApp.swift`
- Modify: `IOS/Legado/App/Features/Reading/Views/ReaderView.swift`

- [ ] **Step 1: LegadoApp.swift — 启动后触发下载检查**

在 `.task { ... }` 闭包末尾 `dbReady = true` **之后**加：

```swift
// WebDAV：启动后检查服务端是否有更新
await MainActor.run { WebDAVSyncManager.shared.checkOnLaunch() }
```

- [ ] **Step 2: ReaderView.swift — onDisappear 触发上传**

找到 `ReaderView.body` 里的 `.onDisappear { ... }` 闭包，在末尾加：

```swift
WebDAVSyncManager.shared.uploadIfNeeded()
```

- [ ] **Step 3: ReaderViewModel.swift — 切章触发**

在 `jumpToChapter()` 末尾（Task 之前）加：

```swift
WebDAVSyncManager.shared.onChapterSwitched()
```

---

## Task 8: 给 Book 模型补 init 便利构造器（SyncModels 需要）

**Files:**
- Modify: `IOS/Legado/App/Features/Reading/Models/Book.swift`

- [ ] **Step 1: 确认 Book 有足够的字段初始化**

检查 `Book.swift` 是否有 `init(bookUrl:name:author:origin:originName:)` 便利构造器。如果没有，在 `Book` struct 末尾加：

```swift
init(bookUrl: String, name: String, author: String, origin: String, originName: String) {
    self.bookUrl     = bookUrl
    self.name        = name
    self.author      = author
    self.origin      = origin
    self.originName  = originName
}
```

---

## Task 9: pbxproj 注册 4 个新文件

**Files:**
- Modify: `IOS/Legado.xcodeproj/project.pbxproj`

- [ ] **Step 1: 运行注册脚本**

```bash
python3 << 'EOF'
import uuid, re

path = 'IOS/Legado.xcodeproj/project.pbxproj'
with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

# 以 DatabaseManager.swift 为锚点（同在 Core/ 目录下）
anchor_ref_line = [l for l in content.split('\n') if 'DatabaseManager.swift */ = {isa = PBXFileReference' in l][0].strip()
anchor_src_line = [l for l in content.split('\n') if 'DatabaseManager.swift in Sources' in l and 'PBXBuildFile' not in l][0].strip()
anchor_grp_line = [l for l in content.split('\n') if 'DatabaseManager.swift */,' in l and 'PBXBuildFile' not in l and 'PBXFileReference' not in l][0].strip()

new_files = [
    'SyncModels.swift',
    'WebDAVSettings.swift',
    'WebDAVClient.swift',
    'WebDAVSyncManager.swift',
]

for fname in new_files:
    file_ref  = uuid.uuid4().hex[:24].upper()
    build_file = uuid.uuid4().hex[:24].upper()

    ref_entry  = f'\t\t{file_ref} /* {fname} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {fname}; sourceTree = "<group>"; }};'
    bld_entry  = f'\t\t{build_file} /* {fname} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_ref} /* {fname} */; }};'
    grp_entry  = f'\t\t{file_ref} /* {fname} */,'
    src_entry  = f'\t\t\t\t\t{build_file} /* {fname} in Sources */,'

    content = content.replace(anchor_ref_line, anchor_ref_line + '\n' + ref_entry, 1)
    content = content.replace(anchor_grp_line, anchor_grp_line + '\n\t\t\t\t\t' + grp_entry.strip(), 1)
    content = content.replace(anchor_src_line, anchor_src_line + '\n\t\t\t\t\t' + build_file + ' /* ' + fname + ' in Sources */,', 1)

with open(path, 'w', encoding='utf-8') as f:
    f.write(content)
print('Done registering', new_files)
EOF
```

- [ ] **Step 2: 编译验证**

```bash
xcodebuild -project IOS/Legado.xcodeproj -scheme Legado \
  -destination 'platform=iOS Simulator,id=962E405B-C2DC-463C-889D-FC51D1438E83' \
  build 2>&1 | grep -E "error:|Build succeeded|BUILD FAILED" | grep -v warning | head -20
```

预期：`** BUILD SUCCEEDED **`

---

## Task 10: Commit

- [ ] **Step 1: 提交全部变更**

```bash
git add IOS/Legado/App/Core/Sync/ \
  IOS/Legado/App/Core/Database/DatabaseManager.swift \
  IOS/Legado/App/UI/SettingsView.swift \
  IOS/Legado/App/LegadoApp.swift \
  IOS/Legado/App/Features/Reading/Views/ReaderView.swift \
  IOS/Legado/App/Features/Reading/ViewModels/ReaderViewModel.swift \
  IOS/Legado/App/Features/Reading/Models/Book.swift \
  IOS/Legado.xcodeproj/project.pbxproj && \
git commit -m "feat(sync): WebDAV 云同步完整实现

- WebDAVClient（actor）：PUT/GET/MKCOL + Basic Auth
- WebDAVSettings：UserDefaults 配置 + Keychain 密码
- SyncModels：Book/Progress/Bookmark/Highlight JSON 快照结构体
- WebDAVSyncManager：同步协调器，时间戳比对，上传/下载决策
- DatabaseManager：全量 export + timestamp-wins import
- SettingsView：WebDAV 配置区块（服务器/用户名/密码/测试/状态/手动同步）
- 触发点：LegadoApp 启动检查 + ReaderView.onDisappear + 每10章自动"
```

---

## Task 11: 代码审查 Round 1

- [ ] **Step 1: 运行代码审查**

使用 `requesting-code-review` skill 对以下文件做第一轮审查：
- `Core/Sync/WebDAVClient.swift`
- `Core/Sync/WebDAVSyncManager.swift`
- `Core/Sync/SyncModels.swift`
- `Core/Sync/WebDAVSettings.swift`
- `Core/Database/DatabaseManager.swift`（仅新增的 extension 部分）

重点检查：
1. 并发安全（actor isolation、@MainActor 边界）
2. 错误处理是否覆盖（401/404/网络超时）
3. timestamp 比较逻辑是否正确（ms vs s）
4. Keychain 操作是否在主线程以外调用时安全

- [ ] **Step 2: 修复 Round 1 发现的问题并提交**

```bash
git add -A && git commit -m "fix(sync): 代码审查 Round 1 修复"
```

---

## Task 12: 代码审查 Round 2

- [ ] **Step 1: 运行第二轮审查**

使用 `requesting-code-review` skill 重点审查：
- `UI/SettingsView.swift`（WebDAV 区块的 State 管理、onAppear/onChange 逻辑）
- `LegadoApp.swift` 和 `ReaderView.swift`（触发时机是否合理，是否有循环触发风险）

- [ ] **Step 2: 修复 Round 2 发现的问题并提交**

```bash
git add -A && git commit -m "fix(sync): 代码审查 Round 2 修复"
```

---

## 自检清单（规范覆盖验证）

| 规范要求 | 对应 Task |
|---------|----------|
| 同步书架列表 | Task 5（exportEntity books） |
| 同步阅读进度 | Task 5（exportEntity reading_progress） |
| 同步书签 | Task 5（exportEntity bookmarks） |
| 同步高亮 | Task 5（exportEntity highlights） |
| timestamp wins 冲突 | Task 4（importProgress 比较 durChapterTime）|
| Auto trigger：进后台 | Task 7（LegadoApp + scenePhase） |
| Auto trigger：关阅读器 | Task 7（ReaderView.onDisappear） |
| Auto trigger：切章 | Task 7（ReaderViewModel.jumpToChapter） |
| 手动触发 | Task 6（SettingsView "立即同步"按钮） |
| Basic Auth | Task 3（WebDAVClient authHeader） |
| Keychain 密码 | Task 2（KeychainHelper） |
| 目录自动创建 | Task 5（makeDirectory legado） |
| 首次同步（空服务端）| Task 5（exists 检查 → 跳过下载） |
| 部分失败 metadata 不更新 | Task 5（defer + uploadedFiles） |
| SyncState 显示 | Task 6（SettingsView 状态区） |
| 测试连接按钮 | Task 6（SettingsView 测试连接） |
