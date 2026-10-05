import AppKit
import UniformTypeIdentifiers

enum PasteService {
    static func write(_ clip: Clip, plain: Bool, imageData: Data?) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let origin = NSPasteboard.PasteboardType(PasteboardPolicy.originType)
        var items: [NSPasteboardItem] = []

        if clip.fileURLs.isEmpty {
            let item = NSPasteboardItem()
            if let text = clip.text {
                item.setString(text, forType: .string)
            }
            if !plain {
                if let html = clip.html {
                    item.setString(html, forType: .html)
                }
                if let rtf = clip.rtf {
                    item.setData(rtf, forType: .rtf)
                }
            }
            if let imageData {
                item.setData(imageData, forType: .png)
            }
            item.setString("1", forType: origin)
            items = [item]
        } else {
            for path in clip.fileURLs {
                let fileItem = NSPasteboardItem()
                fileItem.setString(URL(fileURLWithPath: path).absoluteString, forType: .fileURL)
                if let text = clip.text {
                    fileItem.setString(text, forType: .string)
                }
                fileItem.setString("1", forType: origin)
                items.append(fileItem)
            }
        }
        if pasteboard.writeObjects(items) { return }
        if let text = clip.text, !text.isEmpty {
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
        }
    }

    static func writeText(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        item.setString("1", forType: NSPasteboard.PasteboardType(PasteboardPolicy.originType))
        pasteboard.writeObjects([item])
    }

    static func snapshot(from pasteboard: NSPasteboard = .general) -> PasteboardSnapshot? {
        PasteboardSnapshot.capture(from: pasteboard)
    }

    @discardableResult
    static func restore(_ snapshot: PasteboardSnapshot, onto pasteboard: NSPasteboard = .general) -> Bool {
        snapshot.restore(onto: pasteboard)
    }

    static func imageData(for clip: Clip, store: HistoryStore) -> Data? {
        guard let path = clip.imageRelativePath else { return nil }
        return try? Data(contentsOf: store.url(forRelativePath: path))
    }

    /// Posts Command-V into whichever app is focused.
    static func sendCommandV() {
        let taps = [HotkeyController.activeTap, AbbreviationExpander.activeTap].compactMap { $0 }
        for tap in taps {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        defer {
            for tap in taps {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
        }
        let source = CGEventSource(stateID: .hidSystemState)
        source?.localEventsSuppressionInterval = 0
        let command = CGKeyCode(0x37)
        let v = CGKeyCode(KeyCode.v)
        let held = CGEventFlags.maskCommand
        func post(_ code: CGKeyCode, down: Bool, flags: CGEventFlags) {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down) else { return }
            event.flags = flags
            event.post(tap: .cghidEventTap)
        }
        post(command, down: true, flags: held)
        post(v, down: true, flags: held)
        post(v, down: false, flags: held)
        post(command, down: false, flags: [])
    }
}

enum ClipDrag {
    static func provider(for clip: Clip, store: HistoryStore) -> NSItemProvider? {
        if clip.kind == .file, let path = clip.fileURLs.first {
            return NSItemProvider(contentsOf: URL(fileURLWithPath: path))
        }
        if clip.kind == .image, let relative = clip.imageRelativePath {
            return NSItemProvider(contentsOf: store.url(forRelativePath: relative))
        }
        return nil
    }

    static func provider(forFilePath path: String) -> NSItemProvider? {
        NSItemProvider(contentsOf: URL(fileURLWithPath: path))
    }
}
