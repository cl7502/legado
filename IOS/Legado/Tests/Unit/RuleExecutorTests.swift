import XCTest
@testable import Legado

class RuleExecutorTests: XCTestCase {
    
    var executor: RuleExecutor!
    var source: BookSource!
    
    override func setUp() {
        super.setUp()
        executor = RuleExecutor.shared
        source = BookSource(bookSourceName: "Test Source", bookSourceUrl: "http://test.com")
    }
    
    func testCSSParsing() {
        let html = "<html><body><div class='title'>Hello World</div></body></html>"
        var context = AnalyzeContext(source: source)
        context.result = html
        
        let result = executor.execute(".title@text", in: &context)
        XCTAssertEqual(result, "Hello World")
    }
    
    func testXPathParsing() {
        let html = "<html><body><div id='content'>XPath Result</div></body></html>"
        var context = AnalyzeContext(source: source)
        context.result = html
        
        // 测试真实 XPath 支持
        let result = executor.execute("@XPath://div[@id='content']/text()", in: &context)
        XCTAssertEqual(result, "XPath Result")
    }
    
    func testChainedParsing() {
        let html = "<html><body><div class='container'><span class='item'>Step 1</span></div></body></html>"
        var context = AnalyzeContext(source: source)
        context.result = html
        
        // 链式规则: 先选容器，再选内部 span
        let result = executor.execute(".container @ .item@text", in: &context)
        XCTAssertEqual(result, "Step 1")
    }
    
    func testJSParsing() {
        var context = AnalyzeContext(source: source)
        context.result = "input"
        
        let result = executor.execute("<js>'fixed_' + result</js>", in: &context)
        XCTAssertEqual(result, "fixed_input")
    }
    
    func testListParsing() {
        let html = "<ul><li>Item 1</li><li>Item 2</li></ul>"
        var context = AnalyzeContext(source: source)
        context.result = html
        
        let results = executor.executeList("li", in: &context)
        XCTAssertEqual(results.count, 2)
        XCTAssertTrue(results[0].contains("Item 1"))
    }
}
