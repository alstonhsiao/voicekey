import XCTest
@testable import WhisperVoice

final class PinyinEngineTests: XCTestCase {

    /// Golden values verified against pypinyin lazy_pinyin(style=NORMAL).
    func testGoldenPinyinMatchesPypinyin() {
        XCTAssertEqual(PinyinEngine.syllables("蕭淳云"), ["xiao", "chun", "yun"])
        XCTAssertEqual(PinyinEngine.syllables("蕭純云"), ["xiao", "chun", "yun"])
        XCTAssertEqual(PinyinEngine.syllables("周芷萓"), ["zhou", "zhi", "yi"])
        XCTAssertEqual(PinyinEngine.syllables("加模"), ["jia", "mo"])
        XCTAssertEqual(PinyinEngine.syllables("家模"), ["jia", "mo"])
    }

    /// The whole fuzzy mechanism relies on homophones producing identical syllables.
    func testHomophonesProduceSameSyllables() {
        XCTAssertEqual(PinyinEngine.syllables("蕭純云"), PinyinEngine.syllables("蕭淳云"))
        XCTAssertEqual(PinyinEngine.syllables("家模"), PinyinEngine.syllables("加模"))
    }

    func testNonChinesePassesThrough() {
        XCTAssertEqual(PinyinEngine.syllables("Tahoe"), ["Tahoe"])
    }
}
