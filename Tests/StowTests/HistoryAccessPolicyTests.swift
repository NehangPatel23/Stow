import XCTest

final class HistoryAccessPolicyTests: XCTestCase {
    func testDisabledNeverRequiresAuth() {
        XCTAssertFalse(
            HistoryAccessPolicy.needsAuthentication(
                enabled: false,
                idleSeconds: 10_000,
                thresholdMinutes: 5,
                pendingAfterScreenLock: true
            )
        )
    }

    func testIdleBelowThresholdDoesNotRequire() {
        XCTAssertFalse(
            HistoryAccessPolicy.needsAuthentication(
                enabled: true,
                idleSeconds: 60,
                thresholdMinutes: 5,
                pendingAfterScreenLock: false
            )
        )
    }

    func testIdleAtThresholdRequires() {
        XCTAssertTrue(
            HistoryAccessPolicy.needsAuthentication(
                enabled: true,
                idleSeconds: 5 * 60,
                thresholdMinutes: 5,
                pendingAfterScreenLock: false
            )
        )
    }

    func testScreenLockPendingRequiresEvenWhenActive() {
        XCTAssertTrue(
            HistoryAccessPolicy.needsAuthentication(
                enabled: true,
                idleSeconds: 1,
                thresholdMinutes: 5,
                pendingAfterScreenLock: true
            )
        )
    }

    func testNormalizedIdleMinutes() {
        XCTAssertEqual(HistoryAccessPolicy.normalizedIdleMinutes(5), 5)
        XCTAssertEqual(HistoryAccessPolicy.normalizedIdleMinutes(99), HistoryAccessPolicy.defaultIdleMinutes)
    }
}
