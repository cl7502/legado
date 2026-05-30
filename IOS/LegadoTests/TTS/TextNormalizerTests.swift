import XCTest
@testable import Legado

final class TextNormalizerTests: XCTestCase {
    var sut: TextNormalizer!

    override func setUp() { sut = TextNormalizer() }

    func test_integer_under_10000() {
        XCTAssertEqual(sut.normalize("今天来了3个人"), "今天来了三个人")
    }

    func test_integer_10000_plus() {
        XCTAssertEqual(sut.normalize("损失12000元"), "损失一万两千元")
    }

    func test_year_4digits() {
        XCTAssertEqual(sut.normalize("2024年"), "二零二四年")
    }

    func test_month_day() {
        XCTAssertEqual(sut.normalize("10月1日"), "十月一日")
    }

    func test_time_hhmm() {
        XCTAssertEqual(sut.normalize("14:30"), "十四点三十分")
    }

    func test_percentage() {
        XCTAssertEqual(sut.normalize("成功率98%"), "成功率百分之九十八")
    }

    func test_decimal_amount() {
        XCTAssertEqual(sut.normalize("花了1,234.56元"), "花了一千两百三十四点五六元")
    }

    func test_ellipsis_normalized() {
        XCTAssertEqual(sut.normalize("他说……然后离开"), "他说…然后离开")
    }

    func test_zero_width_chars_removed() {
        XCTAssertEqual(sut.normalize("他\u{200B}说"), "他说")
    }

    func test_mixed_sentence() {
        let input = "他花了1,234.56元买了3本书，于2024年10月1日到货"
        let output = sut.normalize(input)
        XCTAssertTrue(output.contains("一千两百三十四点五六元"))
        XCTAssertTrue(output.contains("三本书"))
        XCTAssertTrue(output.contains("二零二四年十月一日"))
    }
}
