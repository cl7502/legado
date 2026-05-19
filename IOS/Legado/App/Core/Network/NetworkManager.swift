import Foundation
import Alamofire

/// 增强型网络请求管理器 (V3.0 专业版)
class NetworkManager {
    static let shared = NetworkManager()
    
    private let session: Session
    private let interceptor = LegadoInterceptor()
    
    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        session = Session(configuration: configuration, interceptor: interceptor)
    }
    
    /// 执行请求 (支持 GET/POST)
    func request(
        _ url: String,
        method: HTTPMethod = .get,
        parameters: [String: Any]? = nil,
        headers: HTTPHeaders? = nil,
        source: BookSource? = nil
    ) async throws -> String {
        
        var finalHeaders = headers ?? HTTPHeaders()
        if let sourceHeaders = source?.headerDictionary {
            for (key, value) in sourceHeaders {
                finalHeaders.add(name: key, value: value)
            }
        }
        
        let encoding: ParameterEncoding = method == .get ? URLEncoding.default : JSONEncoding.default
        
        let request = session.request(url, method: method, parameters: parameters, encoding: encoding, headers: finalHeaders)
        let response = await request.serializingData().response
        
        interceptor.processResponse(response)
        
        switch response.result {
        case .success(let data):
            return EncodingHelper.shared.decode(data) ?? String(data: data, encoding: .utf8) ?? ""
        case .failure(let error):
            throw error
        }
    }
    
    /// 同步请求 (支持 POST)
    func requestSync(_ url: String, method: String = "GET", body: String? = nil, headers: [String: String]? = nil) -> String? {
        let semaphore = DispatchSemaphore(value: 0)
        var result: String?
        
        var finalHeaders = HTTPHeaders()
        headers?.forEach { finalHeaders.add(name: $0.key, value: $0.value) }
        
        let httpMethod = HTTPMethod(rawValue: method.uppercased())
        let parameters = body?.data(using: .utf8).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        
        session.request(url, method: httpMethod, parameters: parameters, encoding: httpMethod == .get ? URLEncoding.default : JSONEncoding.default, headers: finalHeaders)
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
