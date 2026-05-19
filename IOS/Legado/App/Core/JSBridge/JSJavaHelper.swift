import Foundation
import JavaScriptCore
import CryptoKit

/// Rhino API 兼容协议
/// 目标：在 JS 环境中模拟 Android 的 java 对象
@objc protocol JSJavaHelperProtocol: JSExport {
    // --- 网络请求 ---
    /// 同步 Ajax 请求 (对标 java.ajax)
    func ajax(_ url: String) -> String?
    
    // --- 变量存储 ---
    /// 存储变量 (对标 java.put)
    func put(_ key: String, _ value: Any)
    /// 获取变量 (对标 java.get)
    func get(_ key: String) -> Any?
    
    // --- 字符串处理与编码 ---
    /// Base64 编码
    func base64Encode(_ text: String) -> String
    /// Base64 解码
    func base64Decode(_ text: String) -> String
    /// MD5 加密
    func md5(_ text: String) -> String
    
    // --- 交互与日志 ---
    /// 日志输出
    func log(_ message: Any)
    /// 弹窗提示
    func toast(_ message: Any)
}

/// Rhino API 兼容实现类
class JSJavaHelper: NSObject, JSJavaHelperProtocol {
    
    // 注入当前解析上下文，用于变量持久化
    var currentContext: AnalyzeContext?
    
    func ajax(_ url: String) -> String? {
        // 调用我们之前在 NetworkManager 中准备好的同步请求方法
        return NetworkManager.shared.requestSync(url)
    }
    
    func put(_ key: String, _ value: Any) {
        // 存储到上下文的变量池中
        currentContext?.variables[key] = value
    }
    
    func get(_ key: String) -> Any? {
        // 从上下文获取
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
    
    func log(_ message: Any) {
        print("📖 [JS Log]: \(message)")
    }
    
    func toast(_ message: Any) {
        print("🔔 [JS Toast]: \(message)")
    }
}
