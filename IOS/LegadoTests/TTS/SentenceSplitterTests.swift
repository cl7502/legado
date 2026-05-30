import XCTest
@testable import Legado

final class SentenceSplitterTests: XCTestCase {
    var sut: SentenceSplitter!
    override func setUp() { sut = SentenceSplitter() }

    func test_hard_boundary_splits() {
        let result = sut.split("他来了。她离开了。", baseOffset: 0)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].text, "他来了。")
        XCTAssertEqual(result[1].text, "她离开了。")
    }

    func test_newline_splits() {
        let result = sut.split("第一句\n第二句", baseOffset: 0)
        XCTAssertEqual(result.count, 2)
    }

    func test_short_sentences_merged() {
        // "好。" 只有2字（含标点），应与下一句合并
        let result = sut.split("好。他继续说话。", baseOffset: 0)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].text, "好。他继续说话。")
    }

    func test_long_sentence_split_at_soft_boundary() {
        // 该句 > 80 字，应在软边界（逗号/分号）处切割，所有片段 ≤ 80 NSString 字符
        let long = "林峰看了看她，想起了往事，那是很多年前的事情了，具体是哪一年他已经记不清楚，只知道那时候天气很好，阳光照在树梢上，鸟儿在枝头唱歌，一切都是那么美好，仿佛时间静止了一般。"
        let result = sut.split(long, baseOffset: 0)
        XCTAssertTrue(result.count > 1, "超过80字的句子应被切割，实际 count=\(result.count)")
        result.forEach { XCTAssertLessThanOrEqual(($0.text as NSString).length, 80) }
    }

    func test_char_offset_is_correct() {
        let text = "第一句。第二句。"
        let result = sut.split(text, baseOffset: 100)
        XCTAssertEqual(result[0].charOffset, 100)
        // "第一句。" is 4 NSString characters, so second sentence starts at offset 104
        XCTAssertEqual(result[1].charOffset, 104)
    }

    func test_empty_string() {
        let result = sut.split("", baseOffset: 0)
        XCTAssertTrue(result.isEmpty)
    }
}
