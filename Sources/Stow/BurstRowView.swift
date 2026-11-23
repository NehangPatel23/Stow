import SwiftUI

struct BurstRowView: View {
    var burst: CopyBurst
    var theme: Theme
    @Environment(AppModel.self) private var model

    private var isSelected: Bool {
        burst.clips.contains { model.selection.contains($0.id) }
    }

    private var expanded: Bool {
        model.expandedBurstIDs.contains(burst.id)
    }

    @State private var hovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                typeMark
                VStack(alignment: .leading, spacing: 2) {
                    Text(burst.newest.preview)
                        .font(.system(size: 13))
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        Text(burst.sourceAppName)
                        Text("·")
                        Text(timeLabel(burst.createdAt))
                        Text("·")
                        Button {
                            model.toggleExpandedBurst(burst.id)
                        } label: {
                            HStack(spacing: 3) {
                                Text(expanded ? "Hide" : "\(burst.count) items")
                                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 8, weight: .bold))
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(theme.secondary)
                    .lineLimit(1)
                }
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 4) {
                    if !expanded, let index = model.shortcutIndex(for: burst.newest), model.query.isEmpty {
                        Text("\(index)")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(theme.secondary)
                    }
                    if burst.pinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(theme.pin)
                    }
                }
            }
            if expanded {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(burst.clips) { clip in
                        ClipRowView(clip: clip, theme: theme)
                            .id(clip.id)
                    }
                }
                .padding(.leading, 20)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, model.preferences.compactRows ? 5 : 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected && !expanded ? theme.highlight : (hovered && !expanded ? theme.chip.opacity(0.85) : Color.clear))
        )
        .overlay(alignment: .leading) {
            if isSelected && !expanded {
                RoundedRectangle(cornerRadius: 1)
                    .fill(theme.accent)
                    .frame(width: 2)
                    .padding(.vertical, model.preferences.compactRows ? 5 : 8)
                    .padding(.leading, 3)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onHover { hovered = $0 }
        .onTapGesture(count: 2) {
            model.pasteBurst(burst)
        }
        .onTapGesture {
            model.click(burst.newest.id)
        }
        .contextMenu { burstMenu }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Copy session, \(burst.count) items from \(burst.sourceAppName), \(burst.newest.preview)"
        )
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var burstMenu: some View {
        Group {
            Button("Paste session") {
                model.pasteBurst(burst)
            }
            Button("Paste session with comma") {
                model.pasteBurst(burst, separator: ", ")
            }
            Button("Expand") {
                if !expanded {
                    model.toggleExpandedBurst(burst.id)
                }
            }
            .disabled(expanded)
            Divider()
            Button("Select newest") {
                model.selectOnly(burst.newest.id)
            }
            Button(burst.newest.pinned ? "Unpin newest" : "Pin newest") {
                model.selectOnly(burst.newest.id)
                model.togglePin()
            }
        }
    }

    private var typeMark: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(theme.chip)
                .frame(width: 26, height: 26)
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme.secondary)
        }
    }

    private func timeLabel(_ date: Date) -> String {
        let now = Date()
        let time = date.formatted(date: .omitted, time: .shortened)
        switch TimeBucket.bucket(for: date, now: now) {
        case .today: return time
        case .yesterday: return "Yesterday, \(time)"
        case .older: return date.formatted(date: .abbreviated, time: .shortened)
        }
    }
}
