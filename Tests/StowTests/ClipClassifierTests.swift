import XCTest

final class ClipClassifierTests: XCTestCase {
    func testEmailLinkAndColor() {
        XCTAssertEqual(ClipClassifier.classify(text: "ada@example.com", html: nil, hasRTF: false, hasImage: false, fileURLs: []), .email)
        XCTAssertEqual(ClipClassifier.classify(text: "https://stow.example/path", html: nil, hasRTF: false, hasImage: false, fileURLs: []), .link)
        XCTAssertEqual(ClipClassifier.classify(text: "#336699", html: nil, hasRTF: false, hasImage: false, fileURLs: []), .color)
    }

    func testProseStaysText() {
        let prose = "Please review the notes and return the form tomorrow."
        XCTAssertEqual(ClipClassifier.classify(text: prose, html: nil, hasRTF: false, hasImage: false, fileURLs: []), .text)
    }

    func testCodeAndJSON() {
        let code = "func add() {\n  return 1\n}\n"
        XCTAssertEqual(ClipClassifier.classify(text: code, html: nil, hasRTF: false, hasImage: false, fileURLs: []), .code)
        let json = "{\n  \"name\": \"Stow\"\n}\n"
        XCTAssertEqual(ClipClassifier.classify(text: json, html: nil, hasRTF: false, hasImage: false, fileURLs: []), .code)
    }

    func testImageAndFileWin() {
        XCTAssertEqual(ClipClassifier.classify(text: "caption", html: nil, hasRTF: false, hasImage: true, fileURLs: []), .image)
        XCTAssertEqual(ClipClassifier.classify(text: "/tmp/a.txt", html: nil, hasRTF: false, hasImage: false, fileURLs: ["/tmp/a.txt"]), .file)
    }

    func testRichText() {
        XCTAssertEqual(ClipClassifier.classify(text: "Hello", html: "<b>Hello</b>", hasRTF: false, hasImage: false, fileURLs: []), .richText)
    }
}
