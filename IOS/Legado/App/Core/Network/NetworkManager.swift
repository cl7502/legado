import Foundation
import Alamofire

// MARK: - Domain Rate Limiter (ISSUE-009)

/// Per-domain concurrent rate limiter — mirrors Android ConcurrentRateLimiter.
/// `concurrentRate` format: "maxConcurrent,intervalMs" (e.g. "2,500" = 2 slots, 500ms gap).
actor DomainRateLimiter {
    static let shared = DomainRateLimiter()

    private struct DomainState {
        var inflight: Int = 0
        var lastReleaseDate: Date = .distantPast
    }
    private var states: [String: DomainState] = [:]

    func acquire(domain: String, maxConcurrent: Int, intervalMs: Int) async {
        while (states[domain]?.inflight ?? 0) >= maxConcurrent {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        if intervalMs > 0, let last = states[domain]?.lastReleaseDate {
            let remainMs = Double(intervalMs) - Date().timeIntervalSince(last) * 1000
            if remainMs > 0 { try? await Task.sleep(nanoseconds: UInt64(remainMs * 1_000_000)) }
        }
        var state = states[domain] ?? DomainState()
        state.inflight += 1
        states[domain] = state
    }

    func release(domain: String) {
        var state = states[domain] ?? DomainState()
        state.inflight = max(0, state.inflight - 1)
        state.lastReleaseDate = Date()
        states[domain] = state
    }

    static func parse(_ rate: String) -> (maxConcurrent: Int, intervalMs: Int) {
        let parts = rate.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        return (max(1, Int(parts[0]) ?? 1), parts.count > 1 ? max(0, Int(parts[1]) ?? 0) : 0)
    }
}

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
        let domain = URL(string: url)?.host ?? url
        if let rate = source?.concurrentRate, !rate.isEmpty {
            let (maxC, ms) = DomainRateLimiter.parse(rate)
            await DomainRateLimiter.shared.acquire(domain: domain, maxConcurrent: maxC, intervalMs: ms)
        }
        defer { if source?.concurrentRate != nil { Task { await DomainRateLimiter.shared.release(domain: domain) } } }

        let finalHeaders = mergeHeaders(base: source?.headerDictionary, extra: headers)
        let encoding: ParameterEncoding = method == .get ? URLEncoding.default : JSONEncoding.default
        let req = session.request(url, method: method, parameters: parameters,
                                  encoding: encoding, headers: finalHeaders)
        let response = await req.serializingData().response
        interceptor.processResponse(response)
        return try decodeResponse(response)
    }

    /// GET request — returns (body, finalUrl) so callers can detect redirects (ISSUE-020).
    func requestWithFinalUrl(
        _ url: String,
        headers: HTTPHeaders? = nil,
        source: BookSource? = nil
    ) async throws -> (body: String, finalUrl: String) {
        let domain = URL(string: url)?.host ?? url
        if let rate = source?.concurrentRate, !rate.isEmpty {
            let (maxC, ms) = DomainRateLimiter.parse(rate)
            await DomainRateLimiter.shared.acquire(domain: domain, maxConcurrent: maxC, intervalMs: ms)
        }
        defer { if source?.concurrentRate != nil { Task { await DomainRateLimiter.shared.release(domain: domain) } } }

        let finalHeaders = mergeHeaders(base: source?.headerDictionary, extra: headers)
        let req = session.request(url, method: .get, headers: finalHeaders)
        let response = await req.serializingData().response
        interceptor.processResponse(response)
        let body = try decodeResponse(response)
        let resolvedUrl = response.response?.url?.absoluteString ?? url
        return (body, resolvedUrl)
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

    // Background queue for sync response callbacks — prevents deadlock when
    // requestSync is called from the main thread (e.g. inside JS evaluation
    // on a @MainActor context), since Alamofire's default response queue is main.
    // QoS set to .userInitiated to avoid priority inversion when called from
    // the main (User-interactive) thread.
    private let syncCallbackQueue = DispatchQueue(label: "com.legado.sync", qos: .userInitiated)

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
            session.request(req).responseData(queue: syncCallbackQueue) { resp in
                result = resp.data.flatMap { EncodingHelper.shared.decode($0) }
                semaphore.signal()
            }
        } else {
            session.request(url, method: httpMethod, headers: finalHeaders)
                .responseData(queue: syncCallbackQueue) { resp in
                    result = resp.data.flatMap { EncodingHelper.shared.decode($0) }
                    semaphore.signal()
                }
        }

        _ = semaphore.wait(timeout: .now() + 30)
        return result
    }

    /// Synchronous raw-data fetch (for binary assets such as TTF fonts in JS bridge).
    func requestSyncData(_ url: String) -> Data? {
        let semaphore = DispatchSemaphore(value: 0)
        var result: Data?
        session.request(url, method: .get).responseData { resp in
            result = resp.data
            semaphore.signal()
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
