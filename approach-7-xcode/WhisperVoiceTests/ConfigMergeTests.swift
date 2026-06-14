import XCTest
@testable import WhisperVoice

final class ConfigMergeTests: XCTestCase {

    func testDeepMergeOverridesScalarsAndRecursesDicts() {
        let base: [String: Any] = [
            "api": ["provider": "grok", "temperature": 0.0,
                    "grok": ["model": "grok-stt", "endpoint": "x"]],
            "vocab": ["enabled": false, "match": ["use_tone": false, "min_term_len": 2]],
        ]
        let override: [String: Any] = [
            "api": ["provider": "openai"],                 // scalar override, deep
            "vocab": ["enabled": true, "match": ["min_term_len": 3]], // nested deep merge
        ]
        let merged = ConfigLoader.deepMerge(base, override)

        let api = merged["api"] as? [String: Any]
        XCTAssertEqual(api?["provider"] as? String, "openai")
        XCTAssertEqual(api?["temperature"] as? Double, 0.0)            // preserved
        XCTAssertNotNil(api?["grok"])                                  // preserved subtree

        let vocab = merged["vocab"] as? [String: Any]
        XCTAssertEqual(vocab?["enabled"] as? Bool, true)
        let match = vocab?["match"] as? [String: Any]
        XCTAssertEqual(match?["min_term_len"] as? Int, 3)             // overridden
        XCTAssertEqual(match?["use_tone"] as? Bool, false)           // preserved
    }

    func testDeepMergeReplacesArrays() {
        let base: [String: Any] = ["modes": [["id": "a"], ["id": "b"]]]
        let override: [String: Any] = ["modes": [["id": "c"]]]
        let merged = ConfigLoader.deepMerge(base, override)
        let modes = merged["modes"] as? [[String: Any]]
        XCTAssertEqual(modes?.count, 1)
        XCTAssertEqual(modes?.first?["id"] as? String, "c")
    }

    func testValidateRejectsBadProvider() {
        let bad: [String: Any] = [
            "modes": [["id": "x", "name": "X"]],
            "api": ["provider": "nope"],
            "recording": ["sample_rate": 16000, "channels": 1],
        ]
        XCTAssertThrowsError(try ConfigLoader.validate(bad))
    }

    func testValidateRejectsEmptyModes() {
        let bad: [String: Any] = [
            "modes": [],
            "api": ["provider": "grok"],
            "recording": ["sample_rate": 16000, "channels": 1],
        ]
        XCTAssertThrowsError(try ConfigLoader.validate(bad))
    }

    func testValidateRejectsNonIntSampleRate() {
        let bad: [String: Any] = [
            "modes": [["id": "x", "name": "X"]],
            "api": ["provider": "grok"],
            "recording": ["sample_rate": "16000", "channels": 1],
        ]
        XCTAssertThrowsError(try ConfigLoader.validate(bad))
    }

    func testValidateAcceptsGoodConfig() {
        let good: [String: Any] = [
            "modes": [["id": "direct", "name": "直接"]],
            "api": ["provider": "grok"],
            "recording": ["sample_rate": 16000, "channels": 1, "input_device": ["A", "B"]],
        ]
        XCTAssertNoThrow(try ConfigLoader.validate(good))
    }

    func testInputDeviceSpecParsing() {
        if case .systemDefault = InputDeviceSpec(nil) {} else { XCTFail("nil → default") }
        if case .index(let i) = InputDeviceSpec(3) { XCTAssertEqual(i, 3) } else { XCTFail("int") }
        if case .name(let n) = InputDeviceSpec("Mic") { XCTAssertEqual(n, "Mic") } else { XCTFail("string") }
        if case .candidates(let c) = InputDeviceSpec(["A", "B"]) { XCTAssertEqual(c, ["A", "B"]) } else { XCTFail("array") }
    }

    func testBundledConfigLoads() throws {
        // Bundled config.json should load + validate via the real loader.
        let cfg = try ConfigLoader.load()
        XCTAssertGreaterThanOrEqual(cfg.modes.count, 1)
        XCTAssertTrue(["grok", "openai", "groq"].contains(cfg.api.provider))
    }
}
