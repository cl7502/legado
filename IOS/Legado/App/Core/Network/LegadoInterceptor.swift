import Foundation
import Alamofire

/// Legado 网络拦截器
/// 目标：处理 Cookie 自动持久化与基础 Header 注入
final class LegadoInterceptor: RequestInterceptor {
    
    /// 在请求发送前修改请求
    func adapt(_ urlRequest: URLRequest, for session: Session, completion: @escaping (Result<URLRequest, Error>) -> Void) {
        var urlRequest = urlRequest
        
        // 1. 自动注入持久化的 Cookie
        if let urlString = urlRequest.url?.absoluteString,
           let cookie = CookieManager.shared.getCookie(for: urlString) {
            urlRequest.setValue(cookie, forHTTPHeaderField: "Cookie")
        }
        
        // 2. 注入默认 User-Agent (模拟手机浏览器)
        urlRequest.setValue("Mozilla/5.0 (Linux; Android 10; SM-G973F) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/83.0.4103.106 Mobile Safari/537.36", forHTTPHeaderField: "User-Agent")
        
        completion(.success(urlRequest))
    }
    
    /// 处理请求完成后的响应 (用于保存 Cookie)
    func processResponse(_ response: DataResponse<Data, AFError>) {
        guard let url = response.request?.url?.absoluteString,
              let headerFields = response.response?.allHeaderFields as? [String: String] else { return }
        
        // 提取 Set-Cookie 并保存
        let cookies = HTTPCookie.cookies(withResponseHeaderFields: headerFields, for: response.response!.url!)
        if !cookies.isEmpty {
            let cookieString = cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
            CookieManager.shared.saveCookie(for: url, cookieString: cookieString)
        }
    }
}
