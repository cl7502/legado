import Foundation
import JavaScriptCore

@objc protocol JSJavaHelperProtocol: JSExport {
    func ajax(_ url: String, method: String) -> String?
    func put(_ key: String, value: Any)
    func get(_ key: String) -> Any?
    func log(_ message: String)
}

class JSJavaHelper: NSObject, JSJavaHelperProtocol {
    func ajax(_ url: String, method: String = "GET") -> String? {
        print("AJAX Request: \(url), Method: \(method)")
        return "mock_response"
    }

    func put(_ key: String, value: Any) {
        print("PUT: \(key) = \(value)")
        UserDefaults.standard.set(value, forKey: key)
    }

    func get(_ key: String) -> Any? {
        print("GET: \(key)")
        return UserDefaults.standard.value(forKey: key)
    }

    func log(_ message: String) {
        print("LOG: \(message)")
    }
}

class RhinoAPITests {
    let context: JSContext

    init() {
        self.context = JSContext()
        setupContext()
    }

    private func setupContext() {
        context.exceptionHandler = { context, exception in
            print("JavaScript Error: \(exception ?? "")")
        }
        let javaHelper = JSJavaHelper()
        context.globalObject.setValue(javaHelper, forProperty: "java")
    }

    func testAjaxMethod() -> Bool {
        let result = context.evaluateScript("java.ajax('https://example.com', 'GET')")
        let success = result?.toString()?.toString() == "mock_response"
        print("✅ 测试 1 (ajax 方法): \(success ? "通过" : "失败")")
        return success
    }

    func testPutGetMethod() -> Bool {
        context.evaluateScript("java.put('testKey', 'testValue')")
        let result = context.evaluateScript("java.get('testKey')")
        let success = result?.toString()?.toString() == "testValue"
        print("✅ 测试 2 (put/get 方法): \(success ? "通过" : "失败")")
        return success
    }

    func testLogMethod() -> Bool {
        let result = context.evaluateScript("java.log('test message')")
        let success = result != nil
        print("✅ 测试 3 (log 方法): \(success ? "通过" : "失败")")
        return success
    }

    func runAllTests() -> [String: Bool] {
        var results: [String: Bool] = [:]
        results["ajax 方法"] = testAjaxMethod()
        results["put/get 方法"] = testPutGetMethod()
        results["log 方法"] = testLogMethod()
        return results
    }
}