import Foundation

enum RuleType {
    case defaultRule
    case xpath
    case json
    case regex
    case javascript

    static func parse(_ rule: String) -> (RuleType, String) {
        if rule.hasPrefix("<js>") {
            let content = String(rule.dropFirst(4).dropLast(5))
            return (.javascript, content)
        } else if rule.hasPrefix("@XPath:") {
            let content = String(rule.dropFirst(7))
            return (.xpath, content)
        } else if rule.hasPrefix("@Json:") {
            let content = String(rule.dropFirst(6))
            return (.json, content)
        } else if rule.hasPrefix("@Regex:") {
            let content = String(rule.dropFirst(7))
            return (.regex, content)
        } else if rule.hasPrefix("@") {
            let content = String(rule.dropFirst(1))
            return (.defaultRule, content)
        } else {
            return (.defaultRule, rule)
        }
    }
}

class RuleParserTests {
    func testXPathRule() -> Bool {
        let rule = "@XPath://div[@class='title']/text()"
        let (type, content) = RuleType.parse(rule)
        let success = type == .xpath && content == "//div[@class='title']/text()"
        print("✅ 测试 1 (XPath 规则): \(success ? "通过" : "失败")")
        return success
    }

    func testJSONRule() -> Bool {
        let rule = "@Json:$.data.list[*].title"
        let (type, content) = RuleType.parse(rule)
        let success = type == .json && content == "$.data.list[*].title"
        print("✅ 测试 2 (JSON 规则): \(success ? "通过" : "失败")")
        return success
    }

    func testRegexRule() -> Bool {
        let rule = "@Regex:<title>(.*?)</title>"
        let (type, content) = RuleType.parse(rule)
        let success = type == .regex && content == "<title>(.*?)</title>"
        print("✅ 测试 3 (正则规则): \(success ? "通过" : "失败")")
        return success
    }

    func testJavaScriptRule() -> Bool {
        let rule = "<js>result.map(item => item.title)</js>"
        let (type, content) = RuleType.parse(rule)
        let success = type == .javascript && content == "result.map(item => item.title)"
        print("✅ 测试 4 (JavaScript 规则): \(success ? "通过" : "失败")")
        return success
    }

    func testDefaultRule() -> Bool {
        let rule = ".title@text"
        let (type, content) = RuleType.parse(rule)
        let success = type == .defaultRule && content == ".title@text"
        print("✅ 测试 5 (默认规则): \(success ? "通过" : "失败")")
        return success
    }

    func runAllTests() -> [String: Bool] {
        var results: [String: Bool] = [:]
        results["XPath 规则"] = testXPathRule()
        results["JSON 规则"] = testJSONRule()
        results["正则规则"] = testRegexRule()
        results["JavaScript 规则"] = testJavaScriptRule()
        results["默认规则"] = testDefaultRule()
        return results
    }
}