import XCTest
@testable import VoiceKey

final class ModePreferenceStoreTests: XCTestCase {
    private var suiteName: String!
    private var store: ModePreferenceStore!
    private var modes: [Mode]!

    override func setUp() {
        super.setUp()
        suiteName = "VoiceKeyTests.ModePrefs.\(UUID().uuidString)"
        store = ModePreferenceStore(suiteName: suiteName)
        store.removeAll()
        modes = [
            Mode(raw: ["id": "pro", "name": "專業"])!,
            Mode(raw: ["id": "casual", "name": "一般對話"])!,
            Mode(raw: ["id": "direct", "name": "直接轉錄"])!,
        ]
    }

    override func tearDown() {
        store.removeAll()
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testFirstLaunchUsesDefaultPro() {
        XCTAssertTrue(store.rememberLastMode)
        XCTAssertNil(store.lastModeId)
        XCTAssertEqual(store.startupModeId(modes: modes, defaultId: "pro"), "pro")
    }

    func testValidLastWins() {
        store.rememberLastMode = true
        store.lastModeId = "casual"
        XCTAssertEqual(store.startupModeId(modes: modes, defaultId: "pro"), "casual")
    }

    func testDeletedLastFallsBackToDefault() {
        store.rememberLastMode = true
        store.lastModeId = "gone"
        XCTAssertEqual(store.startupModeId(modes: modes, defaultId: "pro"), "pro")
    }

    func testRememberOffUsesDefault() {
        store.rememberLastMode = false
        store.lastModeId = "casual"
        XCTAssertEqual(store.startupModeId(modes: modes, defaultId: "pro"), "pro")
    }

    func testInvalidDefaultFallsBackToFirstMode() {
        store.rememberLastMode = false
        XCTAssertEqual(store.startupModeId(modes: modes, defaultId: "missing"), "pro")
    }

    func testNoteCurrentModeOnlyWhenRemembering() {
        store.rememberLastMode = true
        store.noteCurrentMode("casual")
        XCTAssertEqual(store.lastModeId, "casual")

        store.rememberLastMode = false
        store.noteCurrentMode("direct")
        XCTAssertEqual(store.lastModeId, "casual")
    }

    func testRememberDefaultsTrueWhenUnset() {
        store.removeAll()
        XCTAssertTrue(store.rememberLastMode)
    }
}
