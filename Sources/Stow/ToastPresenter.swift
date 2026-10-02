import SwiftUI

struct Notice: Equatable, Identifiable {
    var id = UUID()
    var title: String
    var detail: String?
    var symbol: String
    var offersUndo = false
}

struct ToastBanner: View {
    var notice: Notice
    var theme: Theme
    var onUndo: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: notice.symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.accent)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(notice.title)
                    .font(.system(size: 13, weight: .semibold))
                if let detail = notice.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundStyle(theme.secondary)
                        .lineLimit(1)
                }
            }
            if notice.offersUndo, let onUndo {
                Button(action: onUndo) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .help("Undo")
                .accessibilityLabel("Undo")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(theme.card, in: Capsule())
        .overlay(Capsule().strokeBorder(theme.separator))
        .shadow(color: theme.shadow, radius: 10, y: 4)
    }
}
