import Foundation
import JavaScriptCore

/// Legado JS 引擎 — 串行队列保证并发安全
class LegadoJSEngine {
    static let shared = LegadoJSEngine()

    private let context: JSContext
    private let javaHelper: JSJavaHelper
    // 串行队列：所有 JS 执行在同一线程上依次进行，避免 JSContext 竞态
    let queue = DispatchQueue(label: "com.legado.jsengine", qos: .userInteractive)

    init() {
        self.context = JSContext()
        self.javaHelper = JSJavaHelper()
        setupContext()
    }

    private func setupContext() {
        context.exceptionHandler = { _, exception in
            print("❌ [JS Error]: \(exception?.toString() ?? "unknown")")
        }
        context.setObject(javaHelper, forKeyedSubscript: "java" as (NSCopying & NSObjectProtocol))
        context.setObject("", forKeyedSubscript: "baseUrl" as (NSCopying & NSObjectProtocol))
    }

    /// 执行规则脚本（线程安全）
    func evaluateRule(_ script: String, in analyzeContext: inout AnalyzeContext) -> String? {
        // 将 inout 值复制出来，因为闭包不能捕获 inout
        var ctx = analyzeContext
        var resultString: String?

        queue.sync { [weak self] in
            guard let self = self else { return }

            self.javaHelper.currentContext = ctx
            self.context.setObject(ctx.baseUrl as AnyObject,
                                   forKeyedSubscript: "baseUrl" as (NSCopying & NSObjectProtocol))
            if let res = ctx.result as? String {
                self.context.setObject(res as AnyObject,
                                       forKeyedSubscript: "result" as (NSCopying & NSObjectProtocol))
            }

            // MARK: JS context bindings (mirrors Android AnalyzeRule L776-786)

            // book — serialised as plain dict so JS can read book.name etc.
            if let book = ctx.book {
                let bookDict: [String: Any] = [
                    "name": book.name, "author": book.author,
                    "bookUrl": book.bookUrl, "origin": book.origin,
                    "tocUrl": book.tocUrl ?? "",
                    "variable": book.variable ?? "",
                ]
                self.context.setObject(bookDict as AnyObject,
                                       forKeyedSubscript: "book" as (NSCopying & NSObjectProtocol))
            }

            // chapter
            if let chapter = ctx.chapter {
                let chapDict: [String: Any] = [
                    "title": chapter.title, "url": chapter.url, "index": chapter.index,
                ]
                self.context.setObject(chapDict as AnyObject,
                                       forKeyedSubscript: "chapter" as (NSCopying & NSObjectProtocol))
            }

            // source
            let sourceDict: [String: Any] = [
                "bookSourceName": ctx.source.bookSourceName,
                "bookSourceUrl": ctx.source.bookSourceUrl,
                "bookSourceGroup": ctx.source.bookSourceGroup ?? "",
                "bookSourceType": ctx.source.bookSourceType,
            ]
            self.context.setObject(sourceDict as AnyObject,
                                   forKeyedSubscript: "source" as (NSCopying & NSObjectProtocol))

            // page / key
            self.context.setObject(ctx.page as AnyObject,
                                   forKeyedSubscript: "page" as (NSCopying & NSObjectProtocol))
            self.context.setObject(ctx.searchKey as AnyObject,
                                   forKeyedSubscript: "key" as (NSCopying & NSObjectProtocol))

            // cookie proxy — exposes getCookie(tag)/setCookie(tag,value) to JS
            let cookieProxy = JSCookieProxy()
            self.context.setObject(cookieProxy,
                                   forKeyedSubscript: "cookie" as (NSCopying & NSObjectProtocol))

            let jsValue = self.context.evaluateScript(script)
            // 写回变量（JS 内通过 java.put/java.get 修改的变量）
            ctx.variables = self.javaHelper.currentContext?.variables ?? [:]

            if jsValue?.isUndefined == true || jsValue?.isNull == true {
                resultString = nil
            } else {
                resultString = jsValue?.toString()
            }
        }

        // 把 JS 修改的变量写回原始 inout 上下文
        analyzeContext.variables = ctx.variables
        return resultString
    }
}

// MARK: - Cookie proxy exposed to JS as `cookie`

@objc private class JSCookieProxy: NSObject {
    @objc func getCookie(_ tag: String) -> String {
        return CookieManager.shared.getCookie(for: tag) ?? ""
    }

    @objc func setCookie(_ tag: String, _ value: String) {
        CookieManager.shared.saveCookie(for: tag, cookieString: value)
    }
}
