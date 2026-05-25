import Foundation
import JavaScriptCore
import CryptoKit
import SwiftSoup
import CommonCrypto

/// JS-to-Swift bridge — mirrors Android JsExtensions interface.
/// Exposed as `java` in the JS context.
@objc protocol JSJavaHelperProtocol: JSExport {
    // Network
    func ajax(_ url: String) -> String?
    func ajaxAll(_ urlArray: JSValue) -> JSValue?
    func post(_ url: String, _ body: String) -> String?
    func connect(_ urlStr: String) -> String?

    // Variables
    func put(_ key: String, _ value: Any)
    func get(_ key: String) -> Any?

    // Encoding
    func md5(_ text: String) -> String
    func sha1(_ text: String) -> String
    func base64Encode(_ text: String) -> String
    func base64Decode(_ text: String) -> String
    func urlEncode(_ text: String) -> String
    func urlDecode(_ text: String) -> String
    func htmlEncode(_ text: String) -> String
    func htmlDecode(_ text: String) -> String
    func hexDecodeToString(_ hex: String) -> String
    func hexEncodeToString(_ utf8: String) -> String

    // Compression
    func gzip(_ text: String) -> String?
    func unGzip(_ base64: String) -> String?
    func zlib(_ text: String) -> String?
    func unZlib(_ base64: String) -> String?

    // HTML helpers
    func queryTextContent(_ html: String, _ cssSelector: String) -> String?
    func queryAllTextContent(_ html: String, _ cssSelector: String) -> String

    // Reader state
    func getLastChapter() -> String?
    func getBook() -> String?
    func getCookie(_ tag: String) -> String?

    // Time / system
    func getNetworkTime() -> String
    func timeFormat(_ timestamp: String) -> String
    func timeFormatUTC(_ time: String, _ format: String, _ sh: Int) -> String
    func randomUUID() -> String

    // Text helpers
    func t2s(_ text: String) -> String
    func s2t(_ text: String) -> String

    // Logging
    func log(_ message: Any)
}

class JSJavaHelper: NSObject, JSJavaHelperProtocol {
    var currentContext: AnalyzeContext?

    // MARK: - Network

    func ajax(_ url: String) -> String? {
        NetworkManager.shared.requestSync(url)
    }

    func connect(_ urlStr: String) -> String? {
        NetworkManager.shared.requestSync(urlStr)
    }

    func post(_ url: String, _ body: String) -> String? {
        NetworkManager.shared.requestSync(url, method: "POST", body: body)
    }

    func ajaxAll(_ urlArray: JSValue) -> JSValue? {
        guard let urls = urlArray.toArray() as? [String] else { return nil }
        let results = urls.map { NetworkManager.shared.requestSync($0) ?? "" }
        return JSValue(object: results, in: urlArray.context)
    }

    // MARK: - Variables

    func put(_ key: String, _ value: Any) {
        currentContext?.variables[key] = value
    }

    func get(_ key: String) -> Any? {
        // Check reserved keys first (mirrors Android AnalyzeRule.get)
        if key == "bookName" { return currentContext?.variables["bookName"] }
        if key == "title"    { return currentContext?.variables["title"] }
        return currentContext?.variables[key]
    }

    // MARK: - Encoding / Crypto

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
        // Handle URL-safe Base64 and standard Base64
        var b64 = text.replacingOccurrences(of: "-", with: "+")
                      .replacingOccurrences(of: "_", with: "/")
        let rem = b64.count % 4
        if rem > 0 { b64 += String(repeating: "=", count: 4 - rem) }
        guard let data = Data(base64Encoded: b64) else { return "" }
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
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    func htmlDecode(_ text: String) -> String {
        // SwiftSoup can unescape HTML entities
        return (try? SwiftSoup.parse(text).text()) ?? text
            .replacingOccurrences(of: "&amp;",  with: "&")
            .replacingOccurrences(of: "&lt;",   with: "<")
            .replacingOccurrences(of: "&gt;",   with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;",  with: "'")
    }

    func hexDecodeToString(_ hex: String) -> String {
        var result = ""
        var i = hex.startIndex
        while i < hex.endIndex {
            let next = hex.index(i, offsetBy: 2, limitedBy: hex.endIndex) ?? hex.endIndex
            if let byte = UInt8(hex[i..<next], radix: 16) {
                result.append(Character(UnicodeScalar(byte)))
            }
            i = next
        }
        return result
    }

    func hexEncodeToString(_ utf8: String) -> String {
        utf8.utf8.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Compression

    func gzip(_ text: String) -> String? {
        guard let data = text.data(using: .utf8) else { return nil }
        return compress(data, algorithm: .zlib)?.base64EncodedString()
    }

    func unGzip(_ base64: String) -> String? {
        guard let data = Data(base64Encoded: base64),
              let dec = decompress(data, algorithm: .zlib) else { return nil }
        return String(data: dec, encoding: .utf8)
    }

    func zlib(_ text: String) -> String? { gzip(text) }
    func unZlib(_ base64: String) -> String? { unGzip(base64) }

    private func compress(_ data: Data, algorithm: NSData.CompressionAlgorithm) -> Data? {
        try? (data as NSData).compressed(using: algorithm) as Data
    }
    private func decompress(_ data: Data, algorithm: NSData.CompressionAlgorithm) -> Data? {
        try? (data as NSData).decompressed(using: algorithm) as Data
    }

    // MARK: - HTML helpers

    func queryTextContent(_ html: String, _ cssSelector: String) -> String? {
        try? SwiftSoup.parse(html).select(cssSelector).first()?.text()
    }

    func queryAllTextContent(_ html: String, _ cssSelector: String) -> String {
        let els = (try? SwiftSoup.parse(html).select(cssSelector)) ?? Elements()
        return els.array().compactMap { try? $0.text() }.joined(separator: "\n")
    }

    // MARK: - Reader state

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

    func getCookie(_ tag: String) -> String? {
        CookieManager.shared.getCookie(for: tag)
    }

    // MARK: - Time / system

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

    func timeFormatUTC(_ time: String, _ format: String, _ sh: Int) -> String {
        guard let ms = Double(time) else { return time }
        let date = Date(timeIntervalSince1970: ms / 1000)
        let fmt = DateFormatter()
        fmt.dateFormat = format.isEmpty ? "yyyy-MM-dd HH:mm:ss" : format
        fmt.timeZone = TimeZone(secondsFromGMT: sh * 3600)
        return fmt.string(from: date)
    }

    func randomUUID() -> String { UUID().uuidString }

    // MARK: - Chinese conversion (simplified ↔ traditional) — ISSUE-017
    // Uses iOS's built-in ICU transforms ("Traditional-Simplified" / "Simplified-Traditional").
    // These are available via Apple's ICU runtime (CFStringTransform) on iOS 9+.
    // Falls back to unchanged text if the transform is unavailable.
    func t2s(_ text: String) -> String {
        text.applyingTransform(StringTransform("Traditional-Simplified"), reverse: false) ?? text
    }
    func s2t(_ text: String) -> String {
        text.applyingTransform(StringTransform("Simplified-Traditional"), reverse: false) ?? text
    }

    // MARK: - Logging

    func log(_ message: Any) {
        print("📖 [JS]: \(message)")
    }
}
