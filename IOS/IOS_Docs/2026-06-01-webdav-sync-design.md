# WebDAV 云同步设计规范
> 日期：2026-06-01  
> 状态：已批准，待实现

---

## 1. 功能范围

- **同步内容**：书架列表 + 阅读进度 + 书签 + 高亮划线（完整版）
- **冲突策略**：最新时间戳优先（timestamp wins）
- **触发方式**：自动（进后台 / 关阅读器 / 每 N 章）+ 手动按钮
- **认证方式**：HTTP Basic Auth，密码存 Keychain

---

## 2. 架构

### 新增模块

```
IOS/Legado/App/Core/Sync/
  WebDAVClient.swift       // HTTP 层：PUT / GET / MKCOL，Basic Auth
  WebDAVSyncManager.swift  // 同步协调器：时间戳比对、上传/下载决策
  SyncModels.swift         // JSON 可编码结构体（各实体快照）
```

### 数据流

```
触发同步
   ↓
WebDAVSyncManager.sync()
   ├─ GET /legado/metadata.json（获取服务端各文件时间戳）
   ├─ 比较本地 lastSyncTime[entity]
   ├─ 服务端更新 → GET entity.json → db.merge(timestampWins: .latest)
   ├─ 本地更新  → db.export() → PUT entity.json
   └─ 全部成功  → PUT metadata.json（更新时间戳）
```

### WebDAV 服务器目录

```
/legado/
  metadata.json           # 版本控制与各文件时间戳索引
  books.json              # 书架快照
  reading_progress.json   # 阅读进度
  bookmarks.json          # 书签
  highlights.json         # 高亮划线
```

---

## 3. 数据格式

### metadata.json

```json
{
  "version": 1,
  "deviceId": "UUID（本机唯一，首次生成后持久化）",
  "updatedAt": 1748736000000,
  "files": {
    "books": 1748735000000,
    "reading_progress": 1748736000000,
    "bookmarks": 1748730000000,
    "highlights": 1748729000000
  }
}
```

### reading_progress.json

```json
[{
  "bookUrl": "https://...",
  "durChapterIndex": 12,
  "durChapterPos": 3,
  "durChapterTime": 1748736000000
}]
```

### books.json（只含元数据，不含正文缓存）

```json
[{
  "bookUrl": "...",
  "name": "...",
  "author": "...",
  "origin": "...",
  "originName": "...",
  "coverUrl": "...",
  "intro": "...",
  "tocUrl": "...",
  "lastUpdatedAt": 1748736000000
}]
```

### bookmarks.json / highlights.json

- 含 `createdAt` / `updatedAt` 时间戳
- 合并规则：本地有、服务端没有 → 保留本地；服务端有、本地没有 → 写入本地；两端都有 → 取 `updatedAt` 较大的

---

## 4. 触发时机

| 事件 | 行为 |
|------|------|
| App 进入后台 (`scenePhase == .background`) | 触发上传 |
| `ReaderView.onDisappear` | 触发上传（静默，不阻塞 UI）|
| 每切换 10 章（章节计数器） | 触发上传 |
| App 启动后台完成 DB 初始化后 | 触发下载检查 |
| 设置页"立即同步"按钮 | 强制全量同步 |

---

## 5. 凭证存储

- 服务器地址：`UserDefaults`（非敏感）
- 用户名：`UserDefaults`（非敏感）
- 密码：**Keychain**（`kSecClassGenericPassword`，service = `com.legado.webdav`）

---

## 6. UI

### 设置页新增区块

```
WebDAV 同步
  服务器地址  [https://...      ]
  用户名      [username         ]
  密码        [••••••••         ]
               [测试连接]
  ─────────────────────────────
  自动同步    [开关]
  上次同步    2026-06-01 14:32
  同步状态    ✅ 已同步 / 🔄 同步中 / ❌ 错误原因
               [立即同步]
```

### SyncState 枚举

```swift
enum SyncState {
    case idle          // 已同步或未配置
    case syncing       // 进行中（显示 ProgressView）
    case error(String) // 错误（显示红色说明）
}
```

---

## 7. 错误处理

| 情况 | 处理方式 |
|------|---------|
| 网络错误 | 静默重试最多 2 次（指数退避），失败更新 SyncState.error |
| 认证失败（401） | 立即停止，提示"用户名或密码错误" |
| 目录不存在 | 自动 MKCOL /legado/ 创建 |
| 首次同步（服务器空） | 全量上传本地数据 |
| 首次同步（本地空） | 全量下载服务器数据 |
| 部分文件上传失败 | metadata.json 不更新，下次重试失败文件 |
| App 被杀死（同步中途） | metadata.json 未更新，下次重启重新比较，数据安全 |

---

## 8. 实现顺序

1. `WebDAVClient` — HTTP 基础操作（PUT/GET/MKCOL + Basic Auth + Keychain）
2. `SyncModels` — JSON 序列化结构体
3. `DatabaseManager` 扩展 — export/import 方法
4. `WebDAVSyncManager` — 同步逻辑核心
5. 设置页 UI — WebDAV 配置区块
6. 触发点接入 — LegadoApp / ReaderView / 章节计数器
