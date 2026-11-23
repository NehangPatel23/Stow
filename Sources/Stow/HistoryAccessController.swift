import AppKit
import Foundation
import LocalAuthentication

/// Gates panel/library open with Touch ID / password after idle or screen lock.
@MainActor
final class HistoryAccessController {
    private(set) var pendingAfterScreenLock = false
    private var evaluating = false

    func noteScreenLocked() {
        pendingAfterScreenLock = true
    }

    static func secondsSinceLastInput() -> TimeInterval {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .null)
    }

    func isHistoryLocked(preferences: Preferences) -> Bool {
        HistoryAccessPolicy.needsAuthentication(
            enabled: preferences.touchIDAfterIdleEnabled,
            idleSeconds: Self.secondsSinceLastInput(),
            thresholdMinutes: preferences.idleLockMinutes,
            pendingAfterScreenLock: pendingAfterScreenLock
        )
    }

    /// Returns true when the caller may open history UI.
    func allowOpeningHistory(preferences: Preferences) async -> Bool {
        guard isHistoryLocked(preferences: preferences) else { return true }
        guard !evaluating else { return false }
        evaluating = true
        defer { evaluating = false }

        let allowed = await authenticate()
        if allowed {
            pendingAfterScreenLock = false
        }
        return allowed
    }

    private func authenticate() async -> Bool {
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            // No authentication available on this Mac — don't brick history.
            return true
        }
        do {
            return try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Unlock Stow to view clipboard history"
            )
        } catch {
            return false
        }
    }
}
