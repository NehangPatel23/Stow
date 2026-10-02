import Foundation

/// Apps that should receive plain text. Secure-field detection needs Accessibility
/// and stays in the app target.
enum PasteTarget {
    static let plainTextBundleIDs: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "dev.warp.Warp-Stable",
        "com.mitchellh.ghostty",
        "net.kovidgoyal.kitty",
        "com.github.wez.wezterm",
        "com.apple.dt.Xcode",
        "com.microsoft.VSCode",
        "com.microsoft.VSCodeInsiders",
        "com.todesktop.230313mzl4w4u92",
        "com.sublimetext.3",
        "com.sublimetext.4",
        "com.panic.Nova",
        "com.barebones.bbedit",
        "com.macromates.TextMate",
        "dev.zed.Zed",
        "com.exafunction.windsurf",
    ]

    static let plainTextNameFragments = [
        "terminal", "iterm", "warp", "ghostty", "kitty", "wezterm",
        "xcode", "visual studio code", "sublime", "nova", "bbedit",
        "textmate", "zed", "windsurf", "cursor",
    ]

    static func prefersPlainText(bundleID: String?, appName: String?) -> Bool {
        if let bundleID {
            if plainTextBundleIDs.contains(bundleID) { return true }
            if bundleID.hasPrefix("com.jetbrains.") { return true }
            if bundleID.hasPrefix("com.googlecode.iterm2") { return true }
        }
        let name = (appName ?? "").lowercased()
        return plainTextNameFragments.contains { name.contains($0) }
    }
}
