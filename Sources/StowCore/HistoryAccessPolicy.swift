import Foundation

/// Pure rules for when opening history chrome needs device owner authentication.
enum HistoryAccessPolicy {
    static let idleMinuteChoices = [1, 5, 15, 30]
    static let defaultIdleMinutes = 5

    static func normalizedIdleMinutes(_ minutes: Int) -> Int {
        idleMinuteChoices.contains(minutes) ? minutes : defaultIdleMinutes
    }

    static func needsAuthentication(
        enabled: Bool,
        idleSeconds: TimeInterval,
        thresholdMinutes: Int,
        pendingAfterScreenLock: Bool
    ) -> Bool {
        guard enabled else { return false }
        if pendingAfterScreenLock { return true }
        let minutes = normalizedIdleMinutes(thresholdMinutes)
        return idleSeconds >= TimeInterval(minutes * 60)
    }
}
