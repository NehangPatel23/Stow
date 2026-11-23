import AppKit

/// Remembers which display the quick panel last used.
enum PanelDisplayMemory {
    static func displayID(for screen: NSScreen) -> UInt32? {
        let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        return number?.uint32Value
    }

    static func screen(forDisplayID id: UInt32?) -> NSScreen? {
        guard let id else { return nil }
        return NSScreen.screens.first { displayID(for: $0) == id }
    }

    /// Prefer the remembered display when it is still connected; otherwise the fallback.
    static func preferredScreen(savedDisplayID: UInt32?, fallback: NSScreen?) -> NSScreen? {
        screen(forDisplayID: savedDisplayID) ?? fallback
    }
}
