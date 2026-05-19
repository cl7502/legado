import Foundation
import GRDB

/// 数据库管理器
/// 目标：使用 GRDB 实现高性能持久化，支持并发读取
class DatabaseManager {
    static let shared = DatabaseManager()
    
    var dbPool: DatabasePool!
    
    private init() {
        setupDatabase()
    }
    
    private func setupDatabase() {
        do {
            let databaseURL = try FileManager.default
                .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("legado.sqlite")
            
            var config = Configuration()
            config.prepareDatabase { db in
                // 启用外键
                try db.execute(sql: "PRAGMA foreign_keys = ON")
            }
            
            dbPool = try DatabasePool(path: databaseURL.path, configuration: config)
            
            // TODO: 阶段 7 将实现具体的数据库迁移 (Migrations)
        } catch {
            fatalError("Failed to initialize database: \(error)")
        }
    }
}
