import XCTest

final class ClipTransformsTests: XCTestCase {
    func testHTMLToMarkdown() {
        let html = "<p>Hello <a href=\"https://example.com\">there</a></p><p><strong>Bold</strong></p>"
        let markdown = ClipTransform.htmlToMarkdown.output(text: html, html: html)
        XCTAssertEqual(markdown, "Hello [there](https://example.com)\n\n**Bold**")
    }

    func testHTMLSourceCopiedAsRichText() {
        let plain = "<h1>Title</h1><p>Hello <strong>world</strong> and a <a href=\"https://example.com\">link</a>.</p>"
        let escaped = "<meta charset='utf-8'>&lt;h1&gt;Title&lt;/h1&gt;&lt;p&gt;Hello &lt;strong&gt;world&lt;/strong&gt; and a &lt;a href=\"https://example.com\"&gt;link&lt;/a&gt;.&lt;/p&gt;"
        let markdown = ClipTransform.htmlToMarkdown.output(text: plain, html: escaped)
        XCTAssertEqual(markdown, "Title\n\nHello **world** and a [link](https://example.com).")
    }

    func testEscapedWrapperAroundPlainTextOffersNothing() {
        let plain = "A paragraph broken onto several short lines, with a blank line before the next paragraph"
        let escaped = "<meta charset='utf-8'>A paragraph broken onto several short lines, with a blank line before the next paragraph"
        XCTAssertNil(ClipTransform.htmlToMarkdown.output(text: plain, html: escaped))
        XCTAssertNil(ClipTransform.unwrapLines.output(text: plain, html: escaped))
    }

    func testPrettyJSON() {
        let pretty = ClipTransform.prettyJSON.output(text: #"{"b":1,"a":2}"#, html: nil)
        XCTAssertEqual(pretty, "{\n  \"a\" : 2,\n  \"b\" : 1\n}")
    }

    func testUnwrapLinesKeepsParagraphs() {
        let wrapped = "This line was\nwrapped on purpose.\n\nA second paragraph."
        XCTAssertEqual(
            ClipTransform.unwrapLines.output(text: wrapped, html: nil),
            "This line was wrapped on purpose.\n\nA second paragraph."
        )
    }

    func testStripTrackingParameters() {
        let url = "https://example.com/path?utm_source=newsletter&id=4&fbclid=abc"
        XCTAssertEqual(ClipTransform.stripTracking.output(text: url, html: nil), "https://example.com/path?id=4")
    }

    func testPreviewPasteDraftLeavesIdenticalTextUnchanged() {
        var clip = makeClip(text: "hello", hash: "kept")
        clip.html = "<p>hello</p>"
        let applied = PreviewPasteDraft.applying("hello", to: clip)
        XCTAssertEqual(applied.html, "<p>hello</p>")
        XCTAssertEqual(applied.contentHash, "kept")
    }

    func testPreviewPasteDraftClearsRichFormatsAndKeepsHash() {
        var clip = makeClip(text: "hello", hash: "kept")
        clip.html = "<p>hello</p>"
        clip.rtf = Data([0x01])
        let applied = PreviewPasteDraft.applying("hello world", to: clip)
        XCTAssertEqual(applied.text, "hello world")
        XCTAssertNil(applied.html)
        XCTAssertNil(applied.rtf)
        XCTAssertEqual(applied.contentHash, "kept")
        XCTAssertEqual(applied.preview, "hello world")
    }

    func testPreviewPasteDraftSupportsTextKindsOnly() {
        XCTAssertTrue(PreviewPasteDraft.supports(.text))
        XCTAssertTrue(PreviewPasteDraft.supports(.code))
        XCTAssertTrue(PreviewPasteDraft.supports(.richText))
        XCTAssertFalse(PreviewPasteDraft.supports(.image))
        XCTAssertFalse(PreviewPasteDraft.supports(.file))
        XCTAssertFalse(PreviewPasteDraft.supports(.color))
    }

    func testPlainTextOffersNothing() {
        XCTAssertTrue(ClipTransform.available(text: "Hello", html: nil).isEmpty)
    }

    func testSplitLinesRequiresTwoNonEmptyLines() {
        XCTAssertNil(ClipLineOps.splitLines("Hello"))
        XCTAssertNil(ClipLineOps.splitLines("Hello\n"))
        XCTAssertNil(ClipLineOps.splitLines("\n\n"))
        XCTAssertFalse(ClipLineOps.canSplit("one line"))
    }

    func testSplitLinesDropsBlanksAndNormalizesCRLF() {
        XCTAssertEqual(
            ClipLineOps.splitLines("alpha\r\n\r\nbeta\ngamma\n"),
            ["alpha", "beta", "gamma"]
        )
        XCTAssertEqual(
            ClipLineOps.splitLines("  one  \n  two  "),
            ["one", "two"]
        )
        XCTAssertTrue(ClipLineOps.canSplit("a\nb"))
    }

    func testLineToolChangeCase() {
        XCTAssertEqual(ClipLineTool.upperCase.output(text: "Hello"), "HELLO")
        XCTAssertNil(ClipLineTool.upperCase.output(text: "HELLO"))
        XCTAssertEqual(ClipLineTool.lowerCase.output(text: "Hello"), "hello")
        XCTAssertNil(ClipLineTool.lowerCase.output(text: "hello"))
        XCTAssertEqual(ClipLineTool.titleCase.output(text: "hello world"), "Hello World")
        XCTAssertNil(ClipLineTool.titleCase.output(text: "Hello World"))
    }

    func testLineToolSortLines() {
        XCTAssertEqual(ClipLineTool.sortLines.output(text: "c\na\nb"), "a\nb\nc")
        XCTAssertNil(ClipLineTool.sortLines.output(text: "a\nb\nc"))
        XCTAssertNil(ClipLineTool.sortLines.output(text: "only"))
        XCTAssertEqual(ClipLineTool.sortLines.output(text: "b\r\n\r\na"), "a\nb")
    }

    func testLineToolDropDuplicates() {
        XCTAssertEqual(ClipLineTool.dropDuplicates.output(text: "a\nb\na\nc"), "a\nb\nc")
        XCTAssertNil(ClipLineTool.dropDuplicates.output(text: "a\nb\nc"))
        XCTAssertNil(ClipLineTool.dropDuplicates.output(text: "a"))
    }

    func testLineToolTrimWhitespace() {
        XCTAssertEqual(ClipLineTool.trimWhitespace.output(text: "  a  \n  b  "), "a\nb")
        XCTAssertNil(ClipLineTool.trimWhitespace.output(text: "a\nb"))
    }

    func testLineToolJoinComma() {
        XCTAssertEqual(ClipLineTool.joinComma.output(text: "a\nb\nc"), "a, b, c")
        XCTAssertEqual(ClipLineTool.joinComma.output(text: "a\n\n\nb"), "a, b")
        XCTAssertNil(ClipLineTool.joinComma.output(text: "only"))
    }

    func testLineToolAvailability() {
        let single = ClipLineTool.available(text: "Hello")
        XCTAssertTrue(single.contains(.upperCase))
        XCTAssertTrue(single.contains(.lowerCase))
        XCTAssertFalse(single.contains(.sortLines))
        XCTAssertFalse(single.contains(.joinComma))
        XCTAssertTrue(ClipLineTool.available(text: "b\na").contains(.sortLines))
    }

    func testTextLengthEmpty() {
        XCTAssertEqual(TextLength.stats(for: ""), TextLength.Stats(characters: 0, words: 0, lines: 0))
        XCTAssertEqual(TextLength.caption(for: ""), "0 characters · 0 words · 0 lines")
    }

    func testTextLengthSingleWord() {
        XCTAssertEqual(TextLength.stats(for: "Hello"), TextLength.Stats(characters: 5, words: 1, lines: 1))
        XCTAssertEqual(TextLength.caption(for: "Hello"), "5 characters · 1 word · 1 line")
    }

    func testTextLengthWordsAndLines() {
        let text = "Hello world\nsecond line"
        XCTAssertEqual(TextLength.stats(for: text), TextLength.Stats(characters: 23, words: 4, lines: 2))
        XCTAssertEqual(TextLength.caption(for: text), "23 characters · 4 words · 2 lines")
    }

    func testTextLengthTrailingNewlineAndCRLF() {
        XCTAssertEqual(TextLength.stats(for: "Hello\n").lines, 2)
        XCTAssertEqual(TextLength.stats(for: "a\r\nb\r\nc").lines, 3)
    }

    func testTextLengthWhitespaceAndGraphemes() {
        XCTAssertEqual(TextLength.stats(for: "  \n\t  ").words, 0)
        XCTAssertEqual(TextLength.stats(for: "one   two\tthree").words, 3)
        XCTAssertEqual(TextLength.stats(for: "👨‍👩‍👧").characters, 1)
    }

    func testObviousActionEmailAndLink() {
        XCTAssertEqual(
            ObviousActionDetector.detect(in: "hello@example.com", kind: .email),
            .composeEmail("hello@example.com")
        )
        guard case .openURL(let https)? = ObviousActionDetector.detect(in: "https://example.com/path", kind: .link) else {
            return XCTFail("expected openURL for https link")
        }
        XCTAssertEqual(https.absoluteString, "https://example.com/path")
        guard case .openURL(let www)? = ObviousActionDetector.detect(in: "www.example.com", kind: .link) else {
            return XCTFail("expected openURL for www link")
        }
        XCTAssertEqual(www.absoluteString, "https://www.example.com")
    }

    func testObviousActionURLHelpers() {
        let email = ObviousAction.composeEmail("a@b.co")
        XCTAssertEqual(email.urlToOpen?.absoluteString, "mailto:a@b.co")
        let maps = ObviousAction.openInMaps("1 Infinite Loop, Cupertino, CA")
        XCTAssertEqual(maps.urlToOpen?.host, "maps.apple.com")
        XCTAssertTrue(maps.urlToOpen?.query?.contains("q=") == true)
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let cal = ObviousAction.addToCalendar(start: start, end: start.addingTimeInterval(3600), title: "Demo, test")
        let ics = cal.calendarICS()
        XCTAssertNotNil(ics)
        XCTAssertTrue(ics?.contains("BEGIN:VEVENT") == true)
        XCTAssertTrue(ics?.contains("SUMMARY:Demo\\, test") == true)
        XCTAssertNil(email.calendarICS())
    }

    func testObviousActionSkipsCodeAndLongProse() {
        XCTAssertNil(ObviousActionDetector.detect(in: "March 15, 2026 at 3:00 PM", kind: .code))
        let prose = String(repeating: "tomorrow at 3pm is fine. ", count: 40)
        XCTAssertNil(ObviousActionDetector.detect(in: prose, kind: .text))
    }

    func testObviousActionAddressAndDate() {
        let address = "1 Infinite Loop, Cupertino, CA 95014"
        guard case .openInMaps(let query)? = ObviousActionDetector.detect(in: address, kind: .text) else {
            return XCTFail("expected Open in Maps for address")
        }
        XCTAssertTrue(query.contains("Cupertino"))

        let dateText = "March 15, 2026 at 3:00 PM"
        guard case .addToCalendar(let start, _, _)? = ObviousActionDetector.detect(in: dateText, kind: .text) else {
            return XCTFail("expected Add to Calendar for date")
        }
        let components = Calendar.current.dateComponents([.year, .month, .day], from: start)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 3)
        XCTAssertEqual(components.day, 15)
    }
}
