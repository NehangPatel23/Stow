import Foundation

struct ExcludedApp: Codable, Equatable, Identifiable, Sendable {
    var bundleID: String
    var name: String
    var id: String { bundleID }
}

struct Preferences: Codable, Equatable, Sendable {
    var excludedApps: [ExcludedApp] = []
    var extraIgnoredPasteboardTypes: [String] = []
    var manuallyPaused: Bool = false
    var pauseUntil: Date? = nil
    var frontAppPauseBundleID: String? = nil
    var frontAppPauseName: String? = nil
    var frontAppPauseUntil: Date? = nil
    var ignoreNextCopy: Bool = false
    var showShortcutFooter: Bool = true
    var hasSeenFirstRun: Bool = false
    var hotkeyKeyCode: UInt32 = 8
    var hotkeyCarbonModifiers: UInt32 = 768
    var hotkeyLabel: String = "⌘⇧C"

    private static let defaultsKey = "Stow.Preferences"

    static func load(defaults: UserDefaults = .standard) -> Preferences {
        guard let data = defaults.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode(Preferences.self, from: data) else {
            return Preferences()
        }
        return decoded
    }

    func save(defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}
