import CoreGraphics
import Foundation

enum RowDensity: String, Codable, CaseIterable, Identifiable, Sendable {
    case compact
    case comfortable
    case large

    var id: String { rawValue }

    var title: String {
        switch self {
        case .compact: "Compact"
        case .comfortable: "Comfortable"
        case .large: "Large"
        }
    }

    var detail: String {
        switch self {
        case .compact: "Fits more clips."
        case .comfortable: "Default spacing."
        case .large: "Taller rows and more preview lines."
        }
    }

    var verticalPadding: CGFloat {
        switch self {
        case .compact: 5
        case .comfortable: 8
        case .large: 12
        }
    }

    var titleFontSize: CGFloat {
        switch self {
        case .compact, .comfortable: 13
        case .large: 15
        }
    }

    var metaFontSize: CGFloat {
        switch self {
        case .compact, .comfortable: 11
        case .large: 12
        }
    }

    var titleLineLimit: Int {
        switch self {
        case .compact: 1
        case .comfortable: 2
        case .large: 3
        }
    }

    /// Approximate list row height for quick-panel sizing.
    var listRowHeight: CGFloat {
        switch self {
        case .compact: 52
        case .comfortable: 68
        case .large: 92
        }
    }

    static func migrating(fromCompactRows compact: Bool?) -> RowDensity {
        guard let compact else { return .comfortable }
        return compact ? .compact : .comfortable
    }
}
