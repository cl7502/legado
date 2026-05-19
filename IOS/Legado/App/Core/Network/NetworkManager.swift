import Foundation
import Alamofire

/// 增强型网络请求管理器
/// 目标：对标 OkHttp，支持同步/异步转换，支持 Cookie 拦截
class NetworkManager {
    static let shared = NetworkManager()
    
    let session: Session
    
    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        
        // TODO: 待实现 Cookie 拦截器与重试机制
        session = Session(configuration: configuration)
    }
    
    /// 异步请求方法
    func request(
        _ url: String,
        method: HTTPMethod = .get,
        headers: HTTPHeaders? = nil,
        parameters: Parameters? = nil
    ) async throws -> String {
        let request = session.request(url, method: method, parameters: parameters, headers: headers)
        let response = await request.serializingString().response
        
        switch response.result {
        case .success(let value):
            return value
        case .failure(let error):
            throw error
        }
    }
    
    /// 同步请求方法（专为 JS 引擎同步 ajax 调用设计）
    func requestSync(_ url: String, method: String = "GET") -> String? {
        let semaphore = DispatchSemaphore(value: 0)
        var result: String?
        
        AF.request(url, method: HTTPMethod(rawValue: method.uppercased())).responseString { response in
            if case .success(let value) = response.result {
                result = value
            }
            semaphore.signal()
        }
        
        _ = semaphore.wait(timeout: .now() + 30)
        return result
    }
}
