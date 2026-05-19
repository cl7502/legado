import Foundation

class HTMLParser {
    func regex(_ html: String, regex: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: regex) else {
            return nil
        }
        let range = NSRange(html.startIndex..., in: html)
        guard let match = regex.firstMatch(in: html, range: range) else {
            return nil
        }
        let captureRange = match.range(at: 1)
        if captureRange.location == NSNotFound {
            return nil
        }
        return (html as NSString).substring(with: captureRange)
    }
}

class HTMLParserTests {
    let parser = HTMLParser()

    func testRegex() -> Bool {
        let html = "<title>Test Title</title>"
        let result = parser.regex(html, regex: "<title>(.*?)</title>")
        let success = result == "Test Title"
        print("✅ 测试 1 (正则): \(success ? "通过" : "失败")")
        return success
    }

    func runAllTests() -> [String: Bool] {
        var results: [String: Bool] = [:]
        results["正则"] = testRegex()
        return results
    }
}