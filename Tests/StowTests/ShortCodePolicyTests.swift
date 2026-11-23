import XCTest

final class ShortCodePolicyTests: XCTestCase {
    func testSixDigitMatchesWholeCopyOnly() {
        XCTAssertTrue(ShortCodePolicy.matches(text: "123456", kind: .text, pattern: .sixDigit))
        XCTAssertTrue(ShortCodePolicy.matches(text: " 123456 ", kind: .text, pattern: .sixDigit))
        XCTAssertFalse(ShortCodePolicy.matches(text: "12345", kind: .text, pattern: .sixDigit))
        XCTAssertFalse(ShortCodePolicy.matches(text: "1234567", kind: .text, pattern: .sixDigit))
        XCTAssertFalse(ShortCodePolicy.matches(text: "code 123456", kind: .text, pattern: .sixDigit))
        XCTAssertFalse(ShortCodePolicy.matches(text: "123\n456", kind: .text, pattern: .sixDigit))
        XCTAssertFalse(ShortCodePolicy.matches(text: "123456", kind: .image, pattern: .sixDigit))
    }

    func testFourToEightDigitRange() {
        XCTAssertTrue(ShortCodePolicy.matches(text: "1234", kind: .text, pattern: .fourToEightDigit))
        XCTAssertTrue(ShortCodePolicy.matches(text: "12345678", kind: .text, pattern: .fourToEightDigit))
        XCTAssertFalse(ShortCodePolicy.matches(text: "123", kind: .text, pattern: .fourToEightDigit))
        XCTAssertFalse(ShortCodePolicy.matches(text: "123456789", kind: .text, pattern: .fourToEightDigit))
    }

    func testLifetimeNormalization() {
        XCTAssertEqual(ShortCodePolicy.normalizedLifetimeSeconds(60), 60)
        XCTAssertEqual(ShortCodePolicy.normalizedLifetimeSeconds(99), ShortCodePolicy.defaultLifetimeSeconds)
        let created = Date(timeIntervalSince1970: 1_000)
        let expires = ShortCodePolicy.expiresAt(createdAt: created, lifetimeSeconds: 60)
        XCTAssertEqual(expires.timeIntervalSince1970, 1_060)
    }
}
