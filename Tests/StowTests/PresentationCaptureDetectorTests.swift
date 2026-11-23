import XCTest

final class PresentationCaptureDetectorTests: XCTestCase {
    func testScreenshotUIIsActive() {
        let windows = [
            PresentationCaptureDetector.WindowInfo(
                ownerName: "Screenshot",
                windowName: "",
                bundleID: "com.apple.screencaptureui"
            ),
        ]
        XCTAssertTrue(PresentationCaptureDetector.isActive(windows: windows))
    }

    func testScreenSharingTitleIsActive() {
        let windows = [
            PresentationCaptureDetector.WindowInfo(
                ownerName: "zoom.us",
                windowName: "You are sharing your screen",
                bundleID: "us.zoom.xos"
            ),
        ]
        XCTAssertTrue(PresentationCaptureDetector.isActive(windows: windows))
    }

    func testZoomIdleMeetingIsNotActive() {
        let windows = [
            PresentationCaptureDetector.WindowInfo(
                ownerName: "zoom.us",
                windowName: "Zoom Meeting",
                bundleID: "us.zoom.xos"
            ),
        ]
        XCTAssertFalse(PresentationCaptureDetector.isActive(windows: windows))
    }

    func testOrdinaryAppsAreNotActive() {
        let windows = [
            PresentationCaptureDetector.WindowInfo(
                ownerName: "Safari",
                windowName: "Apple",
                bundleID: "com.apple.Safari"
            ),
            PresentationCaptureDetector.WindowInfo(
                ownerName: "TextEdit",
                windowName: "Untitled",
                bundleID: "com.apple.TextEdit"
            ),
        ]
        XCTAssertFalse(PresentationCaptureDetector.isActive(windows: windows))
    }

    func testOBSIsActive() {
        let windows = [
            PresentationCaptureDetector.WindowInfo(
                ownerName: "OBS",
                windowName: "OBS 30",
                bundleID: "com.obsproject.obs-studio"
            ),
        ]
        XCTAssertTrue(PresentationCaptureDetector.isActive(windows: windows))
    }
}
