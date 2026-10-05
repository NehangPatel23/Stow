import AppKit
import Carbon
import CoreGraphics

/// Expands opt-in snippet abbreviations while typing. Only marked snippets expand.
@MainActor
final class AbbreviationExpander {
    nonisolated(unsafe) static var activeTap: CFMachPort?
    nonisolated(unsafe) private static var suppress = false

    private var tapSource: CFRunLoopSource?
    nonisolated(unsafe) private var tapPort: CFMachPort?
    nonisolated(unsafe) private let bufferLock = NSLock()
    nonisolated(unsafe) private var buffer = ""

    /// Lowercased abbreviation → expansion text.
    var expansions: () -> [String: String] = { [:] }
    /// Return false in Stow itself, secure fields, or when the feature is off.
    var shouldExpand: () -> Bool = { false }
    var noteOwnWrite: (() -> Void)?

    func start() {
        guard tapPort == nil else { return }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        for location: CGEventTapLocation in [.cgSessionEventTap, .cghidEventTap] {
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
            return
        }
    }

    func stop() {
        if let tapSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), tapSource, .commonModes)
            self.tapSource = nil
        }
        if let tapPort {
            CGEvent.tapEnable(tap: tapPort, enable: false)
            self.tapPort = nil
            Self.activeTap = nil
        }
        bufferLock.withLock { buffer = "" }
    }

    private static let tapCallback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        let expander = Unmanaged<AbbreviationExpander>.fromOpaque(userInfo).takeUnretainedValue()
        return expander.receive(event, type: type)
    }

    nonisolated private func receive(_ event: CGEvent, type: CGEventType) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tapPort {
                CGEvent.tapEnable(tap: tapPort, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }
        guard type == .keyDown else { return Unmanaged.passUnretained(event) }
        if Self.suppress || HotkeyController.passThrough {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        if flags.contains(.maskCommand) || flags.contains(.maskControl) || flags.contains(.maskAlternate) {
            bufferLock.withLock { buffer = "" }
            return Unmanaged.passUnretained(event)
        }

        if keyCode == KeyCode.escape || keyCode == KeyCode.up || keyCode == KeyCode.down {
            bufferLock.withLock { buffer = "" }
            return Unmanaged.passUnretained(event)
        }

        if keyCode == KeyCode.delete {
            bufferLock.withLock {
                if !buffer.isEmpty { buffer.removeLast() }
            }
            return Unmanaged.passUnretained(event)
        }

        guard let nsEvent = NSEvent(cgEvent: event),
              let characters = nsEvent.charactersIgnoringModifiers,
              let character = characters.first else {
            return Unmanaged.passUnretained(event)
        }

        if SnippetAbbreviation.isWordCharacter(character) {
            bufferLock.withLock {
                buffer.append(character)
                if buffer.count > SnippetAbbreviation.maxLength {
                    buffer.removeFirst(buffer.count - SnippetAbbreviation.maxLength)
                }
            }
            return Unmanaged.passUnretained(event)
        }

        guard SnippetAbbreviation.isDelimiter(character) else {
            bufferLock.withLock { buffer = "" }
            return Unmanaged.passUnretained(event)
        }

        let current = bufferLock.withLock { buffer }
        guard !current.isEmpty else {
            return Unmanaged.passUnretained(event)
        }

        var expansion: String?
        let evaluate = {
            MainActor.assumeIsolated {
                guard self.shouldExpand() else { return }
                expansion = self.expansions()[current.lowercased()]
            }
        }
        if Thread.isMainThread {
            evaluate()
        } else {
            DispatchQueue.main.sync(execute: evaluate)
        }
        bufferLock.withLock { buffer = "" }

        guard let expansion else {
            return Unmanaged.passUnretained(event)
        }

        let deleteCount = current.count
        let delimiterKey = keyCode
        let delimiterFlags = flags
        let delimiterChars = characters
        // Finish the tap callback before synthesizing deletes/paste.
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?.performExpansion(
                    text: expansion,
                    deleteCount: deleteCount,
                    delimiterKeyCode: delimiterKey,
                    delimiterFlags: delimiterFlags,
                    delimiterCharacters: delimiterChars
                )
            }
        }
        return nil
    }

    private func performExpansion(
        text: String,
        deleteCount: Int,
        delimiterKeyCode: UInt16,
        delimiterFlags: CGEventFlags,
        delimiterCharacters: String
    ) {
        guard deleteCount > 0, !text.isEmpty else { return }
        Self.suppress = true
        setTapsEnabled(false)
        defer {
            setTapsEnabled(true)
            Self.suppress = false
        }

        let source = CGEventSource(stateID: .hidSystemState)
        source?.localEventsSuppressionInterval = 0
        for _ in 0..<deleteCount {
            postKey(KeyCode.delete, down: true, flags: [], source: source)
            postKey(KeyCode.delete, down: false, flags: [], source: source)
        }

        PasteService.writeText(text)
        noteOwnWrite?()
        PasteService.sendCommandV()

        if let scalar = delimiterCharacters.unicodeScalars.first {
            if let event = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(delimiterKeyCode),
                keyDown: true
            ) {
                event.flags = delimiterFlags.intersection([.maskShift])
                event.keyboardSetUnicodeString(stringLength: 1, unicodeString: [UniChar(scalar.value)])
                event.post(tap: .cghidEventTap)
            }
            if let event = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(delimiterKeyCode),
                keyDown: false
            ) {
                event.flags = []
                event.post(tap: .cghidEventTap)
            }
        }
    }

    private func setTapsEnabled(_ enabled: Bool) {
        if let tap = Self.activeTap {
            CGEvent.tapEnable(tap: tap, enable: enabled)
        }
        if let tap = HotkeyController.activeTap {
            CGEvent.tapEnable(tap: tap, enable: enabled)
        }
    }

    private func postKey(_ keyCode: UInt16, down: Bool, flags: CGEventFlags, source: CGEventSource?) {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(keyCode), keyDown: down) else {
            return
        }
        event.flags = flags
        event.post(tap: .cghidEventTap)
    }
}
