import AppKit
import Carbon

/// Global Carbon hotkeys for named slots. Uses Control-Option digits by default (no event tap).
@MainActor
final class SlotHotkeyController {
    private var hotKeys: [UInt32: EventHotKeyRef] = [:]
    private var handler: EventHandlerRef?
    private var lastFire = Date.distantPast
    /// Slot index (1…n) that just fired.
    var onPaste: ((Int) -> Void)?

    private static let signature = OSType(0x5354_534C) // 'STSL'
    nonisolated(unsafe) private static var active: SlotHotkeyController?

    /// Registers paste hotkeys for every slot (empty slots still claim their shortcut).
    func register(slots: [ClipSlot]) {
        unregister()
        Self.active = self
        installHandlerIfNeeded()
        for slot in slots {
            _ = registerOne(
                id: UInt32(slot.index),
                keyCode: slot.hotkeyKeyCode,
                modifiers: slot.hotkeyCarbonModifiers
            )
        }
    }

    func unregister() {
        for (_, hotKey) in hotKeys {
            UnregisterEventHotKey(hotKey)
        }
        hotKeys.removeAll()
        if let handler {
            RemoveEventHandler(handler)
            self.handler = nil
        }
        if Self.active === self {
            Self.active = nil
        }
    }

    private func registerOne(id: UInt32, keyCode: UInt32, modifiers: UInt32) -> Bool {
        var hotKey: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKey
        )
        guard status == noErr, let hotKey else { return false }
        hotKeys[id] = hotKey
        return true
    }

    private func installHandlerIfNeeded() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            Self.eventHandler,
            1,
            &spec,
            nil,
            &handler
        )
    }

    private static let eventHandler: EventHandlerUPP = { _, event, _ in
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
        guard status == noErr, hotKeyID.signature == SlotHotkeyController.signature else {
            return noErr
        }
        let index = Int(hotKeyID.id)
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                guard let controller = SlotHotkeyController.active else { return }
                controller.fire(index: index)
            }
        }
        return noErr
    }

    private func fire(index: Int) {
        guard !HotkeyController.passThrough else { return }
        let now = Date()
        guard now.timeIntervalSince(lastFire) > 0.35 else { return }
        lastFire = now
        onPaste?(index)
    }
}
