import Foundation
import JavaScriptCore

/// Legado 核心 JS 引擎 (GSD 强化版)
/// 目标：100% 模拟 Rhino 环境，支持书源规则执行
class LegadoJSEngine {
    static let shared = LegadoJSEngine()
    
    private let context: JSContext
    private let javaHelper: JSJavaHelper
    
    init() {
        self.context = JSContext()
        self.javaHelper = JSJavaHelper()
        setupContext()
    }
    
    private func setupContext() {
        // 配置异常处理
        context.exceptionHandler = { context, exception in
            let error = exception?.toString() ?? "unknown error"
            print("❌ [JS Error]: \(error)")
        }
        
        // 注入 java 对象 (Rhino 兼容桥梁)
        context.setObject(javaHelper, forKeyedSubscript: "java" as (NSCopying & NSObjectProtocol))
        
        // 注入全局基础变量
        context.setObject("", forKeyedSubscript: "baseUrl" as (NSCopying & NSObjectProtocol))
    }
    
    /// 执行规则脚本
    /// - Parameters:
    ///   - script: JS 规则代码
    ///   - analyzeContext: 解析上下文（包含书源、变量、上级结果）
    func evaluateRule(_ script: String, in analyzeContext: inout AnalyzeContext) -> String? {
        // 1. 同步上下文到桥接对象
        javaHelper.currentContext = analyzeContext
        
        // 2. 注入 JS 全局环境
        context.setObject(analyzeContext.baseUrl, forKeyedSubscript: "baseUrl" as (NSCopying & NSObjectProtocol))
        
        // 如果有上级结果，注入为 result 变量
        if let result = analyzeContext.result {
            context.setObject(result, forKeyedSubscript: "result" as (NSCopying & NSObjectProtocol))
        }
        
        // 3. 执行脚本
        let jsValue = context.evaluateScript(script)
        
        // 4. 回写变量 (如果有变更)
        analyzeContext.variables = javaHelper.currentContext?.variables ?? [:]
        
        // 5. 返回结果
        if jsValue?.isUndefined == true || jsValue?.isNull == true {
            return nil
        }
        return jsValue?.toString()
    }
}
