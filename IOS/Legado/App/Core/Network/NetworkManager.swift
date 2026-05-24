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
        source: BookSource? = nil,
        context: inout AnalyzeContext? = nil
    ) async throws -> String {
        
        var finalHeaders = headers ?? HTTPHeaders()
        
        // 1. 注入书源定义的静态 Header
        if let sourceHeaders = source?.headerDictionary {
            for (key, value) in sourceHeaders {
                finalHeaders.add(name: key, value: value)
            }
        }
        
        // 2. 动态 Header 脚本执行
        if let source = source, let loginCheckJs = source.loginCheckJs, var ctx = context {
            if let dynamicHeaderJson = LegadoJSEngine.shared.evaluateRule(loginCheckJs, in: &ctx) {
                if let data = dynamicHeaderJson.data(using: .utf8),
                   let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
                    dict.forEach { finalHeaders.add(name: $0.key, value: $0.value) }
                }
            }
            context = ctx // 写回上下文
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
    
    /// POST 请求（body 为 JSON 字符串或表单字符串）
    func requestPost(
        _ url: String,
        body: String,
        source: BookSource? = nil,
        headers: HTTPHeaders? = nil
    ) async throws -> String {
        var finalHeaders = headers ?? HTTPHeaders()
        if let sourceHeaders = source?.headerDictionary {
            sourceHeaders.forEach { finalHeaders.add(name: $0.key, value: $0.value) }
        }

        // 尝试解析为 JSON，否则按表单发送
        var parameters: [String: Any]?
        var encoding: ParameterEncoding = URLEncoding.httpBody
        if let data = body.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            parameters = json
            encoding = JSONEncoding.default
        } else {
            // 表单格式 key=val&key2=val2
            parameters = body.components(separatedBy: "&").reduce(into: [:]) { dict, pair in
                let kv = pair.components(separatedBy: "=")
                if kv.count == 2 { dict[kv[0]] = kv[1].removingPercentEncoding ?? kv[1] }
            }
        }

        let request = session.request(url, method: .post, parameters: parameters,
                                      encoding: encoding, headers: finalHeaders)
        let response = await request.serializingData().response
        interceptor.processResponse(response)

        switch response.result {
        case .success(let data):
            return EncodingHelper.shared.decode(data) ?? String(data: data, encoding: .utf8) ?? ""
        case .failure(let error):
            throw error
        }
    }
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
