import Foundation
import JavaScriptCore

/// Legado JS 引擎 — 串行队列保证并发安全
class LegadoJSEngine {
    static let shared = LegadoJSEngine()

    // javaHelper is shared; its per-evaluation state (currentContext, cacheObjects)
    // is set before each evaluation call on the serial queue.
    private let javaHelper: JSJavaHelper
    // Serial queue: all JS evaluations happen sequentially on one thread.
    let queue = DispatchQueue(label: "com.legado.jsengine", qos: .userInteractive)

    init() {
        self.javaHelper = JSJavaHelper()
    }

    // MARK: - Fresh-context factory

    /// Build a fresh JSContext loaded with all standard globals.
    /// A new context per evaluateRule call is the key isolation mechanism:
    /// it prevents let/const declarations in one source's script from
    /// polluting the next evaluation (Android uses a new Rhino scope per eval).
    private func makeFreshContext(ctx: AnalyzeContext) -> JSContext {
        let context = JSContext()!

        context.exceptionHandler = { _, exception in
            print("❌ [JS Error]: \(exception?.toString() ?? "unknown")")
        }

        // java bridge
        context.setObject(javaHelper,
                          forKeyedSubscript: "java" as (NSCopying & NSObjectProtocol))

        // Standard globals (mirror Android AnalyzeRule bindings)
        context.setObject(ctx.baseUrl as AnyObject,
                          forKeyedSubscript: "baseUrl" as (NSCopying & NSObjectProtocol))
        if let res = ctx.result as? String {
            context.setObject(res as AnyObject,
                              forKeyedSubscript: "result" as (NSCopying & NSObjectProtocol))
        }

        // book
        if let book = ctx.book {
            let d: [String: Any] = [
                "name": book.name, "author": book.author,
                "bookUrl": book.bookUrl, "origin": book.origin,
                "tocUrl": book.tocUrl ?? "", "variable": book.variable ?? "",
            ]
            context.setObject(d as AnyObject,
                              forKeyedSubscript: "book" as (NSCopying & NSObjectProtocol))
        }

        // chapter
        if let ch = ctx.chapter {
            let d: [String: Any] = [
                "title": ch.title, "url": ch.url, "index": ch.index,
            ]
            context.setObject(d as AnyObject,
                              forKeyedSubscript: "chapter" as (NSCopying & NSObjectProtocol))
        }

        // source
        let srcDict: [String: Any] = [
            "bookSourceName":  ctx.source.bookSourceName,
            "bookSourceUrl":   ctx.source.bookSourceUrl,
            "bookSourceGroup": ctx.source.bookSourceGroup ?? "",
            "bookSourceType":  ctx.source.bookSourceType,
        ]
        context.setObject(srcDict as AnyObject,
                          forKeyedSubscript: "source" as (NSCopying & NSObjectProtocol))

        // page / key
        context.setObject(ctx.page as AnyObject,
                          forKeyedSubscript: "page" as (NSCopying & NSObjectProtocol))
        context.setObject(ctx.searchKey as AnyObject,
                          forKeyedSubscript: "key" as (NSCopying & NSObjectProtocol))

        // cookie proxy
        context.setObject(JSCookieProxy(),
                          forKeyedSubscript: "cookie" as (NSCopying & NSObjectProtocol))

        return context
    }

    // MARK: - Public API

    /// Execute a JS rule script and return the result string.
    func evaluateRule(_ script: String, in analyzeContext: inout AnalyzeContext) -> String? {
        var ctx = analyzeContext
        var resultString: String?

        queue.sync { [weak self] in
            guard let self = self else { return }

            // Bind the helper to the current evaluation context
            self.javaHelper.currentContext = ctx

            // Fresh JSContext — zero pollution from previous evaluations
            let context = self.makeFreshContext(ctx: ctx)

            // Load source jsLib utility functions BEFORE the rule script.
            // Android evaluates jsLib once per source engine; we re-eval per call
            // (acceptable overhead, guarantees isolation).
            if let jsLib = ctx.source.jsLib, !jsLib.isEmpty {
                context.evaluateScript(jsLib)
            }

            let jsValue = context.evaluateScript(script)

            // Propagate variables written by java.put() back to caller
            ctx.variables = self.javaHelper.currentContext?.variables ?? [:]

            if jsValue?.isUndefined == true || jsValue?.isNull == true {
                resultString = nil
            } else {
                resultString = jsValue?.toString()
            }
        }

        analyzeContext.variables = ctx.variables
        return resultString
    }
}

// MARK: - Cookie proxy exposed to JS as `cookie`

@objc private class JSCookieProxy: NSObject {
    @objc func getCookie(_ tag: String) -> String {
        CookieManager.shared.getCookie(for: tag) ?? ""
    }
    @objc func setCookie(_ tag: String, _ value: String) {
        CookieManager.shared.saveCookie(for: tag, cookieString: value)
    }
}
