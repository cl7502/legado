// IOS/Legado/App/Core/Sync/WebDAVSettings.swift
import Foundation
import Security

// MARK: - Keychain Helper

enum KeychainHelper {
    static func set(_ value: String, service: String, account: String) {
        guard let data = value.data(using: .utf8) else { return }
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
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData:  true,
            kSecMatchLimit:  kSecMatchLimitOne
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

    @Published var serverURL: String = UserDefaults.standard.string(forKey: "webdav.serverURL") ?? "" {
        didSet { UserDefaults.standard.set(serverURL, forKey: "webdav.serverURL") }
    }
    @Published var username: String = UserDefaults.standard.string(forKey: "webdav.username") ?? "" {
        didSet { UserDefaults.standard.set(username, forKey: "webdav.username") }
    }
    @Published var autoSync: Bool = UserDefaults.standard.bool(forKey: "webdav.autoSync") {
        didSet { UserDefaults.standard.set(autoSync, forKey: "webdav.autoSync") }
    }

    var password: String {
        get { KeychainHelper.get(service: kWebDAVService, account: "password") ?? "" }
        set { KeychainHelper.set(newValue, service: kWebDAVService, account: "password") }
    }

    var lastSyncDate: Date? {
        get {
            let t = UserDefaults.standard.double(forKey: "webdav.lastSyncTime")
            return t > 0 ? Date(timeIntervalSince1970: t) : nil
        }
        set {
            UserDefaults.standard.set(newValue?.timeIntervalSince1970 ?? 0, forKey: "webdav.lastSyncTime")
            objectWillChange.send()
        }
    }

    var localTimestamps: [String: Int64] {
        let keys = ["books", "reading_progress", "bookmarks", "highlights"]
        return Dictionary(uniqueKeysWithValues: keys.map { k in
            (k, Int64(UserDefaults.standard.double(forKey: "webdav.ts.\(k)")))
        })
    }

    func updateLocalTimestamp(for key: String, to ms: Int64) {
        UserDefaults.standard.set(Double(ms), forKey: "webdav.ts.\(key)")
    }

    var isConfigured: Bool { !serverURL.isEmpty && !username.isEmpty && !password.isEmpty }

    var normalizedServerURL: String { serverURL.trimmingCharacters(in: .init(charactersIn: "/")) }
}
