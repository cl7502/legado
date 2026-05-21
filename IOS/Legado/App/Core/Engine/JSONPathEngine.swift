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
            var key = part
            var arrayIndex: Int?
            
            // 处理索引语法 like list[0]
            if let indexRange = part.range(of: "\\[(\\d+)\\]", options: .regularExpression) {
                let indexStr = part[indexRange].replacingOccurrences(of: "[", with: "").replacingOccurrences(of: "]", with: "")
                arrayIndex = Int(indexStr)
                key = String(part[..<indexRange.lowerBound])
            }
            
            if let dict = current as? [String: Any] {
                current = dict[key]
                if let index = arrayIndex, let array = current as? [Any], index < array.count {
                    current = array[index]
                }
            } else if let array = current as? [Any], part.contains("[*]") {
                return array 
            } else {
                return nil
            }
        }
        
        return current
    }
}
