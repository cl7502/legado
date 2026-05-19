import Foundation

/// 简易 JSONPath 解析引擎
/// 目标：支持 $.data.list[*] 这种 Legado 常用语法
class JSONPathEngine {
    static let shared = JSONPathEngine()
    
    /// 解析 JSON 字符串并执行路径查询
    func extract(json: String, path: String) -> Any? {
        guard let data = json.data(using: .utf8),
              let jsonObject = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }
        
        // 如果路径是 $，直接返回整个对象
        if path == "$" || path == "$." {
            return jsonObject
        }
        
        // 简易路径解析：按点号分割
        let parts = path.replacingOccurrences(of: "$.", with: "").components(separatedBy: ".")
        var current: Any? = jsonObject
        
        for part in parts {
            if let dict = current as? [String: Any] {
                current = dict[part]
            } else if let array = current as? [[String: Any]], part.contains("[*]") {
                // 简单处理数组全选
                return array // 返回整个数组，供后续循环处理
            } else {
                return nil
            }
        }
        
        return current
    }
}
