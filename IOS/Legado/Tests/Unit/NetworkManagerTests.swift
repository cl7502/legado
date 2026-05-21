import XCTest
@testable import Legado

class NetworkManagerTests: XCTestCase {
    
    var network: NetworkManager!
    
    override func setUp() {
        super.setUp()
        network = NetworkManager.shared
    }
    
    func testEncodingDetection() {
        // 模拟一个 GBK 编码的二进制数据
        let gbkString = "测试中文编码"
        let gbkEncoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        let data = gbkString.data(using: gbkEncoding)!
        
        let decoded = EncodingHelper.shared.decode(data)
        XCTAssertEqual(decoded, gbkString)
    }
    
    func testCookiePersistence() {
        let url = "http://test-cookie.com"
        let cookie = "session=12345"
        
        CookieManager.shared.saveCookie(for: url, cookieString: cookie)
        let saved = CookieManager.shared.getCookie(for: url)
        
        XCTAssertEqual(saved, cookie)
    }
}
