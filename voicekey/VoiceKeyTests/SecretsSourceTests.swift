import ServiceManagement
import XCTest
@testable import VoiceKey

final class SecretsSourceTests: XCTestCase {
    private let testAccount = "VOICEKEY_TEST_SRC_ACCOUNT"
    private let previousService = Secrets.keychainServiceName

    override func setUp() {
        super.setUp()
        Secrets.keychainServiceName = "com.alston.VoiceKey.tests"
        _ = Secrets.keychainDelete(account: testAccount)
        unsetenv(testAccount)
    }

    override func tearDown() {
        _ = Secrets.keychainDelete(account: testAccount)
        unsetenv(testAccount)
        Secrets.keychainServiceName = previousService
        super.tearDown()
    }

    func testSourceMissing() {
        let src = Secrets.source(for: testAccount, configValue: "")
        XCTAssertEqual(src.kind, .missing)
    }

    func testSourceConfigWhenNoHigherLayer() {
        let src = Secrets.source(for: testAccount, configValue: "bundled-placeholder")
        XCTAssertEqual(src.kind, .config)
        XCTAssertFalse(src.usesHigherPriorityThanKeychain)
    }

    func testSourceProcessEnvironmentWins() {
        setenv(testAccount, "from-process", 1)
        let src = Secrets.source(for: testAccount, configValue: "from-config")
        XCTAssertEqual(src.kind, .processEnvironment)
        XCTAssertTrue(src.usesHigherPriorityThanKeychain)
    }

    func testKeychainReplaceAndDeleteWithoutRealKeys() {
        let placeholder = "test-only-placeholder"
        XCTAssertTrue(Secrets.keychainReplace(account: testAccount, value: placeholder))
        XCTAssertTrue(Secrets.keychainHasValue(account: testAccount))
        XCTAssertEqual(Secrets.source(for: testAccount, configValue: "").kind, .keychain)
        XCTAssertTrue(Secrets.keychainDelete(account: testAccount))
        XCTAssertFalse(Secrets.keychainHasValue(account: testAccount))
        XCTAssertEqual(Secrets.source(for: testAccount, configValue: "").kind, .missing)
    }

    func testReplaceRejectsEmptyValue() {
        XCTAssertFalse(Secrets.keychainReplace(account: testAccount, value: ""))
        XCTAssertFalse(Secrets.keychainHasValue(account: testAccount))
    }

    func testResolvedValueHonorsEditsBelowEnv() {
        let setVal = Secrets.resolvedValue(account: testAccount, configValue: "", edit: .set("candidate"))
        XCTAssertEqual(setVal, "candidate")
        let cleared = Secrets.resolvedValue(account: testAccount, configValue: "", edit: .clear)
        XCTAssertEqual(cleared, "")
    }

    func testLoginItemStatusMapping() {
        XCTAssertEqual(LoginItem.mapStatus(.enabled), .enabled)
        XCTAssertEqual(LoginItem.mapStatus(.notRegistered), .notRegistered)
        XCTAssertEqual(LoginItem.mapStatus(.requiresApproval), .requiresApproval)
        XCTAssertEqual(LoginItem.mapStatus(.notFound), .notFound)
    }
}
