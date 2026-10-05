import AppKit

/// Captured general pasteboard contents so a one-shot paste can put them back.
struct PasteboardSnapshot: Equatable, Sendable {
    struct Item: Equatable, Sendable {
        var representations: [(type: String, data: Data)]

        static func == (lhs: Item, rhs: Item) -> Bool {
            guard lhs.representations.count == rhs.representations.count else { return false }
            return zip(lhs.representations, rhs.representations).allSatisfy { left, right in
                left.type == right.type && left.data == right.data
            }
        }
    }

    var items: [Item]

    /// Reads declared representations, with a plain-string fallback for reliability.
    static func capture(from pasteboard: NSPasteboard = .general) -> PasteboardSnapshot? {
        if let items = captureItems(from: pasteboard), !items.isEmpty {
            return PasteboardSnapshot(items: items)
        }
        // Some writers only expose string via the convenience API.
        if let string = pasteboard.string(forType: .string), !string.isEmpty,
           let data = string.data(using: .utf8) {
            return PasteboardSnapshot(items: [
                Item(representations: [(NSPasteboard.PasteboardType.string.rawValue, data)]),
            ])
        }
        return nil
    }

    private static func captureItems(from pasteboard: NSPasteboard) -> [Item]? {
        guard let pbItems = pasteboard.pasteboardItems, !pbItems.isEmpty else { return nil }
        var items: [Item] = []
        for pbItem in pbItems {
            var representations: [(type: String, data: Data)] = []
            var seen: Set<String> = []

            if let string = pbItem.string(forType: .string),
               !string.isEmpty,
               let data = string.data(using: .utf8) {
                let raw = NSPasteboard.PasteboardType.string.rawValue
                representations.append((raw, data))
                seen.insert(raw)
            }

            for type in pbItem.types {
                let raw = type.rawValue
                if raw == PasteboardPolicy.originType || seen.contains(raw) { continue }
                if let data = pbItem.data(forType: type), !data.isEmpty {
                    representations.append((raw, data))
                    seen.insert(raw)
                } else if let string = pbItem.string(forType: type),
                          let data = string.data(using: .utf8),
                          !data.isEmpty {
                    representations.append((raw, data))
                    seen.insert(raw)
                }
            }
            if !representations.isEmpty {
                items.append(Item(representations: representations))
            }
        }
        return items.isEmpty ? nil : items
    }

    @discardableResult
    func restore(onto pasteboard: NSPasteboard = .general) -> Bool {
        pasteboard.clearContents()
        let origin = NSPasteboard.PasteboardType(PasteboardPolicy.originType)
        var objects: [NSPasteboardItem] = []
        for item in items {
            let pbItem = NSPasteboardItem()
            for representation in item.representations {
                let type = NSPasteboard.PasteboardType(representation.type)
                // Prefer setString for text so ⌘V consumers reliably see the restored clip.
                if type == .string || representation.type == "public.utf8-plain-text",
                   let string = String(data: representation.data, encoding: .utf8) {
                    pbItem.setString(string, forType: .string)
                } else {
                    pbItem.setData(representation.data, forType: type)
                }
            }
            pbItem.setString("1", forType: origin)
            objects.append(pbItem)
        }
        if pasteboard.writeObjects(objects) {
            return true
        }
        // Last resort: first UTF-8 string we captured.
        for item in items {
            for representation in item.representations {
                if let string = String(data: representation.data, encoding: .utf8), !string.isEmpty {
                    pasteboard.clearContents()
                    pasteboard.setString(string, forType: .string)
                    return true
                }
            }
        }
        return false
    }
}
