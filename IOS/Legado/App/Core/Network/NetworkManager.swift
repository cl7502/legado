import Foundation
import Alamofire

/// 增强型网络请求管理器 (V2.0 完美版)
class NetworkManager {
    static let shared = NetworkManager()
    
    private let session: Session
    private let interceptor = LegadoInterceptor()
    
    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        
        // 集成拦截器
        session = Session(configuration: configuration, interceptor: interceptor)
    }
    
    /// 执行请求，支持书源动态配置
    /// - Parameters:
    ///   - url: 请求地址
    ///   - method: 方法
    ///   - source: 书源对象（用于提取 Header 和执行动态脚本）
    ///   - context: 解析上下文
    func request(
        _ url: String,
        method: HTTPMethod = .get,
        source: BookSource? = nil,
        context: inout AnalyzeContext?
    ) async throws -> String {
        
        var headers = HTTPHeaders()
        
        // 1. 注入书源定义的静态 Header
        if let sourceHeaders = source?.headerDictionary {
            for (key, value) in sourceHeaders {
                headers.add(name: key, value: value)
            }
        }
        
        // 2. TODO: 动态 Header 脚本执行 (在阶段 3 完善后调用 JSEngine)
        
        let request = session.request(url, method: method, headers: headers)
        
        // 3. 处理响应并自动转码 (处理 GBK)
        let response = await request.serializingData().response
        
        // 手动保存 Cookie (由于 Alamofire 拦截器不直接暴露 processResponse)
        interceptor.processResponse(response)
        
        switch response.result {
        case .success(let data):
            // 使用 EncodingHelper 进行智能解码 (完美解决 GBK 乱码)
            if let decodedString = EncodingHelper.shared.decode(data) {
                return decodedString
            }
            return String(data: data, encoding: .utf8) ?? ""
        case .failure(let error):
            throw error
        }
    }
    
    /// 同步请求方法 (专为 JS 脚本设计)
    func requestSync(_ url: String, method: String = "GET") -> String? {
        let semaphore = DispatchSemaphore(value: 0)
        var result: String?
        
        let headers: HTTPHeaders = [
            "User-Agent": "Mozilla/5.0 (Legado; iOS)"
        ]
        
        session.request(url, method: HTTPMethod(rawValue: method.uppercased()), headers: headers)
            .responseData { response in
                if let data = response.data {
                    result = EncodingHelper.shared.decode(data)
                }
                semaphore.signal()
            }
        
        _ = semaphore.wait(timeout: .now() + 30)
        return result
    }
}
