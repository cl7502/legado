import Foundation
import JavaScriptCore
import CryptoKit

/// Rhino API 兼容协议 (终极版)
@objc protocol JSJavaHelperProtocol: JSExport {
    // --- 网络请求 (全参数版) ---
    func ajax(_ url: String) -> String?
    func post(_ url: String, _ body: String) -> String?
    
    // --- 变量存储 ---
    func put(_ key: String, _ value: Any)
    func get(_ key: String) -> Any?
    
    // --- 算法库 (全面对标 java.util) ---
    func md5(_ text: String) -> String
    func sha1(_ text: String) -> String
    func base64Encode(_ text: String) -> String
    func base64Decode(_ text: String) -> String
    
    // --- 编码工具 ---
    func urlEncode(_ text: String) -> String
    func urlDecode(_ text: String) -> String
    func htmlEncode(_ text: String) -> String
    func htmlDecode(_ text: String) -> String
    
    // --- 系统工具 ---
    func getNetworkTime() -> String
    func log(_ message: Any)
}

/// Rhino API 兼容实现类 (终极版)
class JSJavaHelper: NSObject, JSJavaHelperProtocol {
    
    var currentContext: AnalyzeContext?
    
    func ajax(_ url: String) -> String? {
        return NetworkManager.shared.requestSync(url)
    }
    
    func post(_ url: String, _ body: String) -> String? {
        return NetworkManager.shared.requestSync(url, method: "POST", body: body)
    }
    
    func put(_ key: String, _ value: Any) {
        currentContext?.variables[key] = value
    }
    
    func get(_ key: String) -> Any? {
        return currentContext?.variables[key]
    }
    
    func md5(_ text: String) -> String {
        let digest = Insecure.MD5.hash(data: Data(text.utf8))
        return digest.map { String(format: "%02hhx", $0) }.joined()
    }
    
    func sha1(_ text: String) -> String {
        let digest = Insecure.SHA1.hash(data: Data(text.utf8))
        return digest.map { String(format: "%02hhx", $0) }.joined()
    }
    
    func base64Encode(_ text: String) -> String {
        return Data(text.utf8).base64EncodedString()
    }
    
    func base64Decode(_ text: String) -> String {
        guard let data = Data(base64Encoded: text) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
    
    func urlEncode(_ text: String) -> String {
        return text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? text
    }
    
    func urlDecode(_ text: String) -> String {
        return text.removingPercentEncoding ?? text
    }
    
    func htmlEncode(_ text: String) -> String {
        var result = text
        let mapping = ["&": "&amp;", "<": "&lt;", ">": "&gt;", "\"": "&quot;", "'": "&apos;"]
        for (key, value) in mapping {
            result = result.replacingOccurrences(of: key, with: value)
        }
        return result
    }
    
    func htmlDecode(_ text: String) -> String {
        guard let data = text.data(using: .utf8) else { return text }
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]
        return (try? NSAttributedString(data: data, options: options, documentAttributes: nil).string) ?? text
    }
    
    func getNetworkTime() -> String {
        return String(Int64(Date().timeIntervalSince1970 * 1000))
    }
    
    func log(_ message: Any) {
        print("📖 [JS Log]: \(message)")
    }
}
