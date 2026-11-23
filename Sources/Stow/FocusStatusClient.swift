import Foundation
import Intents

/// Reads whether macOS Focus is on. Named Focus modes are not available publicly.
@MainActor
final class FocusStatusClient {
    static let shared = FocusStatusClient()

    private(set) var authorizationStatus: INFocusStatusAuthorizationStatus = .notDetermined
    private(set) var isFocused: Bool?

    private init() {
        refresh()
    }

    func refresh() {
        let center = INFocusStatusCenter.default
        authorizationStatus = center.authorizationStatus
        switch authorizationStatus {
        case .authorized:
            isFocused = center.focusStatus.isFocused
        case .denied, .restricted:
            isFocused = nil
        case .notDetermined:
            isFocused = nil
        @unknown default:
            isFocused = nil
        }
    }

    func requestAuthorization() {
        INFocusStatusCenter.default.requestAuthorization { [weak self] status in
            Task { @MainActor in
                self?.authorizationStatus = status
                self?.refresh()
            }
        }
    }

    var authorizationTitle: String {
        switch authorizationStatus {
        case .authorized: "Focus status allowed"
        case .denied, .restricted: "Focus status denied"
        case .notDetermined: "Focus status not set"
        @unknown default: "Focus status unknown"
        }
    }
}
