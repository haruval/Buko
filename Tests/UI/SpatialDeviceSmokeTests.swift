import XCTest

/// Fresh-install packaging checks for both Buko and Experiment configurations.
/// Does not establish physical Pencil/model quality.
final class SpatialDeviceSmokeTests: XCTestCase {
    @MainActor func testBlankManualAppAndBaselineRelaunch() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons.matching(identifier: "newNote").firstMatch.waitForExistence(timeout: 20))
        XCTAssertFalse(app.buttons["spatialSetup"].exists)
        XCTAssertFalse(app.buttons["spatialCapture"].exists)
        XCTAssertEqual(app.buttons.matching(identifier: "noteRow").allElementsBoundByIndex.filter(\.isHittable).count, 1)
        for title in ["Test PPL Lecture", "Test Operating Systems Lecture", "Test Linear Algebra Lecture", "Test Biology 101 Lecture"] {
            XCTAssertFalse(app.buttons[title].exists)
        }
        XCTAssertFalse(app.buttons["circleIntentTool"].exists)
        app.buttons["openSettings"].tap()
        XCTAssertTrue(app.buttons["openDevelopment"].waitForExistence(timeout: 5))
        app.buttons["openDevelopment"].tap()
        XCTAssertTrue(app.switches["showGestureTestTools"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.switches["showGestureTestTools"].value as? String, "0")
        XCTAssertEqual(app.switches["detailedPreview"].value as? String, "0")
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Recreate '")).count, 0)
        let picture = XCTAttachment(screenshot: app.screenshot())
        picture.name = "Publishing defaults and development settings"; picture.lifetime = .keepAlways; add(picture)
        app.terminate()
        app.launchArguments = ["--spatial-baseline"]
        app.launch()
        XCTAssertTrue(app.buttons.matching(identifier: "newNote").firstMatch.waitForExistence(timeout: 20))
        XCTAssertEqual(app.buttons.matching(identifier: "noteRow").allElementsBoundByIndex.filter(\.isHittable).count, 1)
        XCTAssertFalse(app.buttons["circleIntentTool"].exists)
        XCTAssertFalse(app.buttons["spatialSetup"].exists)
        XCTAssertFalse(app.buttons["spatialCapture"].exists)
    }
}
