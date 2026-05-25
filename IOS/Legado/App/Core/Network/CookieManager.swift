import Foundation

/// Cookie 持久化管理器
/// 目标：确保书源登录状态不丢失
class CookieManager {
    static let shared = CookieManager()
    
    private let storageKey = "com.legado.cookies"
    private var cookies: [String: String] = [:] // 域名 -> Cookie 字符串
    
    private init() {
        loadFromDisk()
    }
    
    /// 获取指定 URL 的 Cookie
    func getCookie(for url: String) -> String? {
        guard let host = URL(string: url)?.host else { return nil }
        return cookies[host]
    }
    
    /// 保存 Cookie (对标 Android 的 CookieInterceptor)
    func saveCookie(for url: String, cookieString: String) {
        guard let host = URL(string: url)?.host else { return }
        cookies[host] = cookieString
        saveToDisk()
    }
    
    private func saveToDisk() {
        UserDefaults.standard.set(cookies, forKey: storageKey)
    }
    
    private func loadFromDisk() {
        if let saved = UserDefaults.standard.dictionary(forKey: storageKey) as? [String: String] {
            cookies = saved
        }
    }
    
    /// 按任意 tag 键存储 Cookie（对标 Android JsExtensions.setCookie）
    func saveCookie(forTag tag: String, value: String) {
        cookies[tag] = value
        saveToDisk()
    }

    /// 清理所有 Cookie
    func clearAll() {
        cookies.removeAll()
        UserDefaults.standard.removeObject(forKey: storageKey)
    }
}
