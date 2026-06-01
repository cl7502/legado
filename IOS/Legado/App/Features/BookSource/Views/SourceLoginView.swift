import SwiftUI
import WebKit

/// 书源 WebView 登录界面
/// 对标 Android SourceLoginActivity + WebViewLoginFragment：
///   - 无 loginUi 时，打开 loginUrl（WebView 方式）
///   - 每次页面加载完成，从 WKHTTPCookieStore 提取 Cookie 并持久化到 CookieManager
///   - 用户点"完成"后执行 loginCheckJs 验证登录状态，再关闭弹窗
struct SourceLoginView: View {

    let source: BookSource
    @Environment(\.dismiss) private var dismiss

    @State private var loginStatus: LoginStatus = .idle
    @State private var loadingURL: String = ""
    @State private var webViewRef: WKWebView? = nil

    enum LoginStatus {
        case idle, loading, verifying, done, failed(String)
    }

    // 解析 loginUrl：处理 @js:/<js> 前缀，返回可直接在 WKWebView 加载的 HTTP URL
    private var resolvedLoginUrl: String? {
        guard var url = source.loginUrl, !url.isEmpty else { return nil }
        url = url.trimmingCharacters(in: .whitespacesAndNewlines)
        // @js: / <js> 格式 — 通过 JS 引擎执行拿到真实 URL（少数书源用法）
        if url.hasPrefix("@js:") || url.lowercased().hasPrefix("<js>") {
            var ctx = AnalyzeContext(source: source, baseUrl: source.bookSourceUrl)
            return LegadoJSEngine.shared.evaluateRule(url, in: &ctx)
        }
        return url
    }

    var body: some View {
        NavigationView {
            ZStack {
                if let loginUrl = resolvedLoginUrl {
                    WebViewRepresentable(
                        urlString: loginUrl,
                        source: source,
                        onLoadStatusChange: { loading in
                            loginStatus = loading ? .loading : .idle
                        },
                        onWebViewCreated: { wv in
                            webViewRef = wv
                        }
                    )
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "link.slash")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("该书源未配置登录 URL")
                            .font(.headline)
                        Text("请在书源编辑页填写「登录 URL」字段")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                }

                // 状态遮罩
                if case .verifying = loginStatus {
                    Color.black.opacity(0.3).ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("验证登录状态…").font(.caption).foregroundColor(.white)
                    }
                }
                if case .failed(let msg) = loginStatus {
                    VStack {}
                        .alert("登录验证失败", isPresented: .constant(true)) {
                            Button("继续使用") { loginStatus = .idle }
                            Button("关闭") { dismiss() }
                        } message: { Text(msg) }
                }
            }
            .navigationTitle("登录 · \(source.bookSourceName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { finishLogin() }
                        .disabled({ if case .verifying = loginStatus { return true }; return false }())
                }
            }
        }
    }

    // MARK: - 完成登录
    // 对标 Android WebViewLoginFragment 用户点"确认"后执行 loginCheckJs
    private func finishLogin() {
        guard let checkJs = source.loginCheckJs, !checkJs.isEmpty else {
            dismiss(); return
        }
        loginStatus = .verifying
        Task {
            // 先等 WKWebView 最新一轮 Cookie 写入 HTTPCookieStore
            try? await Task.sleep(nanoseconds: 300_000_000)
            await extractAndSaveCookies()

            // 执行 loginCheckJs 验证
            var ctx = AnalyzeContext(source: source, baseUrl: source.bookSourceUrl)
            ctx.result = ""   // loginCheckJs 通常自己发请求做检测
            let result = LegadoJSEngine.shared.evaluateRule(checkJs, in: &ctx)
            if result == nil {
                // JS 抛出异常或返回 nil → 可能未登录，给用户提示但不强制阻止
                loginStatus = .failed("loginCheckJs 返回空，请确认已完成登录")
            } else {
                loginStatus = .done
                dismiss()
            }
        }
    }

    // MARK: - Cookie 提取
    // 对标 Android WebViewLoginFragment.onPageFinished → CookieStore.setCookie(source.getKey(), cookie)
    @MainActor
    private func extractAndSaveCookies() async {
        guard let wv = webViewRef else { return }
        let cookieStore = wv.configuration.websiteDataStore.httpCookieStore
        let allCookies = await cookieStore.allCookies()

        var byDomain: [String: [String]] = [:]
        for cookie in allCookies {
            let domain = cookie.domain.hasPrefix(".") ? String(cookie.domain.dropFirst()) : cookie.domain
            byDomain[domain, default: []].append("\(cookie.name)=\(cookie.value)")
        }

        // 按域名保存（对标 Android 按 host 存储）
        for (domain, parts) in byDomain {
            CookieManager.shared.saveCookie(for: "https://\(domain)", cookieString: parts.joined(separator: "; "))
        }

        // 同时按 bookSourceUrl 保存（对标 Android source.getKey() 作为 tag）
        let allStr = byDomain.values.flatMap { $0 }.joined(separator: "; ")
        if !allStr.isEmpty {
            CookieManager.shared.saveCookie(forTag: source.bookSourceUrl, value: allStr)
            print("🍪 [Login] 已保存 Cookie for \(source.bookSourceName)：\(allStr.prefix(80))…")
        }
    }
}

// MARK: - WKWebView UIViewRepresentable 包装
// 每次页面加载完成后提取 Cookie，对标 Android WebViewClient.onPageFinished()
private struct WebViewRepresentable: UIViewRepresentable {

    let urlString: String
    let source: BookSource
    let onLoadStatusChange: (Bool) -> Void
    let onWebViewCreated: (WKWebView) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        // 非持久存储避免污染全局 Cookie（与 HeadlessWebViewLoader 一致）
        // 登录后手动提取再保存到 CookieManager
        cfg.websiteDataStore = .nonPersistent()

        // 注意：有些书源需要 JS 登录，开启 JS 支持
        // iOS 26 默认已开启，明确声明供旧版参考
        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.navigationDelegate = context.coordinator
        onWebViewCreated(wv)
        return wv
    }

    func updateUIView(_ wv: WKWebView, context: Context) {
        guard let url = URL(string: urlString), wv.url == nil else { return }
        var req = URLRequest(url: url)
        // 注入书源 header（对标 Android WebViewLoginFragment.loadUrl(url, headerMap)）
        source.headerDictionary.forEach { req.setValue($0.value, forHTTPHeaderField: $0.key) }
        wv.load(req)
    }

    // MARK: - Coordinator = WKNavigationDelegate
    class Coordinator: NSObject, WKNavigationDelegate {
        let parent: WebViewRepresentable

        init(_ parent: WebViewRepresentable) { self.parent = parent }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            parent.onLoadStatusChange(true)
        }

        // 对标 Android WebViewClient.onPageFinished()
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.onLoadStatusChange(false)
            // 每次页面加载完成即提取 Cookie（用户可能在多步登录中）
            let cookieStore = webView.configuration.websiteDataStore.httpCookieStore
            cookieStore.getAllCookies { cookies in
                var byDomain: [String: [String]] = [:]
                for cookie in cookies {
                    let domain = cookie.domain.hasPrefix(".") ? String(cookie.domain.dropFirst()) : cookie.domain
                    byDomain[domain, default: []].append("\(cookie.name)=\(cookie.value)")
                }
                let sourceUrl = self.parent.source.bookSourceUrl
                for (domain, parts) in byDomain {
                    CookieManager.shared.saveCookie(for: "https://\(domain)", cookieString: parts.joined(separator: "; "))
                }
                let allStr = byDomain.values.flatMap { $0 }.joined(separator: "; ")
                if !allStr.isEmpty {
                    CookieManager.shared.saveCookie(forTag: sourceUrl, value: allStr)
                }
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            parent.onLoadStatusChange(false)
        }

        func webView(_ webView: WKWebView,
                     didFailProvisionalNavigation navigation: WKNavigation!,
                     withError error: Error) {
            parent.onLoadStatusChange(false)
        }

        // SSL 错误：允许继续（对标 Android WebViewClient.onReceivedSslError PROCEED）
        // 部分老书源使用过期证书，iOS 严格模式下无法加载
        func webView(_ webView: WKWebView,
                     didReceive challenge: URLAuthenticationChallenge,
                     completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
            if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
               let trust = challenge.protectionSpace.serverTrust {
                completionHandler(.useCredential, URLCredential(trust: trust))
            } else {
                completionHandler(.performDefaultHandling, nil)
            }
        }
    }
}

// WKHTTPCookieStore async helper (iOS 17+ 有原生 async，低版本用 callback 包装)
private extension WKHTTPCookieStore {
    func allCookies() async -> [HTTPCookie] {
        await withCheckedContinuation { cont in
            getAllCookies { cont.resume(returning: $0) }
        }
    }
}
