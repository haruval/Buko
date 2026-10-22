import XCTest

final class AutofillInteractionTests: XCTestCase {
    @MainActor func testAcceptDeclineAndNativeEditing() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--preview", "--undo-controls"]
        app.launch()
        XCTAssertTrue(app.buttons["acceptAutofill"].waitForExistence(timeout: 15))
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: app.buttons["acceptAutofill"])
        waitForExpectations(timeout: 15)
        app.buttons["declineAutofill"].tap()
        XCTAssertFalse(app.buttons["acceptAutofill"].exists)
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["acceptAutofill"].waitForExistence(timeout: 15))
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: app.buttons["acceptAutofill"])
        waitForExpectations(timeout: 15)
        app.buttons["acceptAutofill"].tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.buttons["acceptAutofill"])
        waitForExpectations(timeout: 5)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.7))
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.7)))
        app.buttons["Validation undo"].tap()
        XCTAssertEqual(app.staticTexts["validationUndoStatus"].label, "Edited")
        app.buttons["Validation undo"].tap()
        XCTAssertEqual(app.staticTexts["validationUndoStatus"].label, "Original restored")
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["acceptAutofill"].waitForExistence(timeout: 15))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.7))
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.7)))
        XCTAssertFalse(app.buttons["acceptAutofill"].exists, "Real drawing must dismiss the staged preview")
        let resurrected = expectation(for: NSPredicate(format: "exists == true"), evaluatedWith: app.buttons["acceptAutofill"])
        resurrected.isInverted = true
        waitForExpectations(timeout: 9)
    }

    @MainActor func testAutomaticHandwritingWithoutSetup() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["acceptAutofill"].waitForExistence(timeout: 15))
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: app.buttons["acceptAutofill"])
        waitForExpectations(timeout: 15)
        XCTAssertFalse(app.buttons["sampleAutofillHandwriting"].exists)
        XCTAssertTrue(app.staticTexts["autofillHandwritingSource"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Automatic note handwriting and inline definition"; screenshot.lifetime = .keepAlways; add(screenshot)
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: app.buttons["acceptAutofill"])
        waitForExpectations(timeout: 15)
        app.buttons["acceptAutofill"].tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.buttons["acceptAutofill"])
        waitForExpectations(timeout: 5)
    }

    @MainActor func testDarkPreviewRotation() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--preview", "--dark"]
        app.launch()
        XCTAssertTrue(app.buttons["acceptAutofill"].waitForExistence(timeout: 15))
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        XCTAssertTrue(app.buttons["acceptAutofill"].waitForExistence(timeout: 5))
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: app.buttons["acceptAutofill"])
        waitForExpectations(timeout: 15)
        Thread.sleep(forTimeInterval: 1.2) // Let the system rotation animation settle before visual evidence.
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Green handwriting preview in dark landscape"; screenshot.lifetime = .keepAlways; add(screenshot)
        app.buttons["declineAutofill"].tap()
        XCTAssertFalse(app.buttons["acceptAutofill"].exists)
    }
}
