import XCTest

/// Packaging checks only. Does not establish physical Pencil/model quality.
final class SpatialDeviceSmokeTests: XCTestCase {
    @MainActor func testBlankManualAppAndBaselineRelaunch() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["New note"].waitForExistence(timeout: 20))
        XCTAssertFalse(app.buttons["spatialSetup"].exists)
        XCTAssertFalse(app.buttons["spatialCapture"].exists)
        XCTAssertEqual(app.buttons.matching(identifier: "noteRow").count, 1)
        for title in ["Test PPL Lecture", "Test Operating Systems Lecture", "Test Linear Algebra Lecture", "Test Biology 101 Lecture"] {
            XCTAssertFalse(app.buttons[title].exists)
        }
        let picture = XCTAttachment(screenshot: app.screenshot())
        picture.name = "Blank isolated manual app"; picture.lifetime = .keepAlways; add(picture)
        app.terminate()
        app.launchArguments = ["--spatial-baseline"]
        app.launch()
        XCTAssertTrue(app.buttons["New note"].waitForExistence(timeout: 20))
        XCTAssertEqual(app.buttons.matching(identifier: "noteRow").count, 1)
        XCTAssertFalse(app.buttons["spatialSetup"].exists)
        XCTAssertFalse(app.buttons["spatialCapture"].exists)
    }
}
