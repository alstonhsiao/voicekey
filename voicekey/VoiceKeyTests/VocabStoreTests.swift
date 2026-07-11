import XCTest
@testable import VoiceKey

final class VocabStoreTests: XCTestCase {

    private let match = VocabMatchConfig(useTone: false, requireSurnameCharSame: false, minTermLen: 2)

    private func makeFile(_ dict: [String: Any]) -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).json")
        let data = try! JSONSerialization.data(withJSONObject: dict)
        try! data.write(to: url)
        return url
    }

    // MARK: - Layer 3 pinyin fuzzy

    func testFuzzyReplacesHomophoneName() {
        let url = makeFile(["people": ["蕭淳云", "周芷萓"], "companies": ["加模"]])
        let store = VocabStore(path: url, match: match)
        XCTAssertEqual(store.apply("請問蕭純云在嗎"), "請問蕭淳云在嗎")
        XCTAssertEqual(store.apply("周芷宜"), "周芷萓")
    }

    func testAlreadyCorrectIsUnchanged() {
        let url = makeFile(["people": ["蕭淳云"]])
        let store = VocabStore(path: url, match: match)
        XCTAssertEqual(store.apply("蕭淳云"), "蕭淳云")
    }

    func testUnrelatedTextUntouched() {
        let url = makeFile(["people": ["蕭淳云"]])
        let store = VocabStore(path: url, match: match)
        XCTAssertEqual(store.apply("今天天氣很好"), "今天天氣很好")
        XCTAssertEqual(store.apply(""), "")
    }

    func testOverridesLiteralReplacement() {
        let url = makeFile(["companies": ["加模"], "overrides": ["家模": "加模"]])
        let store = VocabStore(path: url, match: match)
        XCTAssertEqual(store.apply("家模公司"), "加模公司")
    }

    func testRequireSurnameCharSame() {
        // Precondition: 肖 and 蕭 are homophones (xiao) under the engine.
        XCTAssertEqual(PinyinEngine.syllables("肖淳云"), ["xiao", "chun", "yun"])

        let url = makeFile(["people": ["蕭淳云"]])
        let strict = VocabStore(path: url,
                                match: VocabMatchConfig(useTone: false, requireSurnameCharSame: true, minTermLen: 2))
        XCTAssertEqual(strict.apply("肖淳云"), "肖淳云")   // first char differs → not replaced
        XCTAssertEqual(strict.apply("蕭純云"), "蕭淳云")   // first char same → replaced

        let loose = VocabStore(path: url, match: match)
        XCTAssertEqual(loose.apply("肖淳云"), "蕭淳云")     // require=false → replaced
    }

    func testSttKeytermsIncludeTermsAndPeople() {
        let url = makeFile(["people": ["蕭淳云"], "terms": ["n8n", "API"]])
        let store = VocabStore(path: url, match: match)
        XCTAssertTrue(store.sttKeyterms.contains("蕭淳云"))
        XCTAssertTrue(store.sttKeyterms.contains("n8n"))
        XCTAssertTrue(store.sttKeyterms.contains("API"))
    }

    func testHotReloadPicksUpNewTerms() throws {
        let url = makeFile(["people": ["蕭淳云"]])
        let store = VocabStore(path: url, match: match)
        XCTAssertEqual(store.apply("周芷宜"), "周芷宜")   // not yet known

        let newData = try JSONSerialization.data(withJSONObject: ["people": ["蕭淳云", "周芷萓"]])
        try newData.write(to: url)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(5)],
                                              ofItemAtPath: url.path)
        store.maybeReload()
        XCTAssertEqual(store.apply("周芷宜"), "周芷萓")   // now known
    }

    func testCorruptFileKeepsPreviousData() throws {
        let url = makeFile(["people": ["蕭淳云"]])
        let store = VocabStore(path: url, match: match)
        try "{ not valid json".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(5)],
                                              ofItemAtPath: url.path)
        store.maybeReload()
        XCTAssertEqual(store.apply("蕭純云"), "蕭淳云")   // still works with old data
    }

    // MARK: - Layer 1

    func testLayer1Keyterms() {
        let url = makeFile(["keyterms": ["Zeabur", "n8n", "  ", "蕭淳云"]])
        let store = Layer1VocabStore(path: url)
        XCTAssertEqual(store.keyterms, ["Zeabur", "n8n", "蕭淳云"])   // blanks filtered
    }

    // MARK: - Layer 2

    func testLayer2BuildInjection() {
        let url = makeFile(["names": ["蕭淳云", "加模"], "corrections": ["蕭純云": "蕭淳云"]])
        let store = Layer2VocabStore(path: url)
        let injection = store.buildInjection()
        XCTAssertTrue(injection.contains("蕭淳云"))
        XCTAssertTrue(injection.contains("加模"))
        XCTAssertTrue(injection.contains("蕭純云→蕭淳云"))
    }

    func testLayer2EmptyInjection() {
        let url = makeFile(["names": [], "corrections": [:]])
        let store = Layer2VocabStore(path: url)
        XCTAssertEqual(store.buildInjection(), "")
    }

    // MARK: - STT keyterm merge

    func testMergeKeytermsUserVocabWinsOverStaticModeList() {
        // Mode already fills the limit by itself — user vocab must still get in.
        let modeTerms = (1...10).map { "static\($0)" }
        let merged = VocabStores.mergeKeyterms(vocabTerms: ["蕭淳云", "加模"],
                                               layer1Terms: ["Zeabur"],
                                               modeTerms: modeTerms,
                                               limit: 10)
        XCTAssertEqual(merged.count, 10)
        XCTAssertEqual(Array(merged.prefix(3)), ["蕭淳云", "加模", "Zeabur"])
        XCTAssertEqual(merged[3...].map { $0 }, (1...7).map { "static\($0)" })
    }

    func testMergeKeytermsDedupsAndSkipsEmpty() {
        let merged = VocabStores.mergeKeyterms(vocabTerms: ["n8n", ""],
                                               layer1Terms: ["n8n", "Zeabur"],
                                               modeTerms: ["Zeabur", "API"],
                                               limit: 10)
        XCTAssertEqual(merged, ["n8n", "Zeabur", "API"])
    }
}
