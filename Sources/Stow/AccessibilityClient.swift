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
        let application = AXUIElementCreateApplication(pid)
        guard let element = copyElement(application, attribute: kAXFocusedUIElementAttribute as CFString) else {
            return false
        }
        if copyString(element, attribute: kAXRoleAttribute as CFString) == "AXSecureTextField" {
            return true
        }
        if copyString(element, attribute: kAXSubroleAttribute as CFString) == "AXSecureTextField" {
            return true
        }
        return false
    }

    private static func copyElement(_ element: AXUIElement, attribute: CFString) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success, let value else {
            return nil
        }
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private static func copyString(_ element: AXUIElement, attribute: CFString) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return nil }
        return value as? String
    }
}
