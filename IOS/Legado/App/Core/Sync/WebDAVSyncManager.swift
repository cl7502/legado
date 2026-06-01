// IOS/Legado/App/Core/Sync/WebDAVSyncManager.swift
import Foundation
import UIKit

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
            case .idle:         return "已同步"
            case .syncing:      return "同步中…"
            case .error(let m): return "错误：\(m)"
            }
        }
    }

    @Published private(set) var state: SyncState = .idle

    private let settings = WebDAVSettings.shared
    private let db       = DatabaseManager.shared
    private var syncTask: Task<Void, Never>? = nil
    private var chapterSwitchCount = 0
    private let autoSyncChapterInterval = 10

    // MARK: - Public API

    func syncNow() {
        guard settings.isConfigured, state != .syncing else { return }
        syncTask?.cancel()
        syncTask = Task { await performSync(force: true) }
    }

    func uploadIfNeeded() {
        guard settings.isConfigured, settings.autoSync, state != .syncing else { return }
        syncTask?.cancel()
        syncTask = Task { await performSync(force: false) }
    }

    func onChapterSwitched() {
        chapterSwitchCount += 1
        if chapterSwitchCount >= autoSyncChapterInterval {
            chapterSwitchCount = 0
            uploadIfNeeded()
        }
    }

    func checkOnLaunch() {
        guard settings.isConfigured, settings.autoSync else { return }
        syncTask?.cancel()
        syncTask = Task { await performSync(force: false) }
    }

    // MARK: - Sync Logic

    private func performSync(force: Bool) async {
        // 注册后台任务，防止 App 进入后台时上传被系统截断导致 metadata 与实体不一致
        var bgTask = UIBackgroundTaskIdentifier.invalid
        bgTask = UIApplication.shared.beginBackgroundTask(withName: "WebDAV Sync") { [weak self] in
            self?.syncTask?.cancel()
            UIApplication.shared.endBackgroundTask(bgTask)
            bgTask = .invalid
        }
        defer {
            if bgTask != .invalid {
                UIApplication.shared.endBackgroundTask(bgTask)
                bgTask = .invalid
            }
        }

        state = .syncing
        defer {
            if state == .syncing { state = .idle }
        }

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

            let localTs = settings.localTimestamps
            let now     = Date().milliseconds
            var uploadedFiles: [String] = []
            var uploadTimestamps: [String: Int64] = [:]

            // 3. 处理每个实体
            for entity in ["books", "reading_progress", "bookmarks", "highlights"] {
                let remoteTs = remoteMeta.files[entity] ?? 0
                let localT   = localTs[entity] ?? 0

                // 下载阶段：服务端有更新数据时先拉取合并
                if force || remoteTs > localT {
                    if try await client.exists(path: "legado/\(entity).json") {
                        let data = try await client.get(path: "legado/\(entity).json")
                        try await importEntity(entity, data: data)
                        settings.updateLocalTimestamp(for: entity, to: remoteTs > 0 ? remoteTs : now)
                    }
                }

                // 上传阶段：本地不落后于服务端时上传（包含 force、localT>=remoteTs、首次同步）
                if force || localT >= remoteTs {
                    let data = try await exportEntity(entity)
                    try await client.put(path: "legado/\(entity).json", data: data)
                    settings.updateLocalTimestamp(for: entity, to: now)
                    uploadTimestamps[entity] = now
                    uploadedFiles.append(entity)
                }
            }

            // 4. 更新 metadata
            var newMeta = remoteMeta
            newMeta.updatedAt = now
            for f in uploadedFiles { newMeta.files[f] = uploadTimestamps[f] ?? now }
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
