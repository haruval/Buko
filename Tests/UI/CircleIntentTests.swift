import XCTest

final class CircleIntentTests: XCTestCase {
    @MainActor func testMissingInformationCannotBeDisabled() {
        continueAfterFailure = false
        let app = XCUIApplication()
        // A persisted value from the removed development setting must not expose
        // or disable the production pipeline.
        app.launchArguments = ["-structuredGapRetrievalEnabled", "NO"]
        app.launch()
        XCTAssertTrue(app.buttons["openSettings"].waitForExistence(timeout: 15))
        app.buttons["openSettings"].tap()
        Thread.sleep(forTimeInterval: 0.8)
        app.buttons["openDevelopment"].tap()
        XCTAssertTrue(app.buttons["recreateTestNote"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.switches["structuredGapRetrieval"].exists)
        XCTAssertFalse(app.staticTexts["Find missing information"].exists)
    }

    @MainActor func testDevelopmentResetAndCircleTool() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--canvasGestureTestArea"]
        app.launch()
        let canvas = app.descendants(matching: .any)["Note canvas"].firstMatch
        XCTAssertTrue(canvas.waitForExistence(timeout: 10))
        if app.buttons["Hide notes"].exists { app.buttons["Hide notes"].tap() }
        app.buttons["openSettings"].tap()
        Thread.sleep(forTimeInterval: 0.8)
        XCTAssertFalse(app.buttons["Close settings"].exists)
        XCTAssertTrue(app.buttons["openDevelopment"].exists)
        let menu = app.descendants(matching: .any)["settingsPanel"].firstMatch
        XCTAssertLessThanOrEqual(menu.frame.width, 250)
        XCTAssertLessThanOrEqual(menu.frame.height, 240)
        app.buttons["openDevelopment"].tap()
        Thread.sleep(forTimeInterval: 0.7)
        app.buttons["recreateTestNote"].tap()
        expectation(for: NSPredicate(format: "value == 'Page 1 of 4'"), evaluatedWith: canvas)
        waitForExpectations(timeout: 10)
        XCTAssertTrue((app.textFields["currentNoteTitle"].value as? String)?.contains("Test PPL Lecture") == true)
        app.buttons["circleIntentTool"].tap()
        XCTAssertTrue(app.buttons["circleIntentTool"].isSelected)
        // A straight one-finger drag in the circle tool cancels, leaves no ink,
        // and does not move the notebook or start inference.
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.4))
            .press(forDuration: 0.05, thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.4)))
        XCTAssertFalse(app.otherElements["intentPopup"].exists)
        XCTAssertFalse(app.buttons["Undo"].isEnabled)
        XCTAssertEqual(canvas.value as? String, "Page 1 of 4")
        app.buttons["Pen"].tap()
        app.buttons["openSettings"].tap()
        Thread.sleep(forTimeInterval: 0.8)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["openSettings"].waitForExistence(timeout: 3))
        // A real native pinch still works after circle input arbitration.
        app.descendants(matching: .any)["Canvas zoom test area"].pinch(withScale: 0.5, velocity: -0.8)
        expectation(for: NSPredicate(format: "value CONTAINS 'overview'"), evaluatedWith: canvas)
        waitForExpectations(timeout: 8)
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)).tap()
        expectation(for: NSPredicate(format: "NOT (value CONTAINS 'overview')"), evaluatedWith: canvas)
        waitForExpectations(timeout: 8)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Handwritten PPL fixture and circle tool"
        shot.lifetime = .keepAlways
        add(shot)
        app.terminate(); app.launch()
        XCTAssertTrue(canvas.waitForExistence(timeout: 10))
        XCTAssertTrue((canvas.value as? String)?.contains("of 4") == true)
    }
}
