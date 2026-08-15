import XCTest
@testable import VoiceKey

final class MockHotkeyBackend: HotkeyBackend {
    var registered: [(id: UInt32, keyCode: UInt32, modifiers: UInt32)] = []
    var failOnCall: Int?
    private var callCount = 0

    func register(id: UInt32, keyCode: UInt32, modifiers: UInt32) -> Bool {
        callCount += 1
        if let failOnCall, callCount == failOnCall { return false }
        registered.append((id, keyCode, modifiers))
        return true
    }

    func unregister(id: UInt32) {
        registered.removeAll { $0.id == id }
    }

    func unregisterAll() {
        registered.removeAll()
    }
}

final class HotkeyAndKeyCodesTests: XCTestCase {

    func testF1ToF20RoundTrip() {
        for i in 1...20 {
            let name = "F\(i)"
            let code = KeyCodes.keyCode(for: name)
            XCTAssertNotNil(code, name)
            XCTAssertEqual(KeyCodes.functionKeyName(for: code!), name)
            XCTAssertTrue(KeyCodes.isSupportedFunctionKey(name))
            XCTAssertTrue(KeyCodes.isSupportedFunctionKey(name.lowercased()))
        }
    }

    func testNonFunctionKeyHasNoName() {
        XCTAssertNil(KeyCodes.functionKeyName(for: 0))
        XCTAssertFalse(KeyCodes.isSupportedFunctionKey("A"))
        XCTAssertFalse(KeyCodes.isSupportedFunctionKey("space"))
    }

    func testModifierCombinations() {
        let ctrl = KeyCodes.modifierFlags("ctrl")
        let shift = KeyCodes.modifierFlags("shift")
        let combo = KeyCodes.modifierFlags("ctrl+shift")
        XCTAssertEqual(combo, ctrl | shift)
        XCTAssertTrue(KeyCodes.hasSupportedModifier("cmd+option"))
        XCTAssertFalse(KeyCodes.hasSupportedModifier(""))
        XCTAssertFalse(KeyCodes.hasSupportedModifier("fn"))
    }

    func testDisplayString() {
        XCTAssertEqual(KeyCodes.displayString(key: "F1", modifier: "ctrl"), "⌃F1")
        XCTAssertEqual(KeyCodes.displayString(key: "F10", modifier: "ctrl+shift"), "⌃⇧F10")
    }

    func testDuplicateDetectionViaCoordinator() throws {
        let harness = SettingsTestHarness()
        XCTAssertThrowsError(try harness.coordinator.apply(
            .hotkeys(recordKey: "F1", recordModifier: "ctrl",
                     cycleKey: "F1", cycleModifier: "ctrl")
        )) { error in
            guard let applyError = error as? SettingsApplyError,
                  case .validation = applyError else {
                return XCTFail("expected validation, got \(error)")
            }
        }
        XCTAssertEqual(harness.hotkeyApplies, 0)
        XCTAssertEqual(harness.writes, 0)
    }

    func testSecondRegistrationFailureRestoresOld() {
        let backend = MockHotkeyBackend()
        let mgr = HotkeyManager(backend: backend)
        XCTAssertTrue(mgr.register(keyCode: 1, modifiers: 10, action: {}))
        XCTAssertTrue(mgr.register(keyCode: 2, modifiers: 10, action: {}))
        XCTAssertEqual(backend.registered.map(\.keyCode), [1, 2])

        backend.failOnCall = 4
        let ok = mgr.reconfigure([
            HotkeySpec(keyCode: 3, modifiers: 10, action: {}),
            HotkeySpec(keyCode: 4, modifiers: 10, action: {}),
        ])
        XCTAssertFalse(ok)
        XCTAssertEqual(backend.registered.map(\.keyCode), [1, 2])
        XCTAssertEqual(mgr.registeredCount, 2)
    }

    func testReconfigureSuccessReplacesBoth() {
        let backend = MockHotkeyBackend()
        let mgr = HotkeyManager(backend: backend)
        XCTAssertTrue(mgr.register(keyCode: 1, modifiers: 10, action: {}))
        XCTAssertTrue(mgr.register(keyCode: 2, modifiers: 10, action: {}))
        let ok = mgr.reconfigure([
            HotkeySpec(keyCode: 8, modifiers: 20, action: {}),
            HotkeySpec(keyCode: 9, modifiers: 20, action: {}),
        ])
        XCTAssertTrue(ok)
        XCTAssertEqual(backend.registered.map(\.keyCode), [8, 9])
    }
}
