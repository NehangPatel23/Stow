import XCTest

final class ColorValueTests: XCTestCase {
    func testShortHex() {
        let color = ColorValue.parse("#fff")
        XCTAssertEqual(color?.hex, "#FFFFFF")
    }

    func testRGBAndHSLRoundTrip() {
        let color = ColorValue.parse("rgb(255, 128, 0)")
        XCTAssertEqual(color?.hex, "#FF8000")
        XCTAssertEqual(color?.rgbString(), "rgb(255, 128, 0)")
        let hsl = color?.hslString() ?? ""
        XCTAssertTrue(hsl.hasPrefix("hsl("))
        let parsed = ColorValue.parse("hsl(30, 100%, 50%)")
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.hex, "#FF8000")
    }

    func testRejectsProse() {
        XCTAssertNil(ColorValue.parse("not a color"))
        XCTAssertNil(ColorValue.parse("#12"))
    }
}
