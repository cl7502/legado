import XCTest
@testable import Legado

class IntegrationTests: XCTestCase {
    
    var db: DatabaseManager!
    
    override func setUp() async throws {
        try await super.setUp()
        db = DatabaseManager.shared
        // 清理数据库或使用内存数据库 (此处假设 shared 已初始化)
    }
    
    func testSearchToShelfFlow() async throws {
        // 1. 模拟导入一个书源
        let sourceJson = """
        {
            "bookSourceName": "Test Source",
            "bookSourceUrl": "http://test.com",
            "searchUrl": "http://test.com/search?key={{key}}",
            "ruleSearchList": "li",
            "ruleSearchName": "h3@text"
        }
        """
        let importer = BookSourceImporter()
        let sources = importer.parse(sourceJson)
        try await db.saveBookSources(sources)
        
        // 2. 验证书源已保存并启用
        let enabledSources = try await db.getEnabledBookSources()
        XCTAssertTrue(enabledSources.contains { $0.bookSourceUrl == "http://test.com" })
        
        // 3. 模拟书籍加入书架
        let book = Book(
            bookUrl: "http://test.com/book/1",
            name: "Test Book",
            author: "Author",
            origin: "http://test.com",
            originName: "Test Source"
        )
        try await db.saveBook(book)
        
        // 4. 验证书架
        let shelf = try await db.getBookshelf()
        XCTAssertTrue(shelf.contains { $0.bookUrl == "http://test.com/book/1" })
    }
    
    func testContentPurificationIntegration() {
        let rawContent = "Ad Header\nReal text content\nAd Footer"
        let rule = ReplaceRule(name: "Remove Header", pattern: "Ad Header", replacement: "", isRegex: false)
        
        let processed = ContentProcessor.shared.process(rawContent, with: [rule])
        
        XCTAssertFalse(processed.contains("Ad Header"))
        XCTAssertTrue(processed.contains("Real text content"))
    }
}
