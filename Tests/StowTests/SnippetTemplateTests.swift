import XCTest

final class SnippetTemplateTests: XCTestCase {
    func testFieldsAreDedupedAndNormalized() {
        let text = "Hi {{Name}}, ticket {{ ticket }} for {{name}} on {{date}}."
        let fields = SnippetTemplate.fields(in: text)
        XCTAssertEqual(fields.map(\.key), ["name", "ticket", "date"])
        XCTAssertEqual(fields.map(\.label), ["Name", "Ticket", "Date"])
    }

    func testRenderSubstitutesValues() {
        let text = "Hello {{name}} — {{ticket}}"
        let rendered = SnippetTemplate.render(text, values: ["name": "Ada", "ticket": "42"])
        XCTAssertEqual(rendered, "Hello Ada — 42")
    }

    func testDateDefaultIsFilled() {
        let fields = [TemplateField(key: "date"), TemplateField(key: "name")]
        let values = SnippetTemplate.defaults(for: fields, now: Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertFalse(values["date", default: ""].isEmpty)
        XCTAssertEqual(values["name"], "")
    }
}
