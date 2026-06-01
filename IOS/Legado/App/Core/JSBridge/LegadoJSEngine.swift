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

    // 用于检测是否已在 jsengine 串行队列上执行，防止 queue.sync 重入死锁
    // 场景：JS 脚本调用 java.ajax("@js:...") → AnalyzeUrl.parse → evaluateRule
    // 若不检测，第二次 queue.sync 对同一串行队列重入 → 永久死锁，Watchdog SIGKILL
    private let queueKey = DispatchSpecificKey<Bool>()

    init() {
        self.javaHelper = JSJavaHelper()
        queue.setSpecific(key: queueKey, value: true)
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

        // result / src — Android always binds these even when nil (avoids ReferenceError).
        // We convert non-String values (JSON objects) to their JSON string representation.
        // 注意：NSJSONSerialization 对非 Array/Dictionary 顶层类型抛 ObjC NSException（不是 Swift Error），
        // try? 无法捕获。必须先用 isValidJSONObject 检查，再调用 data(withJSONObject:)。
        let resultStr: String
        if let s = ctx.result as? String {
            resultStr = s
        } else if let obj = ctx.result,
                  JSONSerialization.isValidJSONObject(obj),
                  let data = try? JSONSerialization.data(withJSONObject: obj),
                  let json = String(data: data, encoding: .utf8) {
            resultStr = json
        } else {
            resultStr = ""
        }
        context.setObject(resultStr as AnyObject,
                          forKeyedSubscript: "result" as (NSCopying & NSObjectProtocol))
        // Android also exposes content as `src`
        context.setObject(resultStr as AnyObject,
                          forKeyedSubscript: "src" as (NSCopying & NSObjectProtocol))

        // baseUrl
        context.setObject(ctx.baseUrl as AnyObject,
                          forKeyedSubscript: "baseUrl" as (NSCopying & NSObjectProtocol))

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

        // chapter + title (Android binds both)
        if let ch = ctx.chapter {
            let d: [String: Any] = [
                "title": ch.title, "url": ch.url, "index": ch.index,
            ]
            context.setObject(d as AnyObject,
                              forKeyedSubscript: "chapter" as (NSCopying & NSObjectProtocol))
            context.setObject(ch.title as AnyObject,
                              forKeyedSubscript: "title" as (NSCopying & NSObjectProtocol))
        }

        // source — 暴露为带方法的 JS 对象，兼容 Android 书源常用的 source.getKey() / source.getVariable()
        let sourceUrl   = ctx.source.bookSourceUrl
        let sourceShim  = """
        var source = {
            bookSourceName:  \(jsStringLiteral(ctx.source.bookSourceName)),
            bookSourceUrl:   \(jsStringLiteral(sourceUrl)),
            bookSourceGroup: \(jsStringLiteral(ctx.source.bookSourceGroup ?? "")),
            bookSourceType:  \(ctx.source.bookSourceType),
            key:             \(jsStringLiteral(sourceUrl)),
            variable:        "",
            getKey:      function() { return this.key; },
            getVariable: function() { return this.variable; }
        };
        """
        context.evaluateScript(sourceShim)

        // page / key
        context.setObject(ctx.page as AnyObject,
                          forKeyedSubscript: "page" as (NSCopying & NSObjectProtocol))
        context.setObject(ctx.searchKey as AnyObject,
                          forKeyedSubscript: "key" as (NSCopying & NSObjectProtocol))

        // nextChapterUrl (Android AnalyzeRule:786) — used by JS rules to build pagination
        let nextChapterUrl = ctx.variables["nextChapterUrl"] as? String ?? ""
        context.setObject(nextChapterUrl as AnyObject,
                          forKeyedSubscript: "nextChapterUrl" as (NSCopying & NSObjectProtocol))
        // rssArticle (Android AnalyzeRule:787) — RSS not implemented on iOS; bind empty string
        context.setObject("" as AnyObject,
                          forKeyedSubscript: "rssArticle" as (NSCopying & NSObjectProtocol))

        // cookie proxy
        context.setObject(JSCookieProxy(),
                          forKeyedSubscript: "cookie" as (NSCopying & NSObjectProtocol))

        // cache shim (Android AnalyzeRule:778 binds CacheManager as `cache`)
        // Wraps java.getFromCacheObject / java.setToCacheObject so JS sources can call
        // cache.get(key), cache.put(key, value, time), cache.getOrPut(key, getter, time).
        let cacheShim = """
        var cache = {
            get: function(key) {
                var v = java.getFromCacheObject(key);
                return (v === null || v === undefined) ? '' : v;
            },
            put: function(key, value, time) {
                java.setToCacheObject(key, value);
                return value;
            },
            getOrPut: function(key, getter, time) {
                var v = java.getFromCacheObject(key);
                if (v !== null && v !== undefined && v !== '') return v;
                var nv = getter();
                java.setToCacheObject(key, nv);
                return nv;
            }
        };
        """
        context.evaluateScript(cacheShim)

        // Minimal $ shim — guards against sources whose jsLib failed to define $
        // before our real jsLib eval runs. Real $ should be overwritten by jsLib.
        let dollarShim = """
        if (typeof $ === 'undefined') {
            var $ = function(sel) {
                var h = (typeof result !== 'undefined') ? result : '';
                return {
                    text: function() { return java.queryAllTextContent(h, sel) || ''; },
                    attr: function(n) { return java.queryTextContent(h, sel + '@' + n) || ''; },
                    html: function() { return java.queryTextContent(h, sel) || ''; },
                    find: function(c) { return $(sel + ' ' + c); },
                    first: function() { return this; },
                    last:  function() { return this; },
                    eq:    function() { return this; }
                };
            };
        }
        """
        context.evaluateScript(dollarShim)

        // Packages 兼容层：对标 Android 书源中常见的 Packages.java.* / Packages.android.* 调用
        // 轻文库说等书源的 jsLib 使用 Packages.java.lang.System.currentTimeMillis()
        // 和 Packages.android.util.Base64.encodeToString() 等 Android 专用 API
        let packagesShim = """
        var Packages = {
            java: {
                lang: {
                    String: function(s) {
                        var _s = String(s);
                        return { getBytes: function(charset) { return _s; },
                                 toString:  function() { return _s; } };
                    },
                    System: { currentTimeMillis: function() { return Date.now(); } }
                }
            },
            android: {
                util: {
                    Base64: {
                        NO_WRAP: 2, DEFAULT: 0,
                        encodeToString: function(bytesOrStr, flags) {
                            var s = (typeof bytesOrStr === 'object' && bytesOrStr !== null)
                                ? (bytesOrStr.toString ? bytesOrStr.toString() : String(bytesOrStr))
                                : String(bytesOrStr);
                            return java.base64Encode(s);
                        }
                    }
                }
            }
        };
        """
        context.evaluateScript(packagesShim)

        return context
    }

    // MARK: - Public API

    /// Execute a JS rule script and return the result string.
    func evaluateRule(_ script: String, in analyzeContext: inout AnalyzeContext) -> String? {
        var ctx = analyzeContext
        var resultString: String?

        let alreadyOnQueue = DispatchQueue.getSpecific(key: queueKey) == true

        let block = { [weak self] in
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
            } else if jsValue?.isArray == true {
                // Android Rhino returns actual Java arrays from JS; JavaScriptCore converts
                // arrays to comma-separated strings via toString(). Normalise to newline-
                // separated so RuleExecutor.applySegmentList can split on \n (matching Android).
                if let arr = jsValue?.toArray() {
                    let joined = arr
                        .compactMap { item -> String? in
                            let s = "\(item)"
                            return (s == "undefined" || s == "null") ? nil : s
                        }
                        .joined(separator: "\n")
                    resultString = joined.isEmpty ? nil : joined
                } else {
                    resultString = jsValue?.toString()
                }
            } else {
                resultString = jsValue?.toString()
            }
        }

        // 若已在 jsengine 队列上（即嵌套调用），直接执行避免 queue.sync 重入死锁
        if alreadyOnQueue {
            block()
        } else {
            queue.sync { block() }
        }

        analyzeContext.variables = ctx.variables
        return resultString
    }

    // 把 Swift String 转为 JS 字符串字面量（处理换行、引号等特殊字符）
    private func jsStringLiteral(_ s: String) -> String {
        let escaped = s
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
        return "\"\(escaped)\""
    }
}

// MARK: - Cookie proxy exposed to JS as `cookie`

/// JSExport 协议确保 JavaScript 能可靠调用这三个方法
@objc private protocol JSCookieProxyExport: JSExport {
    func getCookie(_ tag: String) -> String
    func setCookie(_ tag: String, _ value: String)
    func removeCookie(_ tag: String)
}

@objc private class JSCookieProxy: NSObject, JSCookieProxyExport {
    func getCookie(_ tag: String) -> String {
        CookieManager.shared.getCookie(for: tag) ?? ""
    }
    func setCookie(_ tag: String, _ value: String) {
        CookieManager.shared.saveCookie(for: tag, cookieString: value)
    }
    func removeCookie(_ tag: String) {
        CookieManager.shared.removeCookie(forTag: tag)
    }
}
