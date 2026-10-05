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
    var keepPanelOpen: Bool = false
    var compactRows: Bool = false
    var hasSeenFirstRun: Bool = false
    /// Days to keep unpinned text-like clips. `0` means keep forever.
    var textRetentionDays: Int = 0
    /// Days to keep unpinned image clips. `0` means keep forever.
    var imageRetentionDays: Int = 0
    /// When on, typing a marked snippet abbreviation expands it. Unmarked snippets stay inert.
    var abbreviationExpansionEnabled: Bool = true
    var hotkeyKeyCode: UInt32 = 8
    var hotkeyCarbonModifiers: UInt32 = 768
    var hotkeyLabel: String = "⌘⇧C"

    /// Folder sync is off until the user enables it.
    var syncEnabled: Bool = false
    var syncHistory: Bool = true
    var syncSnippets: Bool = true
    /// Security-scoped bookmark for the chosen sync folder.
    var syncFolderBookmark: Data? = nil
    /// Display path shown in Settings (bookmark is the source of truth).
    var syncFolderDisplayPath: String? = nil

    private static let defaultsKey = "Stow.Preferences"

    enum CodingKeys: String, CodingKey {
        case excludedApps, extraIgnoredPasteboardTypes, manuallyPaused, pauseUntil
        case frontAppPauseBundleID, frontAppPauseName, frontAppPauseUntil, ignoreNextCopy
        case showShortcutFooter, keepPanelOpen, compactRows, hasSeenFirstRun
        case textRetentionDays, imageRetentionDays, abbreviationExpansionEnabled
        case hotkeyKeyCode, hotkeyCarbonModifiers, hotkeyLabel
        case syncEnabled, syncHistory, syncSnippets, syncFolderBookmark, syncFolderDisplayPath
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        excludedApps = try container.decodeIfPresent([ExcludedApp].self, forKey: .excludedApps) ?? []
        extraIgnoredPasteboardTypes = try container.decodeIfPresent([String].self, forKey: .extraIgnoredPasteboardTypes) ?? []
        manuallyPaused = try container.decodeIfPresent(Bool.self, forKey: .manuallyPaused) ?? false
        pauseUntil = try container.decodeIfPresent(Date.self, forKey: .pauseUntil)
        frontAppPauseBundleID = try container.decodeIfPresent(String.self, forKey: .frontAppPauseBundleID)
        frontAppPauseName = try container.decodeIfPresent(String.self, forKey: .frontAppPauseName)
        frontAppPauseUntil = try container.decodeIfPresent(Date.self, forKey: .frontAppPauseUntil)
        ignoreNextCopy = try container.decodeIfPresent(Bool.self, forKey: .ignoreNextCopy) ?? false
        showShortcutFooter = try container.decodeIfPresent(Bool.self, forKey: .showShortcutFooter) ?? true
        keepPanelOpen = try container.decodeIfPresent(Bool.self, forKey: .keepPanelOpen) ?? false
        compactRows = try container.decodeIfPresent(Bool.self, forKey: .compactRows) ?? false
        hasSeenFirstRun = try container.decodeIfPresent(Bool.self, forKey: .hasSeenFirstRun) ?? false
        textRetentionDays = Self.normalizedRetention(
            try container.decodeIfPresent(Int.self, forKey: .textRetentionDays) ?? 0
        )
        imageRetentionDays = Self.normalizedRetention(
            try container.decodeIfPresent(Int.self, forKey: .imageRetentionDays) ?? 0
        )
        abbreviationExpansionEnabled = try container.decodeIfPresent(Bool.self, forKey: .abbreviationExpansionEnabled) ?? true
        hotkeyKeyCode = try container.decodeIfPresent(UInt32.self, forKey: .hotkeyKeyCode) ?? 8
        hotkeyCarbonModifiers = try container.decodeIfPresent(UInt32.self, forKey: .hotkeyCarbonModifiers) ?? 768
        hotkeyLabel = try container.decodeIfPresent(String.self, forKey: .hotkeyLabel) ?? "⌘⇧C"
        syncEnabled = try container.decodeIfPresent(Bool.self, forKey: .syncEnabled) ?? false
        syncHistory = try container.decodeIfPresent(Bool.self, forKey: .syncHistory) ?? true
        syncSnippets = try container.decodeIfPresent(Bool.self, forKey: .syncSnippets) ?? true
        syncFolderBookmark = try container.decodeIfPresent(Data.self, forKey: .syncFolderBookmark)
        syncFolderDisplayPath = try container.decodeIfPresent(String.self, forKey: .syncFolderDisplayPath)
    }

    private static let retentionChoices = [0, 1, 7, 14, 30, 90, 365]

    private static func normalizedRetention(_ days: Int) -> Int {
        retentionChoices.contains(days) ? days : 0
    }

    var canEnableSync: Bool {
        syncFolderBookmark != nil && SyncKeychain.hasPassphrase
    }

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
