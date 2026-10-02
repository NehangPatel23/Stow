import AppKit
import SwiftUI

struct Theme {
    var scheme: ColorScheme

    var background: Color {
        scheme == .dark
            ? Color(red: 0.11, green: 0.098, blue: 0.09)
            : Color(red: 0.965, green: 0.953, blue: 0.933)
    }

    var card: Color {
        scheme == .dark
            ? Color(red: 0.16, green: 0.145, blue: 0.133)
            : Color.white.opacity(0.72)
    }

    var highlight: Color {
        scheme == .dark
            ? Color(red: 0.93, green: 0.89, blue: 0.82).opacity(0.14)
            : Color(red: 0.27, green: 0.24, blue: 0.2).opacity(0.08)
    }

    var chip: Color {
        scheme == .dark
            ? Color.white.opacity(0.06)
            : Color.black.opacity(0.05)
    }

    var chipActive: Color {
        scheme == .dark
            ? Color(red: 0.93, green: 0.89, blue: 0.82).opacity(0.22)
            : Color(red: 0.27, green: 0.24, blue: 0.2).opacity(0.14)
    }

    var secondary: Color {
        scheme == .dark ? Color(red: 0.66, green: 0.63, blue: 0.58) : Color(red: 0.45, green: 0.42, blue: 0.38)
    }

    var pin: Color {
        Color(red: 0.72, green: 0.52, blue: 0.28)
    }

    var separator: Color {
        Color.primary.opacity(scheme == .dark ? 0.12 : 0.08)
    }

    var accent: Color {
        scheme == .dark
            ? Color(red: 0.93, green: 0.87, blue: 0.76)
            : Color(red: 0.33, green: 0.27, blue: 0.21)
    }

    var keycap: Color {
        scheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)
    }

    var shadow: Color {
        Color.black.opacity(scheme == .dark ? 0.35 : 0.12)
    }
}

enum StowSurface {
    case library
    case quickPick
}

enum PanelMetrics {
    static let quickWidth: CGFloat = 760
    static let librarySize = NSSize(width: 980, height: 640)

    @MainActor
    static func quickBand(for model: AppModel) -> CGFloat {
        let count = itemCount(model)
        let rows = CGFloat(max(count, 1))
        let natural = rows * 68 + (model.selectedID == nil ? 12 : 36)
        return min(max(natural, 188), 340)
    }

    @MainActor
    static func quickSize(for model: AppModel, screenHeight: CGFloat) -> NSSize {
        let header: CGFloat = 196
        let banner: CGFloat = model.banner == nil ? 0 : 28
        let permission: CGFloat = model.showPermission ? 44 : 0
        let footer: CGFloat = (model.preferences.showShortcutFooter ? 50 : 38) + (model.undo == nil ? 0 : 42)
        let raw = header + banner + permission + quickBand(for: model) + footer
        let cap = max(320, min(640, screenHeight * 0.62))
        return NSSize(width: quickWidth, height: min(max(raw, 320), cap))
    }

    @MainActor
    private static func itemCount(_ model: AppModel) -> Int {
        model.library == .history ? model.flattenedHistory.count : model.visibleSnippets.count
    }
}

struct AppIconMark: View {
    var size: CGFloat

    var body: some View {
        Image(nsImage: NSApp.applicationIconImage)
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
            .shadow(color: .black.opacity(0.16), radius: size * 0.06, y: size * 0.03)
    }
}
