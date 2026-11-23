import AppKit

enum MotionPolicy {
    @MainActor
    static var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    @MainActor
    static func duration(_ preferred: TimeInterval) -> TimeInterval {
        reduceMotion ? 0 : preferred
    }
}
