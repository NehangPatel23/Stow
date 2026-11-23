import SwiftUI

struct SelectionChipView: View {
    var preview: String
    var onCopy: () -> Void
    var onSaveSnippet: () -> Void
    var onDismiss: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var flash: String?

    private var theme: Theme { Theme(scheme: colorScheme) }

    var body: some View {
        HStack(spacing: 8) {
            if let flash {
                Text(flash)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.accent)
                    .transition(.opacity)
            } else {
                Text(preview)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: 160, alignment: .leading)

                chipButton("Copy", systemImage: "doc.on.doc", action: {
                    onCopy()
                    flashSuccess("Copied")
                })
                chipButton("Snippet", systemImage: "text.badge.plus", action: {
                    onSaveSnippet()
                    flashSuccess("Saved")
                })
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(theme.secondary)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Dismiss")
                .accessibilityLabel("Dismiss")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(theme.card, in: Capsule())
        .overlay(Capsule().strokeBorder(theme.separator))
        .shadow(color: theme.shadow, radius: 12, y: 4)
        .animation(.easeOut(duration: 0.15), value: flash)
    }

    private func chipButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .semibold))
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(theme.accent)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(theme.chip, in: Capsule())
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
    }

    private func flashSuccess(_ message: String) {
        flash = message
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(700))
            onDismiss()
        }
    }
}
