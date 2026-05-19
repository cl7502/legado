import Foundation

/// 编码助手
/// 目标：解决中文网页常见的 GBK/GB2312 乱码问题
class EncodingHelper {
    static let shared = EncodingHelper()
    
    /// 尝试将 Data 转换为字符串，支持自动识别 GBK
    func decode(_ data: Data, suggestedEncoding: String.Encoding? = nil) -> String? {
        // 1. 如果指定了编码，优先使用
        if let encoding = suggestedEncoding, let result = String(data: data, encoding: encoding) {
            return result
        }
        
        // 2. 尝试 UTF-8
        if let utf8String = String(data: data, encoding: .utf8) {
            return utf8String
        }
        
        // 3. 尝试 GBK (GB_18030_2000 是目前最全的中文编码)
        let gbkEncoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        if let gbkString = String(data: data, encoding: gbkEncoding) {
            return gbkString
        }
        
        // 4. 备选方案：尝试从 HTML Meta 标签中检测编码（后续在 HTMLParser 中增强）
        
        return nil
    }
}
