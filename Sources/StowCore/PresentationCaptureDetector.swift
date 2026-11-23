import Foundation

/// Heuristic “screen is being captured or shared” detection from window metadata.
/// Pure inputs so unit tests do not need CoreGraphics.
enum PresentationCaptureDetector {
    struct WindowInfo: Equatable, Sendable {
        var ownerName: String
        var windowName: String
        var bundleID: String?
    }

    /// Bundle IDs whose on-screen windows often mean a share or capture session.
    static let captureBundleIDs: Set<String> = [
        "com.apple.screencaptureui",
        "com.apple.ScreenSharing",
        "com.apple.ReplayKit.RPBroadcastActivityExtension",
        "us.zoom.xos",
        "com.microsoft.teams",
        "com.microsoft.teams2",
        "com.microsoft.SkypeForBusiness",
        "com.webex.meetingmanager",
        "com.cisco.webexmeetingsapp",
        "com.hnc.Discord",
        "com.tinyspeck.slackmacgap",
        "com.loom.desktop",
        "com.obsproject.obs-studio",
    ]

    private static let titleHints = [
        "screen sharing",
        "sharing screen",
        "sharing your screen",
        "is sharing",
        "you're sharing",
        "you are sharing",
        "presenting",
        "screen recording",
        "recording screen",
        "stop sharing",
        "stop present",
        "share screen",
        "share your screen",
    ]

    static func isActive(windows: [WindowInfo]) -> Bool {
        for window in windows {
            if isCaptureWindow(window) {
                return true
            }
        }
        return false
    }

    static func isCaptureWindow(_ window: WindowInfo) -> Bool {
        let owner = window.ownerName.lowercased()
        let title = window.windowName.lowercased()
        let bundle = window.bundleID?.lowercased()

        if bundle == "com.apple.screencaptureui" {
            return true
        }
        if bundle == "com.apple.ScreenSharing".lowercased() {
            return true
        }
        if owner.contains("screenshot") || owner == "screencaptureui" {
            return true
        }
        if titleHints.contains(where: { title.contains($0) }) {
            return true
        }
        if let bundle, captureBundleIDs.contains(where: { $0.lowercased() == bundle }) {
            // Conferencing apps: only when the title looks like a share session.
            if bundle.hasPrefix("us.zoom") || bundle.contains("teams") || bundle.contains("webex")
                || bundle.contains("discord") || bundle.contains("slack") || bundle.contains("loom") {
                return title.contains("share") || title.contains("present") || title.contains("recording")
            }
            if bundle.contains("obs") {
                return true
            }
        }
        return false
    }
}
