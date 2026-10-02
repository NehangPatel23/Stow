import Foundation

struct Snippet: Identifiable, Equatable, Sendable {
    var id: UUID
    var createdAt: Date
    var title: String
    var text: String
    var kind: ClipKind
    var pinned: Bool = false

    var preview: String {
        ClipText.previewLine(from: text)
    }
}
