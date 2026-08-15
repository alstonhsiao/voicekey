import XCTest
@testable import VoiceKey

final class ConfigLocalWriterTests: XCTestCase {
    private var dir: URL!
    private var localURL: URL!
    private var writer: ConfigLocalWriter!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceKeyWriterTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        localURL = dir.appendingPathComponent("config.local.json")
        writer = ConfigLocalWriter(localURL: localURL, bundledJSON: Self.sampleBundled())
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    func testNestedDeepMergeKeepsExistingOverride() throws {
        try writer.apply([
            "vocab": ["enabled": false],
            "recording": ["sample_rate": 48000],
        ])
        let candidate = try writer.apply(["vocab": ["stt_keyterm_limit": 5]])
        XCTAssertEqual(candidate.vocab.sttKeytermLimit, 5)
        XCTAssertFalse(candidate.vocab.enabled)
        XCTAssertEqual(candidate.recording.sampleRate, 48000)

        let local = try readLocal()
        let vocab = local["vocab"] as? [String: Any]
        XCTAssertEqual(vocab?["enabled"] as? Bool, false)
        XCTAssertEqual(vocab?["stt_keyterm_limit"] as? Int, 5)
        XCTAssertEqual((local["recording"] as? [String: Any])?["sample_rate"] as? Int, 48000)
    }

    func testDoesNotWriteBundledConfig() throws {
        try writer.apply(["default_mode_id": "casual"])
        let local = try readLocal()
        XCTAssertEqual(local["default_mode_id"] as? String, "casual")
        XCTAssertNil(local["modes"])
        XCTAssertNil(local["api"])
    }

    func testCorruptLocalRefusesOverwrite() throws {
        try Data("{not-json".utf8).write(to: localURL)
        XCTAssertThrowsError(try writer.apply(["default_mode_id": "casual"])) { error in
            guard let applyError = error as? SettingsApplyError,
                  case .corruptLocal = applyError else {
                return XCTFail("expected corruptLocal, got \(error)")
            }
        }
        let leftover = try String(contentsOf: localURL, encoding: .utf8)
        XCTAssertEqual(leftover, "{not-json")
    }

    func testCandidateValidationFailureDoesNotWrite() throws {
        try writer.apply(["default_mode_id": "casual"])
        let before = try Data(contentsOf: localURL)
        XCTAssertThrowsError(try writer.apply(["api": ["provider": "nope"]]))
        let after = try Data(contentsOf: localURL)
        XCTAssertEqual(before, after)
    }

    func testRollbackRestoresBytes() throws {
        try writer.apply(["default_mode_id": "casual"])
        let original = try Data(contentsOf: localURL)
        let commit = try writer.prepare(["default_mode_id": "direct"])
        try writer.write(commit)
        XCTAssertEqual(try readLocal()["default_mode_id"] as? String, "direct")
        try writer.rollback(commit)
        XCTAssertEqual(try Data(contentsOf: localURL), original)
    }

    func testRollbackRemovesFileWhenOriginallyMissing() throws {
        XCTAssertFalse(FileManager.default.fileExists(atPath: localURL.path))
        let commit = try writer.prepare(["default_mode_id": "casual"])
        try writer.write(commit)
        XCTAssertTrue(FileManager.default.fileExists(atPath: localURL.path))
        try writer.rollback(commit)
        XCTAssertFalse(FileManager.default.fileExists(atPath: localURL.path))
    }

    func testWrittenFileIsPrettyJSONObject() throws {
        try writer.apply(["default_mode_id": "pro"])
        let text = try String(contentsOf: localURL, encoding: .utf8)
        XCTAssertTrue(text.contains("default_mode_id"))
        XCTAssertFalse(text.contains("XAI_API_KEY"))
        XCTAssertFalse(text.lowercased().contains("sk-"))
    }

    private func readLocal() throws -> [String: Any] {
        let data = try Data(contentsOf: localURL)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    static func sampleBundled() -> [String: Any] {
        [
            "default_mode_id": "pro",
            "modes": [
                ["id": "pro", "name": "專業"],
                ["id": "casual", "name": "一般對話"],
                ["id": "direct", "name": "直接轉錄"],
            ],
            "api": [
                "provider": "grok",
                "grok": ["api_key": "", "model": "grok-stt", "endpoint": "https://api.x.ai/v1/stt"],
                "llm_correction": [
                    "provider": "cerebras",
                    "cerebras": ["api_key": "", "model": "gpt-oss-120b", "max_tokens": 2048],
                ],
            ],
            "recording": ["sample_rate": 16000, "channels": 1, "input_device": NSNull()],
            "hotkey": [
                "record_key": "F1", "record_modifier": "ctrl",
                "mode_cycle_key": "F10", "mode_cycle_modifier": "ctrl",
            ],
            "vocab": ["enabled": true, "file": "user_vocab.json", "stt_keyterm_limit": 10],
        ]
    }
}
