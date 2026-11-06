import XCTest

final class AutofillLibraryTests: XCTestCase {
    @MainActor func testAFolderDragRenameAndPersistence() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication(); app.launch()
        XCTAssertTrue(app.buttons["openSettings"].waitForExistence(timeout: 20))
        if app.buttons["showNotes"].exists { app.buttons["showNotes"].tap() }
        XCTAssertFalse(app.buttons["openBulletinBoard"].exists)
        app.buttons["newNote"].tap()
        Thread.sleep(forTimeInterval: 1)
        app.buttons["newNote"].tap()
        Thread.sleep(forTimeInterval: 1)
        let cards = app.buttons.matching(identifier: "noteRow")
        XCTAssertGreaterThanOrEqual(cards.count, 2)
        let first = cards.element(boundBy: 0)
        let second = cards.allElementsBoundByIndex.first { abs($0.frame.midX - first.frame.midX) > 100 }!
        first.press(forDuration: 1.2, thenDragTo: second)
        let folder = app.buttons["folderCard"].firstMatch
        XCTAssertTrue(folder.waitForExistence(timeout: 8))
        folder.tap()
        let title = app.textFields["folderTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        title.press(forDuration: 1.1)
        if app.menuItems["Select All"].waitForExistence(timeout: 2) { app.menuItems["Select All"].tap() }
        else { title.tap(withNumberOfTaps: 3, numberOfTouches: 1) }
        title.typeText("Semester\n")
        XCTAssertEqual(title.value as? String, "Semester")
        screenshot(app, "Expanded folder inside sidebar")
        app.buttons["folderBack"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier == 'folderCard' AND label CONTAINS 'Semester'")).firstMatch.waitForExistence(timeout: 5))
        app.terminate(); app.launch()
        if app.buttons["showNotes"].waitForExistence(timeout: 3) { app.buttons["showNotes"].tap() }
        let restored = app.buttons.matching(NSPredicate(format: "identifier == 'folderCard' AND label CONTAINS 'Semester'")).firstMatch
        XCTAssertTrue(restored.waitForExistence(timeout: 10))
        screenshot(app, "Two-column glass library landscape")
        restored.tap()
        XCTAssertEqual(app.buttons.matching(identifier: "noteRow").count, 2)
        app.buttons["noteRow"].firstMatch.tap()
        app.buttons["folderBack"].tap()
        XCUIDevice.shared.orientation = .portrait
        Thread.sleep(forTimeInterval: 1)
        screenshot(app, "Two-column glass library portrait")
    }

    @MainActor func testBCircleToolVisibility() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launch()
        XCTAssertTrue(app.buttons["openSettings"].waitForExistence(timeout: 20))
        XCTAssertFalse(app.buttons["circleIntentTool"].exists)
        openGestureSettings(app)
        XCTAssertEqual(app.switches["showGestureTestTools"].value as? String, "0")
        app.switches["showGestureTestTools"].tap()
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.6)).tap()
        XCTAssertTrue(app.buttons["circleIntentTool"].waitForExistence(timeout: 20))
        XCTAssertFalse(app.buttons["bandSelectionTool"].exists)
        app.buttons["circleIntentTool"].tap()
        openGestureSettings(app)
        app.switches["showGestureTestTools"].tap()
        XCTAssertFalse(app.buttons["circleIntentTool"].exists)
        XCTAssertTrue(app.buttons["Pen"].isSelected)
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["openSettings"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["circleIntentTool"].exists)
        openGestureSettings(app)
        app.switches["showGestureTestTools"].tap()
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.6)).tap()
        XCTAssertTrue(app.buttons["circleIntentTool"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["bandSelectionTool"].exists)
        openGestureSettings(app)
        app.switches["showGestureTestTools"].tap()
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.6)).tap()
        XCTAssertFalse(app.buttons["circleIntentTool"].exists)
    }

    @MainActor func testCHeadingWithNearbyDeadlineUsesAutofill() {
        checkCircle(argument: "--circle-heading", expectedWords: ["closure"], requireRetrieval: true)
    }

    @MainActor func testDDeadlineQuestionUsesAutofillPlanning() {
        checkCircle(argument: "--circle-question", expectedWords: ["review", "exam"], requireRetrieval: false)
    }

    @MainActor func testECompletedContextAndHeadingUsesAutofill() {
        checkCircle(argument: "--circle-parallel", expectedWords: ["tokens", "parsing"], requireRetrieval: true)
    }

    @MainActor private func checkCircle(argument: String, expectedWords: [String], requireRetrieval: Bool) {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = [argument, "-detailedAutofillPreview", "NO"]
        app.launch()
        XCTAssertTrue(app.buttons["captureCircleFixture"].waitForExistence(timeout: 20))
        app.buttons["captureCircleFixture"].tap()
        XCTAssertTrue(app.staticTexts["circleFixtureResult"].waitForExistence(timeout: 90))
        let recognized = app.staticTexts["circleFixtureRecognition"].label.lowercased()
        let stages = app.staticTexts["circleFixtureStages"].label
        for word in expectedWords { XCTAssertTrue(recognized.contains(word), recognized) }
        XCTAssertTrue(stages.contains("binding") || stages.contains("intent"), "Must enter the autofill planner: \(stages)")
        XCTAssertFalse(stages.contains("circleAction"))
        XCTAssertFalse(stages.contains("bulletin"))
        if requireRetrieval { XCTAssertTrue(stages.contains("retrieval"), stages) }
        if argument == "--circle-parallel" { XCTAssertTrue(recognized.contains("\n"), recognized) }
        XCTAssertFalse(app.buttons["acceptAutofill"].exists, "No attached evidence must not produce an insertion")
        XCTAssertFalse(app.otherElements["bulletinPreviewContent"].exists)
        XCTAssertTrue(app.staticTexts["circleFixtureInkIntact"].exists)
        screenshot(app, "Circle enters autofill directly — " + argument)
        app.buttons["Dismiss autofill"].tap()
        XCTAssertFalse(app.otherElements["intentPopup"].exists)
        XCTAssertTrue(app.staticTexts["circleFixtureInkIntact"].exists)
    }

    @MainActor private func openGestureSettings(_ app: XCUIApplication) {
        app.buttons["openSettings"].tap()
        XCTAssertTrue(app.buttons["openDevelopment"].waitForExistence(timeout: 5))
        app.buttons["openDevelopment"].tap()
        XCTAssertTrue(app.switches["showGestureTestTools"].waitForExistence(timeout: 5))
    }

    @MainActor private func screenshot(_ app: XCUIApplication, _ title: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = title; attachment.lifetime = .keepAlways; add(attachment)
    }
}
