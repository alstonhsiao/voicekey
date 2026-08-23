import XCTest
@testable import VoiceKey

final class PasteTests: XCTestCase {
    func testActiveTargetSkipsActivationSettle() {
        XCTAssertEqual(Paste.activationSettleNanoseconds(targetWasActive: true), 0)
    }

    func testInactiveTargetKeepsActivationSettle() {
        XCTAssertEqual(Paste.activationSettleNanoseconds(targetWasActive: false), 120_000_000)
    }
}
