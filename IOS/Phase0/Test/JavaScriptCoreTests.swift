import Foundation
import JavaScriptCore

class JavaScriptCoreTests {
    let context: JSContext

    init() {
        self.context = JSContext()
        setupContext()
    }

    private func setupContext() {
        context.exceptionHandler = { context, exception in
            print("JavaScript Error: \(exception ?? "")")
        }
    }

    func testArithmeticOperations() -> Bool {
        let result = context.evaluateScript("1 + 1")
        let success = result?.toInt32() == 2
        print("✅ 测试 1 (算术运算): \(success ? "通过" : "失败")")
        return success
    }

    func testFunctionCall() -> Bool {
        let result = context.evaluateScript("function add(a, b) { return a + b; } add(1, 2)")
        let success = result?.toInt32() == 3
        print("✅ 测试 2 (函数调用): \(success ? "通过" : "失败")")
        return success
    }

    func testObjectOperation() -> Bool {
        let result = context.evaluateScript("var obj = {name: 'test'}; obj.name")
        let success = result?.toString()?.toString() == "test"
        print("✅ 测试 3 (对象操作): \(success ? "通过" : "失败")")
        return success
    }

    func testArrayOperation() -> Bool {
        let result = context.evaluateScript("var arr = [1, 2, 3]; arr.length")
        let success = result?.toInt32() == 3
        print("✅ 测试 4 (数组操作): \(success ? "通过" : "失败")")
        return success
    }

    func testStringOperation() -> Bool {
        let result = context.evaluateScript("'hello'.length")
        let success = result?.toInt32() == 5
        print("✅ 测试 5 (字符串操作): \(success ? "通过" : "失败")")
        return success
    }

    func runAllTests() -> [String: Bool] {
        var results: [String: Bool] = [:]
        results["算术运算"] = testArithmeticOperations()
        results["函数调用"] = testFunctionCall()
        results["对象操作"] = testObjectOperation()
        results["数组操作"] = testArrayOperation()
        results["字符串操作"] = testStringOperation()
        return results
    }
}