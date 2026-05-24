import Foundation
import JavaScriptCore
import CryptoKit
import SwiftSoup

/// Rhino API 兼容协议 — 对标 Android JsExtensions
@objc protocol JSJavaHelperProtocol: JSExport {
    // 网络
    func ajax(_ url: String) -> String?
    func ajaxAll(_ urlArray: JSValue) -> JSValue?
    func post(_ url: String, _ body: String) -> String?
    // 变量
    func put(_ key: String, _ value: Any)
    func get(_ key: String) -> Any?
    // 加密/编码
    func md5(_ text: String) -> String
    func sha1(_ text: String) -> String
    func base64Encode(_ text: String) -> String
    func base64Decode(_ text: String) -> String
    func urlEncode(_ text: String) -> String
    func urlDecode(_ text: String) -> String
    func htmlEncode(_ text: String) -> String
    func htmlDecode(_ text: String) -> String
    // 压缩
    func gzip(_ text: String) -> String?
    func unGzip(_ base64: String) -> String?
    func zlib(_ text: String) -> String?
    func unZlib(_ base64: String) -> String?
    // HTML 查询
    func queryTextContent(_ html: String, _ cssSelector: String) -> String?
    func queryAllTextContent(_ html: String, _ cssSelector: String) -> String
    // 阅读器状态
    func getLastChapter() -> String?
    func getBook() -> String?
    // 时间/系统
    func getNetworkTime() -> String
    func timeFormat(_ timestamp: String) -> String
    func log(_ message: Any)
}

class JSJavaHelper: NSObject, JSJavaHelperProtocol {
    var currentContext: AnalyzeContext?

    // MARK: - 网络

    func ajax(_ url: String) -> String? {
        NetworkManager.shared.requestSync(url)
    }

    func post(_ url: String, _ body: String) -> String? {
        NetworkManager.shared.requestSync(url, method: "POST", body: body)
    }

    func ajaxAll(_ urlArray: JSValue) -> JSValue? {
        // 同步批量请求（依次执行）
        guard let urls = urlArray.toArray() as? [String] else { return nil }
        let results = urls.map { NetworkManager.shared.requestSync($0) ?? "" }
        return JSValue(object: results, in: urlArray.context)
    }

    // MARK: - 变量

    func put(_ key: String, _ value: Any) {
        currentContext?.variables[key] = value
    }

    func get(_ key: String) -> Any? {
        currentContext?.variables[key]
    }

    // MARK: - 加密/编码

    func md5(_ text: String) -> String {
        let digest = Insecure.MD5.hash(data: Data(text.utf8))
        return digest.map { String(format: "%02hhx", $0) }.joined()
    }

    func sha1(_ text: String) -> String {
        let digest = Insecure.SHA1.hash(data: Data(text.utf8))
        return digest.map { String(format: "%02hhx", $0) }.joined()
    }

    func base64Encode(_ text: String) -> String {
        Data(text.utf8).base64EncodedString()
    }

    func base64Decode(_ text: String) -> String {
        guard let data = Data(base64Encoded: text) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    func urlEncode(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? text
    }

    func urlDecode(_ text: String) -> String {
        text.removingPercentEncoding ?? text
    }

    func htmlEncode(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    func htmlDecode(_ text: String) -> String {
        guard let data = text.data(using: .utf8) else { return text }
        let opts: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]
        return (try? NSAttributedString(data: data, options: opts, documentAttributes: nil).string) ?? text
    }

    // MARK: - 压缩

    func gzip(_ text: String) -> String? {
        guard let inputData = text.data(using: .utf8) else { return nil }
        let compressed = compress(inputData, algorithm: .zlib)
        return compressed?.base64EncodedString()
    }

    func unGzip(_ base64: String) -> String? {
        guard let data = Data(base64Encoded: base64) else { return nil }
        guard let decompressed = decompress(data, algorithm: .zlib) else { return nil }
        return String(data: decompressed, encoding: .utf8)
    }

    func zlib(_ text: String) -> String? { gzip(text) }
    func unZlib(_ base64: String) -> String? { unGzip(base64) }

    private func compress(_ data: Data, algorithm: NSData.CompressionAlgorithm) -> Data? {
        try? (data as NSData).compressed(using: algorithm) as Data
    }

    private func decompress(_ data: Data, algorithm: NSData.CompressionAlgorithm) -> Data? {
        try? (data as NSData).decompressed(using: algorithm) as Data
    }

    // MARK: - HTML 查询（书源 JS 常用）

    func queryTextContent(_ html: String, _ cssSelector: String) -> String? {
        try? SwiftSoup.parse(html).selectFirst(cssSelector)?.text()
    }

    func queryAllTextContent(_ html: String, _ cssSelector: String) -> String {
        let elements = (try? SwiftSoup.parse(html).select(cssSelector)) ?? Elements()
        return elements.array().compactMap { try? $0.text() }.joined(separator: "\n")
    }

    // MARK: - 阅读器状态

    func getLastChapter() -> String? {
        currentContext?.variables["lastChapterTitle"] as? String
    }

    func getBook() -> String? {
        guard let ctx = currentContext,
              let data = try? JSONEncoder().encode(ctx.source),
              let json = String(data: data, encoding: .utf8)
        else { return nil }
        return json
    }

    // MARK: - 时间/系统

    func getNetworkTime() -> String {
        String(Int64(Date().timeIntervalSince1970 * 1000))
    }

    func timeFormat(_ timestamp: String) -> String {
        guard let ms = Double(timestamp) else { return timestamp }
        let date = Date(timeIntervalSince1970: ms / 1000)
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH:mm"
        return fmt.string(from: date)
    }

    func log(_ message: Any) {
        print("📖 [JS Log]: \(message)")
    }
}
