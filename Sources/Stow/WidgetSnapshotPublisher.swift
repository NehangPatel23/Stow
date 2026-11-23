import Foundation
import WidgetKit

enum WidgetSnapshotPublisher {
    @MainActor
    static func publish(from model: AppModel) {
        let presenting = model.isPresenting
        let items = WidgetSnapshotStore.orderedItems(
            from: model.snippets.map {
                (
                    id: $0.id,
                    title: $0.title,
                    text: presenting ? "" : $0.text,
                    kind: $0.kind.rawValue,
                    symbolName: $0.kind.symbolName,
                    pinned: $0.pinned,
                    sortOrder: $0.sortOrder,
                    createdAt: $0.createdAt
                )
            }
        ).map { item in
            var item = item
            if presenting {
                item.preview = ""
                item.text = ""
            }
            return item
        }
        let paused = model.isPaused || model.frontAppPauseIsActive
        let snapshot = WidgetSnapshot.make(snippets: items, isPaused: paused)
        _ = WidgetSnapshotStore.save(snapshot)
        WidgetPauseBridge.mirrorPaused(model.isPaused)
        WidgetCenter.shared.reloadTimelines(ofKind: StowAppGroup.widgetKind)
    }
}
