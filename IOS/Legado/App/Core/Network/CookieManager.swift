import Foundation

/// Cookie 持久化管理器
/// 目标：确保书源登录状态不丢失
class CookieManager {
    static let shared = CookieManager()

    private let storageKey = "com.legado.cookies"
    private var cookies: [String: String] = [:]
    // 串行队列：保护 cookies 字典的并发读写（prefetch 并发请求会触发并发写入）
    private let queue = DispatchQueue(label: "com.legado.CookieManager", attributes: .concurrent)

    private init() {
        loadFromDisk()
    }

    /// 获取指定 URL 的 Cookie
    func getCookie(for url: String) -> String? {
        guard let host = URL(string: url)?.host else { return nil }
        return queue.sync { cookies[host] }
    }

    /// 保存 Cookie (对标 Android 的 CookieInterceptor)
    func saveCookie(for url: String, cookieString: String) {
        guard let host = URL(string: url)?.host else { return }
        queue.async(flags: .barrier) { [weak self] in
            self?.cookies[host] = cookieString
            self?.trimIfNeeded()
            self?.saveToDisk()
        }
    }

    private func trimIfNeeded() {
        // W-9: 最多保留 200 条，防止无限增长（每条写入 UserDefaults 有双倍内存开销）
        guard cookies.count > 200 else { return }
        let overflow = cookies.count - 200
        cookies.keys.prefix(overflow).forEach { cookies.removeValue(forKey: $0) }
    }

    private func saveToDisk() {
        // 必须在 barrier block 内调用（已持有写锁）
        UserDefaults.standard.set(cookies, forKey: storageKey)
    }

    private func loadFromDisk() {
        if let saved = UserDefaults.standard.dictionary(forKey: storageKey) as? [String: String] {
            cookies = saved
        }
    }

    /// 按任意 tag 键存储 Cookie（对标 Android JsExtensions.setCookie）
    func saveCookie(forTag tag: String, value: String) {
        queue.async(flags: .barrier) { [weak self] in
            self?.cookies[tag] = value
            self?.saveToDisk()
        }
    }

    /// 按 tag 直接读取（对标 Android JsExtensions.getCookie(tag)）
    func getCookie(forTag tag: String) -> String? {
        queue.sync { cookies[tag] }
    }

    /// 按 tag 删除（对标 Android JsExtensions.removeCookie(tag)）
    func removeCookie(forTag tag: String) {
        queue.async(flags: .barrier) { [weak self] in
            self?.cookies.removeValue(forKey: tag)
            self?.saveToDisk()
        }
    }

    /// 清理所有 Cookie
    func clearAll() {
        queue.async(flags: .barrier) { [weak self] in
            self?.cookies.removeAll()
            UserDefaults.standard.removeObject(forKey: self?.storageKey ?? "com.legado.cookies")
        }
    }
}
