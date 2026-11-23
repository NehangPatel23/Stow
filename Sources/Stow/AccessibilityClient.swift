import ApplicationServices
import AppKit

enum AccessibilityClient {
    static func isTrusted(prompt: Bool) -> Bool {
        _ = prompt
        return AXIsProcessTrusted()
    }

    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Accessibility granted while Stow is running applies only to the next launch.
    static func relaunch() {
        let path = Bundle.main.bundleURL.path
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 0.4; open \"\(path)\""]
        try? process.run()
        NSApp.terminate(nil)
    }
}

enum FocusedField {
    static func isSecureTextField(pid: pid_t) -> Bool {
        guard AccessibilityClient.isTrusted(prompt: false) else { return false }
        guard let element = focusedElement(pid: pid) else { return false }
        return isSecure(element)
    }

    fileprivate static func focusedElement(pid: pid_t) -> AXUIElement? {
        let application = AXUIElementCreateApplication(pid)
        return copyElement(application, attribute: kAXFocusedUIElementAttribute as CFString)
    }

    fileprivate static func isSecure(_ element: AXUIElement) -> Bool {
        if copyString(element, attribute: kAXRoleAttribute as CFString) == "AXSecureTextField" {
            return true
        }
        if copyString(element, attribute: kAXSubroleAttribute as CFString) == "AXSecureTextField" {
            return true
        }
        return false
    }

    fileprivate static func copyElement(_ element: AXUIElement, attribute: CFString) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success, let value else {
            return nil
        }
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    fileprivate static func copyString(_ element: AXUIElement, attribute: CFString) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return nil }
        return value as? String
    }
}

/// Selected text in the front app’s focused field (for the selection chip).
enum FocusedSelection {
    struct Result: Equatable, Sendable {
        var text: String
        var isSecure: Bool
        /// Screen coordinates (AppKit bottom-left origin), when available.
        var bounds: CGRect?
    }

    static func read(pid: pid_t) -> Result? {
        guard AccessibilityClient.isTrusted(prompt: false) else { return nil }
        guard let element = FocusedField.focusedElement(pid: pid) else { return nil }
        let secure = FocusedField.isSecure(element)
        let raw = FocusedField.copyString(element, attribute: kAXSelectedTextAttribute as CFString)
        let text = SelectionChipPolicy.normalizedSelection(raw) ?? ""
        let bounds = text.isEmpty ? nil : selectionBounds(element: element)
        return Result(text: text, isSecure: secure, bounds: bounds)
    }

    private static func selectionBounds(element: AXUIElement) -> CGRect? {
        var rangeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeValue) == .success,
              let rangeValue else {
            return nil
        }
        var boundsValue: CFTypeRef?
        let status = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeValue,
            &boundsValue
        )
        guard status == .success, let boundsValue else { return nil }
        guard CFGetTypeID(boundsValue) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(boundsValue as! AXValue, .cgRect, &rect) else { return nil }
        // AX uses top-left origin; AppKit uses bottom-left relative to the global desktop.
        let desktopHeight = NSScreen.screens.map(\.frame.maxY).max() ?? 0
        let flippedY = desktopHeight - rect.origin.y - rect.height
        return CGRect(x: rect.origin.x, y: flippedY, width: rect.width, height: rect.height)
    }
}
