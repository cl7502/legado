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
}
