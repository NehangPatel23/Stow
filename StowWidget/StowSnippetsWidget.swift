import AppIntents
import SwiftUI
import WidgetKit

struct StowSnippetsEntry: TimelineEntry {
    var date: Date
    var snapshot: WidgetSnapshot
}

struct StowSnippetsProvider: TimelineProvider {
    func placeholder(in context: Context) -> StowSnippetsEntry {
        StowSnippetsEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (StowSnippetsEntry) -> Void) {
        completion(StowSnippetsEntry(date: Date(), snapshot: WidgetSnapshotStore.load().orPlaceholder))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StowSnippetsEntry>) -> Void) {
        let entry = StowSnippetsEntry(date: Date(), snapshot: WidgetSnapshotStore.load())
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(30 * 60))))
    }
}

extension WidgetSnapshot {
    static let placeholder = WidgetSnapshot(
        updatedAt: Date(),
        isPaused: false,
        snippets: [
            WidgetSnippetItem(
                id: UUID(),
                title: "Support reply",
                preview: "Thanks for writing in — happy to help.",
                text: "Thanks for writing in — happy to help.",
                kind: "text",
                symbolName: "text.alignleft",
                pinned: true
            ),
            WidgetSnippetItem(
                id: UUID(),
                title: "Office address",
                preview: "500 Market Street, San Francisco",
                text: "500 Market Street, San Francisco",
                kind: "text",
                symbolName: "text.alignleft",
                pinned: false
            ),
        ]
    )

    var orPlaceholder: WidgetSnapshot {
        snippets.isEmpty ? .placeholder : self
    }
}

struct StowSnippetsWidget: Widget {
    let kind = StowAppGroup.widgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StowSnippetsProvider()) { entry in
            StowSnippetsWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    Color(nsColor: .windowBackgroundColor)
                }
        }
        .configurationDisplayName("Snippets")
        .description("A handful of Stow snippets, with a pause control for recording.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct StowSnippetsWidgetView: View {
    var entry: StowSnippetsEntry

    @Environment(\.widgetFamily) private var family

    private var limit: Int {
        switch family {
        case .systemSmall: 3
        case .systemMedium: 4
        default: 6
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if entry.snapshot.snippets.isEmpty {
                Text("No snippets yet")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            } else {
                ForEach(Array(entry.snapshot.snippets.prefix(limit))) { item in
                    snippetRow(item)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(12)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Stow")
                .font(.system(size: 13, weight: .semibold))
            if entry.snapshot.isPaused {
                Text("Paused")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color(red: 0.72, green: 0.45, blue: 0.18))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.15), in: Capsule())
            }
            Spacer(minLength: 4)
            Button(intent: ToggleRecordingIntent()) {
                Image(systemName: entry.snapshot.isPaused ? "record.circle" : "pause.circle")
                    .font(.system(size: 14, weight: .semibold))
            }
            .buttonStyle(.plain)
            .help(entry.snapshot.isPaused ? "Resume recording" : "Pause recording")
        }
    }

    private func snippetRow(_ item: WidgetSnippetItem) -> some View {
        Button(intent: CopyWidgetSnippetIntent(snippetID: item.id)) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: item.symbolName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 14)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(item.title)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                        if item.pinned {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(Color(red: 0.72, green: 0.52, blue: 0.28))
                        }
                    }
                    if family != .systemSmall {
                        Text(item.preview)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
