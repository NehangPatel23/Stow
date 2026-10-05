import Foundation

struct Clip: Identifiable, Equatable, Sendable {
    var id: UUID
    var createdAt: Date
    var pinned: Bool
    var sourceAppName: String
    var sourceBundleID: String
    var kind: ClipKind
    var preview: String
    var text: String?
    var html: String?
    /// Loaded for paste, restore, and the preview. List rows leave this nil.
    var rtf: Data?
    var imageRelativePath: String?
    var thumbRelativePath: String?
    var fileURLs: [String]
    var colorHex: String?
    var contentHash: String
    var imageWidth: Int?
    var imageHeight: Int?
    var byteSize: Int
    /// How many stored copies folded into this row.
    var copyCount: Int
    /// On-device OCR text for image clips. `nil` means not indexed yet; empty means indexed with no text.
    var ocrText: String?
}

struct ClipDraft: Equatable, Sendable {
    var sourceAppName: String
    var sourceBundleID: String
    var kind: ClipKind
    var preview: String
    var text: String?
    var html: String?
    var rtf: Data?
    var imagePNG: Data?
    var thumbnailPNG: Data?
    var fileURLs: [String]
    var colorHex: String?
    var contentHash: String
    var imageWidth: Int?
    var imageHeight: Int?
    var byteSize: Int
    var createdAt: Date
    /// Optional precomputed OCR. Usually filled after record, not during ingest.
    var ocrText: String? = nil
}
