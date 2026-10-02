import AppKit
import Foundation

enum ClipIngest {
    private static let textLimit = 1_000_000
    private static let imageByteLimit = 12 * 1024 * 1024

    static func makeDraft(from pasteboard: NSPasteboard, source: NSRunningApplication?) -> ClipDraft? {
        let items = pasteboard.pasteboardItems ?? []
        var text: String?
        var html: String?
        var rtf: Data?
        var png: Data?
        var filePaths: [String] = []

        for item in items {
            if text == nil, let value = item.string(forType: .string), !ClipText.isBlank(value) {
                text = value
            }
            if html == nil, let value = item.string(forType: .html), !value.isEmpty {
                html = value
            }
            if rtf == nil, let value = item.data(forType: .rtf), !value.isEmpty {
                rtf = value
            }
            if png == nil, let value = item.data(forType: .png), !value.isEmpty {
                png = value
            } else if png == nil, let tiff = item.data(forType: .tiff), let image = NSImage(data: tiff) {
                png = pngData(from: image)
            }
            if let file = filePath(from: item) {
                filePaths.append(file)
            }
            if text == nil, let url = item.string(forType: .URL), !ClipText.isBlank(url) {
                text = url
            }
        }

        if ClipText.isBlank(text), let rtf, let attributed = NSAttributedString(rtf: rtf, documentAttributes: nil) {
            text = attributed.string
        }

        if var value = text {
            if value.count > textLimit {
                value = String(value.prefix(textLimit))
            }
            text = value
        }

        filePaths = Array(NSOrderedSet(array: filePaths).compactMap { $0 as? String }.prefix(50))

        let hasImage = png != nil
        if png == nil && filePaths.isEmpty && ClipText.isBlank(text) && rtf == nil && ClipText.isBlank(html) {
            return nil
        }

        var storedPNG = png
        var thumbnail: Data?
        var pixelWidth: Int?
        var pixelHeight: Int?
        if let png {
            if let image = NSImage(data: png) {
                pixelWidth = pixelsWide(image, fallbackData: png)
                pixelHeight = pixelsHigh(image, fallbackData: png)
                thumbnail = thumbnailPNG(from: image)
            }
            if png.count > imageByteLimit {
                storedPNG = thumbnail.flatMap { thumb -> Data? in
                    guard let image = NSImage(data: png) else { return thumb }
                    return resizedPNG(from: image, maxSide: 1600) ?? thumb
                }
            }
        }

        let kind = ClipClassifier.classify(
            text: text,
            html: html,
            hasRTF: rtf != nil,
            hasImage: hasImage,
            fileURLs: filePaths
        )
        let color = text.flatMap { ColorValue.parse($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        let preview = previewLine(
            kind: kind,
            text: text,
            filePaths: filePaths,
            width: pixelWidth,
            height: pixelHeight,
            byteSize: storedPNG?.count ?? text?.utf8.count ?? 0
        )
        let hash: String
        if let storedPNG, kind == .image {
            hash = ContentHash.image(storedPNG)
        } else if kind == .file {
            hash = ContentHash.files(filePaths)
        } else {
            hash = ContentHash.text(text ?? "")
        }

        return ClipDraft(
            sourceAppName: source?.localizedName ?? "Unknown",
            sourceBundleID: source?.bundleIdentifier ?? "",
            kind: kind,
            preview: preview,
            text: text,
            html: html,
            rtf: rtf,
            imagePNG: storedPNG,
            thumbnailPNG: thumbnail,
            fileURLs: filePaths,
            colorHex: color?.hex,
            contentHash: hash,
            imageWidth: pixelWidth,
            imageHeight: pixelHeight,
            byteSize: storedPNG?.count ?? text?.utf8.count ?? filePaths.count,
            createdAt: Date()
        )
    }

    private static func previewLine(
        kind: ClipKind,
        text: String?,
        filePaths: [String],
        width: Int?,
        height: Int?,
        byteSize: Int
    ) -> String {
        switch kind {
        case .image:
            if let width, let height {
                return "\(width) × \(height) · \(ByteFormat.string(for: byteSize))"
            }
            return "Image · \(ByteFormat.string(for: byteSize))"
        case .file:
            let names = filePaths.map { URL(fileURLWithPath: $0).lastPathComponent }
            return names.isEmpty ? "File" : names.joined(separator: ", ")
        default:
            return ClipText.previewLine(from: text ?? "")
        }
    }

    private static func filePath(from item: NSPasteboardItem) -> String? {
        guard let raw = item.string(forType: .fileURL), let url = URL(string: raw), url.isFileURL else {
            return nil
        }
        return url.path
    }

    static func pngData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    private static func thumbnailPNG(from image: NSImage) -> Data? {
        resizedPNG(from: image, maxSide: 64)
    }

    private static func resizedPNG(from image: NSImage, maxSide: CGFloat) -> Data? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        let scale = min(1, maxSide / max(size.width, size.height))
        let newSize = NSSize(width: max(1, floor(size.width * scale)), height: max(1, floor(size.height * scale)))
        let canvas = NSImage(size: newSize)
        canvas.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: newSize), from: .zero, operation: .copy, fraction: 1)
        canvas.unlockFocus()
        return pngData(from: canvas)
    }

    private static func pixelsWide(_ image: NSImage, fallbackData: Data) -> Int? {
        if let rep = NSBitmapImageRep(data: fallbackData) { return rep.pixelsWide }
        return Int(image.size.width)
    }

    private static func pixelsHigh(_ image: NSImage, fallbackData: Data) -> Int? {
        if let rep = NSBitmapImageRep(data: fallbackData) { return rep.pixelsHigh }
        return Int(image.size.height)
    }
}
