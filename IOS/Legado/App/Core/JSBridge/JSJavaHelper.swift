import Foundation
import JavaScriptCore
import CryptoKit
import SwiftSoup
import CommonCrypto

/// JS-to-Swift bridge — mirrors Android JsExtensions interface.
/// Exposed as `java` in the JS context.
@objc protocol JSJavaHelperProtocol: JSExport {
    // Network — url may be "http://...,{options}" (same as AnalyzeUrl option format)
    func ajax(_ url: String) -> String?
    func ajaxAll(_ urlArray: JSValue) -> JSValue?
    func post(_ url: String, _ body: String) -> String?
    func connect(_ urlStr: String) -> String?
    func connectWithoutCookie(_ urlStr: String) -> String?

    // Variables — put() returns the value so it can be used inline in JS:
    //   java.ajax(url + ',' + java.put("headers", JSON.stringify({...})))
    func put(_ key: String, _ value: Any) -> Any
    func get(_ key: String) -> Any?
    func get(_ key: String, _ defaultValue: JSValue) -> Any?

    // Cross-evaluation object cache (mirrors Android JsExtensions.getFromCacheObject)
    func getFromCacheObject(_ key: String) -> Any?
    func setToCacheObject(_ key: String, _ value: Any)
    func clearCacheObjects()

    // Encoding
    func md5(_ text: String) -> String
    func md5Encode(_ text: String) -> String    // Android 标准名，等同于 md5()
    func md5Encode16(_ text: String) -> String
    func sha1(_ text: String) -> String
    func sha256(_ text: String) -> String
    func sha512(_ text: String) -> String
    func base64Encode(_ text: String) -> String
    func base64Decode(_ text: String) -> String
    func urlEncode(_ text: String) -> String
    func urlDecode(_ text: String) -> String
    func encodeURI(_ text: String, _ charset: String) -> String
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
    // Android alias: aesBase64DecodeToString(data, key, mode, iv) — note mode/iv order differs
    func aesBase64DecodeToString(_ data: String, _ key: String, _ mode: String, _ iv: String) -> String

    // Compression
    func gzip(_ text: String) -> String?
    func unGzip(_ base64: String) -> String?
    func zlib(_ text: String) -> String?
    func unZlib(_ base64: String) -> String?

    // HTML helpers
    func queryTextContent(_ html: String, _ cssSelector: String) -> String?
    func queryAllTextContent(_ html: String, _ cssSelector: String) -> String
    /// Android JsExtensions.getElements — CSS 选择当前 result 中的元素，返回 outerHTML 数组
    func getElements(_ cssSelector: String) -> JSValue?

    // Font decryption (ISSUE-016)
    func queryTTF(_ str: String) -> QueryTTFProxy?
    func replaceFont(_ text: String, _ errorTTF: JSValue, _ correctTTF: JSValue) -> String

    // Reader state
    func getLastChapter() -> String?
    func getBook() -> String?
    func getCookie(_ tag: String) -> String?
    func setCookie(_ tag: String, _ value: String)
    func removeCookie(_ tag: String)
    func clearCookies()

    // Text / array helpers
    func toast(_ message: Any)
    func longToast(_ message: Any)
    func getString(_ strArray: JSValue) -> String
    func getStringArray(_ str: String) -> JSValue?

    // Crypto
    func rsaEncrypt(_ data: String, _ key: String, _ transformation: String) -> String

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

    // MARK: - Global variable store (mirrors Android BookSourceHelp.varMap)
    // java.put(key, value) writes here; java.get(key) reads here.
    // Keyed by sourceUrl so sources are isolated.
    // @put:{} in RuleExecutor also bridges here so explore-stored vars survive
    // across context resets (e.g., explore → book info → chapter content).
    static var globalVarStore: [String: [String: String]] = [:]
    private static let varStoreLock = NSLock()

    static func globalPut(_ key: String, value: String, sourceUrl: String) {
        varStoreLock.lock(); defer { varStoreLock.unlock() }
        globalVarStore[sourceUrl, default: [:]][key] = value
    }

    static func globalGet(_ key: String, sourceUrl: String) -> String? {
        varStoreLock.lock(); defer { varStoreLock.unlock() }
        return globalVarStore[sourceUrl]?[key]
    }

    // Android ajax()/connect() pass the URL string through AnalyzeUrl, so
    // "http://api.example.com/list,{\"headers\":{...}}" correctly attaches
    // request headers. We replicate that by parsing with AnalyzeUrl.parse().

    func ajax(_ url: String) -> String? {
        requestWithOptions(url)
    }

    func connect(_ urlStr: String) -> String? {
        requestWithOptions(urlStr)
    }

    // Android alias — same implementation on iOS
    func connectWithoutCookie(_ urlStr: String) -> String? {
        requestWithOptions(urlStr)
    }

    func post(_ url: String, _ body: String) -> String? {
        NetworkManager.shared.requestSync(url, method: "POST", body: body)
    }

    func ajaxAll(_ urlArray: JSValue) -> JSValue? {
        guard let urls = urlArray.toArray() as? [String] else { return nil }
        let results = urls.map { requestWithOptions($0) ?? "" }
        return JSValue(object: results, in: urlArray.context)
    }

    /// Parse URL option format ("url,{headers/method/body}") and make request.
    /// Mirrors Android AnalyzeUrl(urlStr, source=source).getStrResponse().body
    private func requestWithOptions(_ rawUrl: String) -> String? {
        let ctx = currentContext
        let parsed = AnalyzeUrl.parse(rawUrl, context: ctx)
        let reqUrl = parsed.url
        guard !reqUrl.isEmpty else { return nil }
        let headers: [String: String]? = parsed.headers.isEmpty ? nil : parsed.headers
        if parsed.method == "POST", let body = parsed.body {
            return NetworkManager.shared.requestSync(reqUrl, method: "POST", body: body, headers: headers)
        }
        return NetworkManager.shared.requestSync(reqUrl, headers: headers)
    }

    // MARK: - Variables

    // Returns value so JS can use put() inline:
    //   java.ajax(url + ',' + java.put("headers", JSON.stringify({...})))
    @discardableResult
    func put(_ key: String, _ value: Any) -> Any {
        let strVal = "\(value)"
        currentContext?.variables[key] = strVal
        // Also persist globally so cross-evaluation rules (book info, TOC, content) can read via java.get
        if let srcUrl = currentContext?.source.bookSourceUrl {
            JSJavaHelper.globalPut(key, value: strVal, sourceUrl: srcUrl)
        }
        return value
    }

    func get(_ key: String) -> Any? {
        // Reserved keys — always from local context
        if key == "bookName" { return currentContext?.variables["bookName"] }
        if key == "title"    { return currentContext?.variables["title"] }
        // Check local context first, fall back to global store
        if let local = currentContext?.variables[key] { return local }
        if let srcUrl = currentContext?.source.bookSourceUrl {
            return JSJavaHelper.globalGet(key, sourceUrl: srcUrl)
        }
        return nil
    }

    /// 两参数版 get(key, defaultValue)——Android 书源常用，第二个参数为默认值
    func get(_ key: String, _ defaultValue: JSValue) -> Any? {
        if key == "bookName" { return currentContext?.variables["bookName"] }
        if key == "title"    { return currentContext?.variables["title"] }
        if let local = currentContext?.variables[key] { return local }
        if let srcUrl = currentContext?.source.bookSourceUrl,
           let global = JSJavaHelper.globalGet(key, sourceUrl: srcUrl) { return global }
        return defaultValue.isUndefined || defaultValue.isNull ? nil : defaultValue
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

    func md5Encode(_ text: String) -> String { md5(text) }

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

    /// java.encodeURI(str, charset) — Android 书源常用，用指定编码对搜索关键词做 URL 编码
    /// iOS 只支持 UTF-8，GBK/GB2312 等字节流编码回退到 UTF-8 的 percent encoding
    func encodeURI(_ text: String, _ charset: String) -> String {
        let enc = charset.lowercased().replacingOccurrences(of: "-", with: "")
        if enc == "gbk" || enc == "gb2312" || enc == "gb18030" {
            // 尝试 GBK 编码后 percent-encode 每个字节
            if let data = text.data(using: .init(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))) {
                return data.map { String(format: "%%%02X", $0) }.joined()
            }
        }
        return text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? text
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
        (try? Entities.unescape(text)) ?? text
    }

    func hexDecodeToString(_ hex: String) -> String {
        var bytes: [UInt8] = []
        var i = hex.startIndex
        while i < hex.endIndex {
            let next = hex.index(i, offsetBy: 2, limitedBy: hex.endIndex) ?? hex.endIndex
            if let byte = UInt8(hex[i..<next], radix: 16) { bytes.append(byte) }
            i = next
        }
        return String(bytes: bytes, encoding: .utf8) ?? String(bytes: bytes, encoding: .isoLatin1) ?? ""
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
    // key/iv 支持三种格式：UTF-8 字符串、十六进制、Base64

    func aesEncrypt(_ data: String, _ key: String, _ iv: String, _ mode: String) -> String {
        guard let dataBytes = data.data(using: .utf8),
              let keyBytes = decodeKeyBytes(key) else { return "" }
        let ivBytes = decodeKeyBytes(iv) ?? Data(repeating: 0, count: kCCBlockSizeAES128)
        let opts = aesOptions(mode)
        return aesCrypt(CCOperation(kCCEncrypt), data: dataBytes, key: keyBytes, iv: ivBytes, opts: opts)?
            .base64EncodedString() ?? ""
    }

    func aesDecrypt(_ base64Data: String, _ key: String, _ iv: String, _ mode: String) -> String {
        var normalized = base64Data
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let rem = normalized.count % 4
        if rem > 0 { normalized += String(repeating: "=", count: 4 - rem) }
        guard let dataBytes = Data(base64Encoded: normalized),
              let keyBytes = decodeKeyBytes(key) else { return "" }
        let ivBytes = decodeKeyBytes(iv) ?? Data(repeating: 0, count: kCCBlockSizeAES128)
        let opts = aesOptions(mode)
        return aesCrypt(CCOperation(kCCDecrypt), data: dataBytes, key: keyBytes, iv: ivBytes, opts: opts)
            .flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    // Android alias: parameter order is (data, key, mode, iv) — mode and iv are swapped
    func aesBase64DecodeToString(_ data: String, _ key: String, _ mode: String, _ iv: String) -> String {
        aesDecrypt(data, key, iv, mode)
    }

    /// key/iv 解码：自动识别十六进制（纯十六进制字符且长度为偶数）、Base64、UTF-8
    private func decodeKeyBytes(_ s: String) -> Data? {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        // 十六进制：全为 0-9a-fA-F 且长度为偶数（16/24/32/48/64字节对应的十六进制）
        let hexLengths: Set<Int> = [32, 48, 64]
        if hexLengths.contains(trimmed.count),
           trimmed.allSatisfy({ $0.isHexDigit }) {
            var bytes: [UInt8] = []
            var i = trimmed.startIndex
            while i < trimmed.endIndex {
                let next = trimmed.index(i, offsetBy: 2, limitedBy: trimmed.endIndex) ?? trimmed.endIndex
                if let byte = UInt8(trimmed[i..<next], radix: 16) { bytes.append(byte) }
                i = next
            }
            if bytes.count == 16 || bytes.count == 24 || bytes.count == 32 { return Data(bytes) }
        }
        // Base64：尝试解码并校验长度
        var b64 = trimmed
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let rem = b64.count % 4
        if rem > 0 { b64 += String(repeating: "=", count: 4 - rem) }
        if let data = Data(base64Encoded: b64),
           data.count == 16 || data.count == 24 || data.count == 32 { return data }
        // 兜底：UTF-8
        return trimmed.data(using: .utf8)
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

    func getElements(_ cssSelector: String) -> JSValue? {
        guard let jsCtx = JSContext.current() else { return nil }
        let html: String
        if let s = currentContext?.result as? String { html = s }
        else { return JSValue(undefinedIn: jsCtx) }
        // 返回 [ElementWrapper]，JSCore 自动桥接为 JS 数组，每个元素支持 .select()/.attr()/.text()
        let wrappers = HTMLParser.shared.cssList(html, query: cssSelector)
            .map { ElementWrapper($0) }
        return JSValue(object: wrappers, in: jsCtx)
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
            // Skip control chars, space, and non-BMP scalars — mirrors Android isBlankUnicode check
            let v = scalar.value
            guard v > 0x20 && v <= 0xFFFF else { return String(scalar) }
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
              let book = ctx.book,
              let data = try? JSONEncoder().encode(book),
              let json = String(data: data, encoding: .utf8)
        else { return nil }
        return json
    }

    func getCookie(_ tag: String) -> String? {
        // Tag 直接查找（setCookie 存储方式）；失败后再走 URL host 解析
        if let v = CookieManager.shared.getCookie(forTag: tag) { return v }
        return CookieManager.shared.getCookie(for: tag)
    }

    func setCookie(_ tag: String, _ value: String) {
        CookieManager.shared.saveCookie(forTag: tag, value: value)
    }

    func removeCookie(_ tag: String) {
        CookieManager.shared.removeCookie(forTag: tag)
    }

    func clearCookies() {
        CookieManager.shared.clearAll()
    }

    func toast(_ message: Any) {
        print("📖 [JS Toast]: \(message)")
    }

    func longToast(_ message: Any) {
        print("📖 [JS Toast]: \(message)")
    }

    func getString(_ strArray: JSValue) -> String {
        guard let arr = strArray.toArray() else { return "" }
        let strs = arr.compactMap { $0 as? String }
        return strs.isEmpty ? "" : strs[Int.random(in: 0..<strs.count)]
    }

    func getStringArray(_ str: String) -> JSValue? {
        guard let jsCtx = JSContext.current() else { return nil }
        let arr = str.components(separatedBy: ",")
                     .map { $0.trimmingCharacters(in: .whitespaces) }
        return JSValue(object: arr, in: jsCtx)
    }

    func rsaEncrypt(_ data: String, _ key: String, _ transformation: String) -> String {
        let upper = transformation.uppercased()
        let useOAEP = upper.contains("OAEP")
        let padding: SecKeyAlgorithm = useOAEP
            ? .rsaEncryptionOAEPSHA1
            : .rsaEncryptionPKCS1

        // key 可能是 Base64 DER 或 PEM；剥离 PEM 头尾后解码
        var b64 = key
            .replacingOccurrences(of: "-----BEGIN PUBLIC KEY-----", with: "")
            .replacingOccurrences(of: "-----END PUBLIC KEY-----", with: "")
            .replacingOccurrences(of: "-----BEGIN RSA PUBLIC KEY-----", with: "")
            .replacingOccurrences(of: "-----END RSA PUBLIC KEY-----", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: " ", with: "")
        let rem = b64.count % 4
        if rem > 0 { b64 += String(repeating: "=", count: 4 - rem) }
        guard let keyData = Data(base64Encoded: b64) else { return "" }

        let attrs: [String: Any] = [
            kSecAttrKeyType as String:       kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String:      kSecAttrKeyClassPublic,
        ]
        var error: Unmanaged<CFError>?
        guard let secKey = SecKeyCreateWithData(keyData as CFData, attrs as CFDictionary, &error),
              let plainData = data.data(using: .utf8),
              let encData = SecKeyCreateEncryptedData(secKey, padding, plainData as CFData, &error)
        else { return "" }
        return (encData as Data).base64EncodedString()
    }

    // MARK: - Time / system

    func getNetworkTime() -> String {
        String(Int64(Date().timeIntervalSince1970 * 1000))
    }

    func timeFormat(_ timestamp: String) -> String {
        guard let ts = Double(timestamp) else { return timestamp }
        // > 1e10 视为毫秒级（当前秒级时间戳约 1.7e9），否则视为秒级
        let seconds = ts > 1e10 ? ts / 1000 : ts
        let date = Date(timeIntervalSince1970: seconds)
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH:mm"
        return fmt.string(from: date)
    }

    func timeFormatUTC(_ time: String, _ format: String, _ sh: Int) -> String {
        guard let ts = Double(time) else { return time }
        let seconds = ts > 1e10 ? ts / 1000 : ts
        let date = Date(timeIntervalSince1970: seconds)
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

// MARK: - ElementWrapper — DOM-like element wrapper for java.getElements()

/// Android JsExtensions 返回的元素对象，支持 .select() / .attr() / .text() 链式调用。
/// 例：lis[i].select('a').attr('href')
@objc protocol ElementWrapperProtocol: JSExport {
    /// 在当前元素内查找第一个匹配的子元素，返回 ElementWrapper
    func select(_ css: String) -> ElementWrapper?
    /// 获取当前元素的属性值
    func attr(_ name: String) -> String
    /// 获取当前元素的纯文本内容
    func text() -> String
    /// 获取当前元素的 inner HTML
    func html() -> String
}

@objc final class ElementWrapper: NSObject, ElementWrapperProtocol {
    let outerHtml: String

    init(_ outerHtml: String) {
        self.outerHtml = outerHtml
    }

    func select(_ css: String) -> ElementWrapper? {
        // HTMLParser.cssList 返回 outerHTML 数组，取第一个
        let results = HTMLParser.shared.cssList(outerHtml, query: css)
        return results.first.map { ElementWrapper($0) }
    }

    func attr(_ name: String) -> String {
        guard let doc = try? SwiftSoup.parse(outerHtml),
              let el = doc.body()?.children().first() else { return "" }
        return (try? el.attr(name)) ?? ""
    }

    func text() -> String {
        guard let doc = try? SwiftSoup.parse(outerHtml),
              let el = doc.body()?.children().first() else { return "" }
        return (try? el.text()) ?? ""
    }

    func html() -> String {
        guard let doc = try? SwiftSoup.parse(outerHtml),
              let el = doc.body()?.children().first() else { return "" }
        return (try? el.html()) ?? ""
    }
}
