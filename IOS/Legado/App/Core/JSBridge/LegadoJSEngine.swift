import Foundation
import JavaScriptCore

/// Legado 核心 JS 引擎
/// 目标：模拟 Rhino 环境，支持书源规则执行
class LegadoJSEngine {
    static let shared = LegadoJSEngine()
    
    private let context: JSContext
    
    init() {
        self.context = JSContext()
        setupContext()
    }
    
    private func setupContext() {
        // 配置异常处理
        context.exceptionHandler = { context, exception in
            print("JS Error: \(exception?.toString() ?? "unknown error")")
        }
        
        // TODO: 阶段 3 将实现全量的 Rhino API (java.ajax, java.md5 等)
        injectBasicHelpers()
    }
    
    private func injectBasicHelpers() {
        // 注入基础的全局变量占位
        context.setObject("", forKeyedSubscript: "baseUrl" as (NSCopying & NSObjectProtocol))
        context.setObject(nil, forKeyedSubscript: "result" as (NSCopying & NSObjectProtocol))
    }
    
    /// 执行 JS 脚本
    func evaluate(_ script: String) -> JSValue? {
        return context.evaluateScript(script)
    }
}
