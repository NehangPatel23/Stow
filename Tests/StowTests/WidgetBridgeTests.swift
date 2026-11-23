import XCTest

final class WidgetBridgeTests: XCTestCase {
    func testOrderedItemsPinsFirstAndCaps() {
        let older = Date(timeIntervalSince1970: 100)
        let newer = Date(timeIntervalSince1970: 200)
        let items = WidgetSnapshotStore.orderedItems(
            from: [
                (id: UUID(), title: "B", text: "beta", kind: "text", symbolName: "text.alignleft", pinned: false, sortOrder: 1, createdAt: newer),
                (id: UUID(), title: "A", text: "alpha", kind: "text", symbolName: "text.alignleft", pinned: true, sortOrder: 9, createdAt: older),
                (id: UUID(), title: "C", text: "gamma", kind: "link", symbolName: "link", pinned: false, sortOrder: 0, createdAt: older),
            ]
        )
        XCTAssertEqual(items.map(\.title), ["A", "C", "B"])
        XCTAssertEqual(items.first?.preview.isEmpty, false)
    }

    func testSnapshotCapsAtMax() {
        let many = (0..<20).map { index in
            WidgetSnippetItem(
                id: UUID(),
                title: "S\(index)",
                preview: "p",
                text: "t",
                kind: "text",
                symbolName: "text.alignleft",
                pinned: false
            )
        }
        let snapshot = WidgetSnapshot.make(snippets: many, isPaused: true)
        XCTAssertEqual(snapshot.snippets.count, WidgetSnapshot.maxSnippets)
        XCTAssertTrue(snapshot.isPaused)
    }
}
