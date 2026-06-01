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
            case .badURL:               return "服务器地址无效"
            case .authFailed:           return "用户名或密码错误（401）"
            case .serverError(let c):   return "服务器错误（\(c)）"
            case .emptyResponse:        return "服务器返回空内容"
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

    deinit {
        session.invalidateAndCancel()
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
        // 200/201 Created、301 Moved、405 Method Not Allowed（目录已存在）均视为成功；
        // 409 Conflict 表示父目录不存在（非"已存在"），不应忽略
        let successCodes: Set<Int> = [200, 201, 301, 405]
        if let http = resp as? HTTPURLResponse, !successCodes.contains(http.statusCode) {
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
        switch http.statusCode {
        case 200, 204:  return true
        case 404:       return false
        case 401:       throw WebDAVError.authFailed
        default:        throw WebDAVError.serverError(http.statusCode)
        }
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
