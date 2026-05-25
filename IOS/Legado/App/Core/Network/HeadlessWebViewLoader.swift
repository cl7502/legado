import WebKit
import Foundation

/// Headless WKWebView fetcher for anti-scraping sources that set `"webView": true`.
/// Mirrors Android BackstageWebView + OkHttp integration.
///
/// Each call creates an isolated, non-persistent WKWebView; parallel source requests
/// don't share cookies or JS state.
enum HeadlessWebViewLoader {

    /// Fetch the fully-rendered HTML from `urlString`.
    /// - Parameters:
    ///   - headers:  extra request headers (source + per-request headers merged by caller)
    ///   - injectJs: JS evaluated after page load (mirrors Android `webJs` field)
    ///   - timeout:  seconds before URLError.timedOut is thrown (default 30)
    static func fetch(
        urlString: String,
        headers: [String: String] = [:],
        injectJs: String? = nil,
        timeout: TimeInterval = 30
    ) async throws -> String {
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }

        return try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
                    DispatchQueue.main.async {
                        WebViewRequest(url: url, headers: headers,
                                       injectJs: injectJs, cont: cont).start()
                    }
                }
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw URLError(.timedOut)
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
}

// MARK: - Per-request WKWebView wrapper

/// One disposable WKWebView for one fetch. Self-retains so ARC doesn't collect
/// it while loading (WKWebView holds `navigationDelegate` weakly).
private final class WebViewRequest: NSObject, WKNavigationDelegate {

    private let url: URL
    private let headers: [String: String]
    private let injectJs: String?
    private let wv: WKWebView
    private var cont: CheckedContinuation<String, Error>?
    // Strong cycle broken on completion; keeps self alive during load.
    private var selfRef: WebViewRequest?

    init(url: URL, headers: [String: String], injectJs: String?,
         cont: CheckedContinuation<String, Error>) {
        self.url = url
        self.headers = headers
        self.injectJs = injectJs
        self.cont = cont
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .nonPersistent()
        wv = WKWebView(frame: CGRect(x: -1, y: -1, width: 375, height: 812), configuration: cfg)
        super.init()
        wv.navigationDelegate = self
    }

    func start() {
        selfRef = self   // retain self for duration of load
        var req = URLRequest(url: url)
        headers.forEach { req.setValue($0.value, forHTTPHeaderField: $0.key) }
        wv.load(req)
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if let js = injectJs, !js.isEmpty {
            webView.evaluateJavaScript(js) { [weak self] _, _ in
                self?.extractHTML()
            }
        } else {
            extractHTML()
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(.failure(error))
    }

    func webView(_ webView: WKWebView,
                 didFailProvisionalNavigation navigation: WKNavigation!,
                 withError error: Error) {
        finish(.failure(error))
    }

    private func extractHTML() {
        wv.evaluateJavaScript("document.documentElement.outerHTML") { [weak self] result, _ in
            self?.finish(.success(result as? String ?? ""))
        }
    }

    private func finish(_ result: Result<String, Error>) {
        wv.navigationDelegate = nil      // break retain
        wv.stopLoading()
        let c = cont; cont = nil; selfRef = nil   // release cycle
        switch result {
        case .success(let html):  c?.resume(returning: html)
        case .failure(let error): c?.resume(throwing: error)
        }
    }
}
