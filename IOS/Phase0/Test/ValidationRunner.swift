import Foundation

class ValidationRunner {
    static let shared = ValidationRunner()

    private init() {}

    func runAllTests() -> String {
        var output = ""
        output += "========================================\n"
        output += "  Legado iOS 版本验证程序\n"
        output += "  版本: v1.0\n"
        output += "  日期: 2025年12月28日\n"
        output += "========================================\n\n"

        // JavaScriptCore 基础功能测试
        output += "【1. JavaScriptCore 基础功能测试】\n"
        let jsTests = JavaScriptCoreTests()
        let jsResults = jsTests.runAllTests()
        output += printResults(jsResults, title: "JavaScriptCore 基础功能")

        // Rhino API 兼容性测试
        output += "\n【2. Rhino API 兼容性测试】\n"
        let rhinoTests = RhinoAPITests()
        let rhinoResults = rhinoTests.runAllTests()
        output += printResults(rhinoResults, title: "Rhino API 兼容性")

        // 规则解析系统测试
        output += "\n【3. 规则解析系统测试】\n"
        let ruleTests = RuleParserTests()
        let ruleResults = ruleTests.runAllTests()
        output += printResults(ruleResults, title: "规则解析系统")

        // HTML 解析测试
        output += "\n【4. HTML 解析测试】\n"
        let htmlTests = HTMLParserTests()
        let htmlResults = htmlTests.runAllTests()
        output += printResults(htmlResults, title: "HTML 解析")

        // 汇总结果
        output += "\n========================================\n"
        output += "  测试结果汇总\n"
        output += "========================================\n"

        let allResults = [
            ("JavaScriptCore 基础功能", jsResults),
            ("Rhino API 兼容性", rhinoResults),
            ("规则解析系统", ruleResults),
            ("HTML 解析", htmlResults)
        ]

        var totalTests = 0
        var passedTests = 0

        for (category, results) in allResults {
            let categoryTotal = results.count
            let categoryPassed = results.values.filter { $0 }.count
            let passRate = Double(categoryPassed) / Double(categoryTotal) * 100

            totalTests += categoryTotal
            passedTests += categoryPassed

            output += "\(category): \(categoryPassed)/\(categoryTotal) 通过 (\(String(format: "%.1f", passRate))%)\n"
        }

        let overallPassRate = Double(passedTests) / Double(totalTests) * 100
        output += "\n总计: \(passedTests)/\(totalTests) 通过 (\(String(format: "%.1f", overallPassRate))%)\n"

        if overallPassRate >= 95 {
            output += "\n✅ 验证通过！可以继续开发。\n"
        } else if overallPassRate >= 80 {
            output += "\n⚠️ 验证部分通过，需要调整方案。\n"
        } else {
            output += "\n❌ 验证失败，需要重新评估技术方案。\n"
        }

        output += "========================================\n"

        return output
    }

    private func printResults(_ results: [String: Bool], title: String) -> String {
        var output = ""
        output += "\n\(title)测试结果:\n"
        for (testName, passed) in results {
            let status = passed ? "✅" : "❌"
            output += "  \(status) \(testName)\n"
        }
        return output
    }
}