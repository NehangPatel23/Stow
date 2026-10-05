import AppKit
import Carbon
import CoreGraphics

@MainActor
final class HotkeyController {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var tapSource: CFRunLoopSource?
    nonisolated(unsafe) private var tapPort: CFMachPort?
    nonisolated(unsafe) static var activeTap: CFMachPort?
    nonisolated(unsafe) private var watchedKey: UInt32 = 8
    nonisolated(unsafe) private var watchedModifiers: UInt32 = 768
    /// While Settings is listening for a new shortcut, the current one must reach the recorder.
    nonisolated(unsafe) static var passThrough = false
    private var lastFire = Date.distantPast
    var onPress: (() -> Void)?

    func register(keyCode: UInt32, modifiers: UInt32) -> Bool {
        unregisterHotKey()
        watchedKey = keyCode
        watchedModifiers = modifiers
        let carbon = registerCarbon(keyCode: keyCode, modifiers: modifiers)
        let tap = installTap()
        return carbon || tap
    }

    func unregister() {
        unregisterHotKey()
        removeTap()
        if let handler {
            RemoveEventHandler(handler)
            self.handler = nil
        }
    }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        return modifiers
    }

    static func label(keyCode: UInt16, flags: NSEvent.ModifierFlags, characters: String?) -> String {
        var label = ""
        if flags.contains(.control) { label += "⌃" }
        if flags.contains(.option) { label += "⌥" }
        if flags.contains(.shift) { label += "⇧" }
        if flags.contains(.command) { label += "⌘" }
        if let characters, let first = characters.first, !first.isWhitespace {
            label += String(first).uppercased()
        } else {
            label += fallbackName(for: keyCode)
        }
        return label
    }

    private static let signature = OSType(0x5354_4F57) // 'STOW'

    private func registerCarbon(keyCode: UInt32, modifiers: UInt32) -> Bool {
        installHandlerIfNeeded()
        var hotKey: EventHotKeyRef?
        let id = EventHotKeyID(signature: Self.signature, id: 1)
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            id,
            GetApplicationEventTarget(),
            0,
            &hotKey
        )
        guard status == noErr else { return false }
        self.hotKey = hotKey
        return true
    }

    private func unregisterHotKey() {
        if let hotKey {
            UnregisterEventHotKey(hotKey)
            self.hotKey = nil
        }
    }

    private func installHandlerIfNeeded() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let userData else { return noErr }
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr, hotKeyID.signature == HotkeyController.signature else {
                    return noErr
                }
                let controller = Unmanaged<HotkeyController>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        controller.fire()
                    }
                }
                return noErr
            },
            1,
            &spec,
            Unmanaged.passUnretained(self).toOpaque(),
            &handler
        )
    }

    /// ⌘⇧C is a Finder shortcut. A session event tap takes it before Finder does.
    private func installTap() -> Bool {
        guard tapPort == nil else { return true }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let locations: [CGEventTapLocation] = [.cghidEventTap, .cgSessionEventTap]
        for location in locations {
            guard let tap = CGEvent.tapCreate(
                tap: location,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: Self.tapCallback,
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            ) else { continue }
            guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else { continue }
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            tapPort = tap
            Self.activeTap = tap
            tapSource = source
            return true
        }
        return false
    }

    private func removeTap() {
        if let tapSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), tapSource, .commonModes)
            self.tapSource = nil
        }
        if let tapPort {
            CGEvent.tapEnable(tap: tapPort, enable: false)
            self.tapPort = nil
            Self.activeTap = nil
        }
    }

    private static let tapCallback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        let controller = Unmanaged<HotkeyController>.fromOpaque(userInfo).takeUnretainedValue()
        return controller.receive(event, type: type)
    }

    nonisolated private func receive(_ event: CGEvent, type: CGEventType) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tapPort {
                CGEvent.tapEnable(tap: tapPort, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }
        guard type == .keyDown else { return Unmanaged.passUnretained(event) }
        if Self.passThrough { return Unmanaged.passUnretained(event) }
        let code = UInt32(event.getIntegerValueField(.keyboardEventKeycode))
        let repeated = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        guard !repeated, code == watchedKey, modifiersMatch(event.flags) else {
            return Unmanaged.passUnretained(event)
        }
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?.fire()
            }
        }
        return nil
    }

    nonisolated private func modifiersMatch(_ flags: CGEventFlags) -> Bool {
        func wants(_ carbon: Int) -> Bool {
            watchedModifiers & UInt32(carbon) != 0
        }
        return flags.contains(.maskCommand) == wants(cmdKey)
            && flags.contains(.maskShift) == wants(shiftKey)
            && flags.contains(.maskAlternate) == wants(optionKey)
            && flags.contains(.maskControl) == wants(controlKey)
    }

    private func fire() {
        guard !Self.passThrough else { return }
        let now = Date()
        guard now.timeIntervalSince(lastFire) > 0.35 else { return }
        lastFire = now
        onPress?()
    }

    private static func fallbackName(for keyCode: UInt16) -> String {
        if let digit = KeyCode.digits.first(where: { $0.key == keyCode })?.value {
            return String(digit)
        }
        switch keyCode {
        case KeyCode.c: return "C"
        case KeyCode.v: return "V"
        case KeyCode.p: return "P"
        case KeyCode.s: return "S"
        default: return "Key"
        }
    }
}
