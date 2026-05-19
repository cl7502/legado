import Foundation
import JavaScriptCore
import CryptoKit

/// Rhino API 兼容协议 (扩展版)
@objc protocol JSJavaHelperProtocol: JSExport {
    // --- 网络请求 ---
    func ajax(_ url: String) -> String?
    
    // --- 变量存储 ---
    func put(_ key: String, _ value: Any)
    func get(_ key: String) -> Any?
    
    // --- 字符串处理与编码 ---
    func base64Encode(_ text: String) -> String
    func base64Decode(_ text: String) -> String
    func md5(_ text: String) -> String
    
    /// URL 编码 (对标 java.urlEncode)
    func urlEncode(_ text: String) -> String
    /// URL 解码 (对标 java.urlDecode)
    func urlDecode(_ text: String) -> String
    /// HTML 转义 (对标 java.encodeHtml)
    func encodeHtml(_ text: String) -> String
    /// HTML 反转义 (对标 java.decodeHtml)
    func decodeHtml(_ text: String) -> String
    
    // --- 时间工具 ---
    /// 获取网络时间 (对标 java.getNetworkTime)
    func getNetworkTime() -> String
    
    // --- HTML 辅助解析 ---
    /// 获取元素文本 (对标 java.getString)
    func getString(_ html: String, _ rule: String) -> String
    
    // --- 交互与日志 ---
    func log(_ message: Any)
    func toast(_ message: Any)
}

/// Rhino API 兼容实现类 (扩展版)
class JSJavaHelper: NSObject, JSJavaHelperProtocol {
    
    var currentContext: AnalyzeContext?
    
    func ajax(_ url: String) -> String? {
        return NetworkManager.shared.requestSync(url)
    }
    
    func put(_ key: String, _ value: Any) {
        currentContext?.variables[key] = value
    }
    
    func get(_ key: String) -> Any? {
        return currentContext?.variables[key]
    }
    
    func base64Encode(_ text: String) -> String {
        return Data(text.utf8).base64EncodedString()
    }
    
    func base64Decode(_ text: String) -> String {
        guard let data = Data(base64Encoded: text) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
    
    func md5(_ text: String) -> String {
        let digest = Insecure.MD5.hash(data: Data(text.utf8))
        return digest.map { String(format: "%02hhx", $0) }.joined()
    }
    
    func urlEncode(_ text: String) -> String {
        return text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? text
    }
    
    func urlDecode(_ text: String) -> String {
        return text.removingPercentEncoding ?? text
    }
    
    func encodeHtml(_ text: String) -> String {
        // 基础 HTML 转义实现
        var result = text
        let mapping = ["&": "&amp;", "<": "&lt;", ">": "&gt;", "\"": "&quot;", "'": "&apos;"]
        for (key, value) in mapping {
            result = result.replacingOccurrences(of: key, with: value)
        }
        return result
    }
    
    func decodeHtml(_ text: String) -> String {
        // 使用内置的 NSAttributedString 进行复杂的 HTML 解构
        guard let data = text.data(using: .utf8) else { return text }
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]
        return (try? NSAttributedString(data: data, options: options, documentAttributes: nil).string) ?? text
    }
    
    func getNetworkTime() -> String {
        // 简单返回当前系统毫秒数 (Legado 常用作时间戳)
        return String(Int64(Date().timeIntervalSince1970 * 1000))
    }
    
    func getString(_ html: String, _ rule: String) -> String {
        // 调用 HTMLParser (阶段 4 会完善，此处先提供基础逻辑)
        // 简单模拟：如果 rule 是 CSS，尝试提取
        return "" // TODO: 整合 HTMLParser
    }
    
    func log(_ message: Any) {
        print("📖 [JS Log]: \(message)")
    }
    
    func toast(_ message: Any) {
        print("🔔 [JS Toast]: \(message)")
    }
}
