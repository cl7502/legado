import Foundation
import Alamofire

/// Network request manager — mirrors Android OkHttp + AnalyzeUrl.getStrResponseAwait()
class NetworkManager {
    static let shared = NetworkManager()

    private let session: Session
    private let interceptor = LegadoInterceptor()

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        session = Session(configuration: config, interceptor: interceptor)
    }

    // MARK: - Async API

    /// GET request — returns decoded string body.
    func request(
        _ url: String,
        method: HTTPMethod = .get,
        parameters: [String: Any]? = nil,
        headers: HTTPHeaders? = nil,
        source: BookSource? = nil
    ) async throws -> String {
        let finalHeaders = mergeHeaders(base: source?.headerDictionary, extra: headers)
        let encoding: ParameterEncoding = method == .get ? URLEncoding.default : JSONEncoding.default
        let req = session.request(url, method: method, parameters: parameters,
                                  encoding: encoding, headers: finalHeaders)
        let response = await req.serializingData().response
        interceptor.processResponse(response)
        return try decodeResponse(response)
    }

    /// POST with raw string body (JSON or form).
    func requestPost(
        _ url: String,
        body: String,
        source: BookSource? = nil,
        headers: HTTPHeaders? = nil
    ) async throws -> String {
        var finalHeaders = mergeHeaders(base: source?.headerDictionary, extra: headers)

        // Detect content type from body or existing headers
        let contentType = finalHeaders.value(for: "Content-Type")
        let bodyData: Data

        if body.hasPrefix("{") || body.hasPrefix("[") {
            // JSON body
            if contentType == nil { finalHeaders.add(name: "Content-Type", value: "application/json") }
            bodyData = body.data(using: .utf8) ?? Data()
        } else {
            // Form-encoded body
            if contentType == nil { finalHeaders.add(name: "Content-Type", value: "application/x-www-form-urlencoded") }
            bodyData = body.data(using: .utf8) ?? Data()
        }

        var urlReq = try URLRequest(url: url, method: .post)
        urlReq.headers = finalHeaders
        urlReq.httpBody = bodyData

        let req = session.request(urlReq)
        let response = await req.serializingData().response
        interceptor.processResponse(response)
        return try decodeResponse(response)
    }

    // MARK: - Sync API (for JS bridge — runs on a background thread via semaphore)

    func requestSync(_ url: String, method: String = "GET", body: String? = nil,
                     headers: [String: String]? = nil) -> String? {
        let semaphore = DispatchSemaphore(value: 0)
        var result: String?

        var finalHeaders = HTTPHeaders()
        headers?.forEach { finalHeaders.add(name: $0.key, value: $0.value) }

        let httpMethod = HTTPMethod(rawValue: method.uppercased())

        if let body = body, httpMethod != .get {
            // POST with body
            var urlReq = try? URLRequest(url: url, method: httpMethod)
            urlReq?.headers = finalHeaders
            urlReq?.httpBody = body.data(using: .utf8)
            guard let req = urlReq else { return nil }
            session.request(req).responseData { resp in
                result = resp.data.flatMap { EncodingHelper.shared.decode($0) }
                semaphore.signal()
            }
        } else {
            session.request(url, method: httpMethod, headers: finalHeaders)
                .responseData { resp in
                    result = resp.data.flatMap { EncodingHelper.shared.decode($0) }
                    semaphore.signal()
                }
        }

        _ = semaphore.wait(timeout: .now() + 30)
        return result
    }

    // MARK: - Helpers

    private func mergeHeaders(base: [String: String]?, extra: HTTPHeaders?) -> HTTPHeaders {
        var headers = HTTPHeaders()
        base?.forEach { headers.add(name: $0.key, value: $0.value) }
        extra?.forEach { headers.add(name: $0.name, value: $0.value) }
        return headers
    }

    private func decodeResponse(_ response: DataResponse<Data, AFError>) throws -> String {
        interceptor.processResponse(response)
        switch response.result {
        case .success(let data):
            return EncodingHelper.shared.decode(data) ?? String(data: data, encoding: .utf8) ?? ""
        case .failure(let error):
            throw error
        }
    }
}
