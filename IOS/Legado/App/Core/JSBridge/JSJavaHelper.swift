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
    func connectWithoutCookie(_ urlStr: String) -> String?

    // Variables
    func put(_ key: String, _ value: Any)
    func get(_ key: String) -> Any?

    // Cross-evaluation object cache (mirrors Android JsExtensions.getFromCacheObject)
    func getFromCacheObject(_ key: String) -> Any?
    func setToCacheObject(_ key: String, _ value: Any)
    func clearCacheObjects()

    // Encoding
    func md5(_ text: String) -> String
    func md5Encode16(_ text: String) -> String
    func sha1(_ text: String) -> String
    func sha256(_ text: String) -> String
    func sha512(_ text: String) -> String
    func base64Encode(_ text: String) -> String
    func base64Decode(_ text: String) -> String
    func urlEncode(_ text: String) -> String
    func urlDecode(_ text: String) -> String
    func htmlEncode(_ text: String) -> String
    func htmlDecode(_ text: String) -> String
    func hexDecodeToString(_ hex: String) -> String
    func hexEncodeToString(_ utf8: String) -> String

    // HMAC
    func hmacSha256(_ data: String, _ key: String) -> String
    func hmacSha1(_ data: String, _ key: String) -> String
    func hmacMd5(_ data: String, _ key: String) -> String

    // AES
    func aesEncrypt(_ data: String, _ key: String, _ iv: String, _ mode: String) -> String
    func aesDecrypt(_ base64Data: String, _ key: String, _ iv: String, _ mode: String) -> String

    // Compression
    func gzip(_ text: String) -> String?
    func unGzip(_ base64: String) -> String?
    func zlib(_ text: String) -> String?
    func unZlib(_ base64: String) -> String?

    // HTML helpers
    func queryTextContent(_ html: String, _ cssSelector: String) -> String?
    func queryAllTextContent(_ html: String, _ cssSelector: String) -> String

    // Font decryption (ISSUE-016)
    func queryTTF(_ str: String) -> QueryTTFProxy?
    func replaceFont(_ text: String, _ errorTTF: JSValue, _ correctTTF: JSValue) -> String

    // Reader state
    func getLastChapter() -> String?
    func getBook() -> String?
    func getCookie(_ tag: String) -> String?
    func setCookie(_ tag: String, _ value: String)

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

    // Cross-evaluation object cache — mirrors Android JsExtensions cacheMap.
    // Keyed by sourceUrl so different sources don't share cache entries.
    private var cacheObjects: [String: Any] = [:]

    // MARK: - Network

    func ajax(_ url: String) -> String? {
        NetworkManager.shared.requestSync(url)
    }

    func connect(_ urlStr: String) -> String? {
        NetworkManager.shared.requestSync(urlStr)
    }

    // Android alias — same as connect() on iOS (no separate cookie jar to bypass)
    func connectWithoutCookie(_ urlStr: String) -> String? {
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

    // MARK: - Cross-evaluation object cache (mirrors Android JsExtensions cacheMap)
    // Used by book sources to pass parsed HTML/JSON between rule evaluations within
    // one parsing session without re-fetching. javaHelper is a singleton so these
    // persist across evaluateRule calls for the lifetime of the app.

    func getFromCacheObject(_ key: String) -> Any? {
        let cacheKey = "\(currentContext?.source.bookSourceUrl ?? ""):\(key)"
        return cacheObjects[cacheKey]
    }

    func setToCacheObject(_ key: String, _ value: Any) {
        let cacheKey = "\(currentContext?.source.bookSourceUrl ?? ""):\(key)"
        cacheObjects[cacheKey] = value
    }

    func clearCacheObjects() {
        let prefix = currentContext?.source.bookSourceUrl ?? ""
        cacheObjects = cacheObjects.filter { !$0.key.hasPrefix("\(prefix):") }
    }

    // MARK: - Encoding / Crypto

    func md5(_ text: String) -> String {
        let digest = Insecure.MD5.hash(data: Data(text.utf8))
        return digest.map { String(format: "%02hhx", $0) }.joined()
    }

    func md5Encode16(_ text: String) -> String {
        let full = md5(text)
        let start = full.index(full.startIndex, offsetBy: 8)
        let end = full.index(full.startIndex, offsetBy: 24)
        return String(full[start..<end])
    }

    func sha1(_ text: String) -> String {
        let digest = Insecure.SHA1.hash(data: Data(text.utf8))
        return digest.map { String(format: "%02hhx", $0) }.joined()
    }

    func sha256(_ text: String) -> String {
        let digest = SHA256.hash(data: Data(text.utf8))
        return digest.map { String(format: "%02hhx", $0) }.joined()
    }

    func sha512(_ text: String) -> String {
        let digest = SHA512.hash(data: Data(text.utf8))
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

    // MARK: - HMAC (CommonCrypto)

    func hmacSha256(_ data: String, _ key: String) -> String {
        hmac(data: data, key: key, algorithm: CCHmacAlgorithm(kCCHmacAlgSHA256), digestLen: CC_SHA256_DIGEST_LENGTH)
    }

    func hmacSha1(_ data: String, _ key: String) -> String {
        hmac(data: data, key: key, algorithm: CCHmacAlgorithm(kCCHmacAlgSHA1), digestLen: CC_SHA1_DIGEST_LENGTH)
    }

    func hmacMd5(_ data: String, _ key: String) -> String {
        hmac(data: data, key: key, algorithm: CCHmacAlgorithm(kCCHmacAlgMD5), digestLen: CC_MD5_DIGEST_LENGTH)
    }

    private func hmac(data: String, key: String, algorithm: CCHmacAlgorithm, digestLen: Int32) -> String {
        let keyBytes = Array(key.utf8)
        let msgBytes = Array(data.utf8)
        var out = [UInt8](repeating: 0, count: Int(digestLen))
        CCHmac(algorithm, keyBytes, keyBytes.count, msgBytes, msgBytes.count, &out)
        return out.map { String(format: "%02hhx", $0) }.joined()
    }

    // MARK: - AES (CommonCrypto)
    // mode string: "CBC/PKCS5Padding", "ECB/PKCS5Padding", etc.

    func aesEncrypt(_ data: String, _ key: String, _ iv: String, _ mode: String) -> String {
        guard let dataBytes = data.data(using: .utf8),
              let keyBytes = key.data(using: .utf8) else { return "" }
        let ivBytes = iv.data(using: .utf8) ?? Data(repeating: 0, count: kCCBlockSizeAES128)
        let opts = aesOptions(mode)
        return aesCrypt(CCOperation(kCCEncrypt), data: dataBytes, key: keyBytes, iv: ivBytes, opts: opts)?
            .base64EncodedString() ?? ""
    }

    func aesDecrypt(_ base64Data: String, _ key: String, _ iv: String, _ mode: String) -> String {
        guard let dataBytes = Data(base64Encoded: base64Data),
              let keyBytes = key.data(using: .utf8) else { return "" }
        let ivBytes = iv.data(using: .utf8) ?? Data(repeating: 0, count: kCCBlockSizeAES128)
        let opts = aesOptions(mode)
        return aesCrypt(CCOperation(kCCDecrypt), data: dataBytes, key: keyBytes, iv: ivBytes, opts: opts)
            .flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    private func aesOptions(_ mode: String) -> CCOptions {
        let upper = mode.uppercased()
        let ecb = upper.contains("ECB") ? CCOptions(kCCOptionECBMode) : 0
        return CCOptions(kCCOptionPKCS7Padding) | ecb
    }

    private func aesCrypt(_ op: CCOperation, data: Data, key: Data, iv: Data, opts: CCOptions) -> Data? {
        let keyLen = key.count
        guard keyLen == 16 || keyLen == 24 || keyLen == 32 else { return nil }
        let bufSize = data.count + kCCBlockSizeAES128
        var out = Data(count: bufSize)
        var outLen = 0
        let status: CCCryptorStatus = key.withUnsafeBytes { kp in
            iv.withUnsafeBytes { ip in
                data.withUnsafeBytes { dp in
                    out.withUnsafeMutableBytes { op2 in
                        CCCrypt(op, CCAlgorithm(kCCAlgorithmAES), opts,
                                kp.baseAddress, keyLen,
                                ip.baseAddress,
                                dp.baseAddress, data.count,
                                op2.baseAddress, bufSize,
                                &outLen)
                    }
                }
            }
        }
        return status == kCCSuccess ? out.prefix(outLen) : nil
    }

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

    // MARK: - Font decryption (ISSUE-016)

    func queryTTF(_ str: String) -> QueryTTFProxy? {
        let data: Data?
        let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("http") {
            data = NetworkManager.shared.requestSyncData(trimmed)
        } else {
            // Try standard then URL-safe base64
            var b64 = trimmed.replacingOccurrences(of: "-", with: "+")
                              .replacingOccurrences(of: "_", with: "/")
            let rem = b64.count % 4
            if rem > 0 { b64 += String(repeating: "=", count: 4 - rem) }
            data = Data(base64Encoded: b64)
        }
        guard let fontData = data, !fontData.isEmpty else { return nil }
        return QueryTTFProxy(QueryTTF(data: fontData))
    }

    func replaceFont(_ text: String, _ errorTTF: JSValue, _ correctTTF: JSValue) -> String {
        guard let errProxy = errorTTF.toObject() as? QueryTTFProxy,
              let corProxy = correctTTF.toObject() as? QueryTTFProxy
        else { return text }
        return text.unicodeScalars.map { scalar -> String in
            let ch = Character(scalar)
            let glyph = errProxy.ttf.glyphId(for: ch)
            if glyph == 0 { return String(scalar) }
            return corProxy.ttf.char(forGlyphId: glyph).map { String($0) } ?? String(scalar)
        }.joined()
    }

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

    func setCookie(_ tag: String, _ value: String) {
        CookieManager.shared.saveCookie(forTag: tag, value: value)
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

// MARK: - QueryTTFProxy — JSExport wrapper for QueryTTF (ISSUE-016)

/// Opaque token passed between `queryTTF()` and `replaceFont()` in JS book sources.
/// Exposed as a JS object so JS code can write:  `java.replaceFont(text, java.queryTTF(url), ...)`.
@objc protocol QueryTTFProxyProtocol: JSExport {}

@objc final class QueryTTFProxy: NSObject, QueryTTFProxyProtocol {
    let ttf: QueryTTF
    init(_ ttf: QueryTTF) { self.ttf = ttf }
}
