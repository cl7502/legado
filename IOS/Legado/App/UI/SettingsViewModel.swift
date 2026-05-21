import SwiftUI

/// 设置界面业务逻辑
@MainActor
class SettingsViewModel: ObservableObject {
    @Published var appVersion = "2.0.0 (GSD-Core)"
    @Published var cacheSize = "计算中..."
    
    func clearCache() {
        // 清理 URLCache
        URLCache.shared.removeAllCachedResponses()
        cacheSize = "0 MB"
    }
    
    func clearCookies() {
        CookieManager.shared.clearAll()
    }
    
    func clearDatabase() {
        Task {
            try? await DatabaseManager.shared.dbPool.write { db in
                try db.execute(sql: "DELETE FROM book_source")
                try db.execute(sql: "DELETE FROM book")
            }
        }
    }
}
