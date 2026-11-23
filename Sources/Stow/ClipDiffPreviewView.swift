import SwiftUI

struct ClipDiffPreviewView: View {
    var session: ClipDiffSession
    var theme: Theme
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Diff")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.secondary)
                Spacer()
                Button("Done") {
                    model.endClipDiff()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            HStack(alignment: .top, spacing: 12) {
                sideLabel(title: "Older", clip: session.older)
                sideLabel(title: "Newer", clip: session.newer)
            }

            HStack(spacing: 8) {
                Button("Paste older") { model.pasteDiffClip(older: true) }
                Button("Paste newer") { model.pasteDiffClip(older: false) }
                Button("Plain older") { model.pasteDiffClip(older: true, plain: true) }
                Button("Plain newer") { model.pasteDiffClip(older: false, plain: true) }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            if let failure = session.failure {
                Text(failureMessage(failure))
                    .font(.system(size: 12))
                    .foregroundStyle(theme.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else if let result = session.result {
                Text(result.caption)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.secondary)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(result.lines.enumerated()), id: \.offset) { _, line in
                            diffLine(line)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }

    private func sideLabel(title: String, clip: Clip) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme.secondary)
            Text(clip.preview)
                .font(.system(size: 12))
                .lineLimit(2)
            Text("\(clip.sourceAppName) · \(clip.createdAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.system(size: 11))
                .foregroundStyle(theme.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func diffLine(_ line: ClipDiffLine) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(line.prefix)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(prefixColor(line))
                .frame(width: 10, alignment: .leading)
            Text(line.text.isEmpty ? " " : line.text)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(textColor(line))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(background(line))
        .accessibilityLabel(accessibilityLabel(line))
    }

    private func prefixColor(_ line: ClipDiffLine) -> Color {
        switch line {
        case .unchanged: theme.secondary
        case .removed: Color(red: 0.72, green: 0.28, blue: 0.24)
        case .added: Color(red: 0.22, green: 0.52, blue: 0.34)
        }
    }

    private func textColor(_ line: ClipDiffLine) -> Color {
        switch line {
        case .unchanged: Color.primary
        case .removed, .added: prefixColor(line)
        }
    }

    private func background(_ line: ClipDiffLine) -> Color {
        switch line {
        case .unchanged:
            Color.clear
        case .removed:
            Color(red: 0.72, green: 0.28, blue: 0.24).opacity(theme.scheme == .dark ? 0.18 : 0.1)
        case .added:
            Color(red: 0.22, green: 0.52, blue: 0.34).opacity(theme.scheme == .dark ? 0.18 : 0.1)
        }
    }

    private func accessibilityLabel(_ line: ClipDiffLine) -> String {
        let body = line.text.isEmpty ? "blank line" : line.text
        switch line {
        case .unchanged: return body
        case .removed: return "Removed: \(body)"
        case .added: return "Added: \(body)"
        }
    }

    private func failureMessage(_ failure: ClipDiff.Failure) -> String {
        switch failure {
        case .tooLarge:
            return "These clips are too large to diff here. Paste either one from the list instead."
        }
    }
}
