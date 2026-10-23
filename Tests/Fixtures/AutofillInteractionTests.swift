import XCTest

final class AutofillInteractionTests: XCTestCase {
    @MainActor func testColdHandwritingUsesImmediateFallback() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--cold-handwriting", "-detailedAutofillPreview", "NO"]
        app.launch()
        XCTAssertTrue(app.buttons["acceptAutofill"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["acceptAutofill"].isEnabled)
        XCTAssertFalse(app.staticTexts["Matching your handwriting…"].exists)
        XCTAssertFalse(app.staticTexts["autofillHandwritingSource"].exists)
        app.buttons["declineAutofill"].tap()
        XCTAssertFalse(app.buttons["acceptAutofill"].exists)
    }

    @MainActor func testCompactProgressAndExactSources() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--sourced-preview", "--pipeline-preview", "-detailedAutofillPreview", "NO"]
        app.launch()
        let title = app.staticTexts["autofillPreviewTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        XCTAssertEqual(title.label, "Thinking…")
        expectation(for: NSPredicate(format: "label == 'Defining Parsing…'"), evaluatedWith: title)
        waitForExpectations(timeout: 12)
        XCTAssertFalse(app.buttons["acceptAutofill"].exists)
        Thread.sleep(forTimeInterval: 0.6)
        let popup = app.descendants(matching: .any)["intentPopup"].firstMatch
        let compactHeight = popup.frame.height
        XCTAssertLessThan(compactHeight, 110, "A short processing label needs balanced padding, not an empty tall card")
        XCTAssertGreaterThan(popup.frame.width, compactHeight * 2)
        let compact = XCTAttachment(screenshot: app.screenshot())
        compact.name = "Content-sized defining stage"; compact.lifetime = .keepAlways; add(compact)
        XCTAssertTrue(app.buttons["acceptAutofill"].waitForExistence(timeout: 20))
        Thread.sleep(forTimeInterval: 0.8)
        XCTAssertGreaterThan(popup.frame.height, compactHeight + 60)
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: app.buttons["acceptAutofill"])
        waitForExpectations(timeout: 15)
        XCTAssertTrue(title.label.hasPrefix("Autofilled from "))
        XCTAssertFalse(app.descendants(matching: .any)["detailedAutofillContent"].exists)
        let passages = app.descendants(matching: .any).matching(identifier: "autofillSourcePassage")
        let hierarchy = XCTAttachment(string: app.debugDescription); hierarchy.lifetime = .keepAlways; add(hierarchy)
        XCTAssertEqual(passages.count, 1,
                       "Only passages referenced by the draft belong in the simple preview")
        XCTAssertGreaterThan(passages.firstMatch.label.count, 40)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Compact autofill with exact source passage"; screenshot.lifetime = .keepAlways; add(screenshot)
        app.buttons["autofillSourceLink"].firstMatch.tap()
        XCTAssertTrue(app.buttons["closeLecturePDF"].waitForExistence(timeout: 5))
        app.buttons["closeLecturePDF"].tap()
        app.buttons["declineAutofill"].tap()
        XCTAssertFalse(app.buttons["acceptAutofill"].exists)
    }

    @MainActor func testDetailedResultsRetainPipelineAndInputs() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--sourced-preview", "-detailedAutofillPreview", "YES"]
        app.launch()
        XCTAssertTrue(app.buttons["acceptAutofill"].waitForExistence(timeout: 20))
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: app.buttons["acceptAutofill"])
        waitForExpectations(timeout: 15)
        XCTAssertTrue(app.descendants(matching: .any)["detailedAutofillContent"].exists)
        let hierarchy = XCTAttachment(string: app.debugDescription); hierarchy.lifetime = .keepAlways; add(hierarchy)
        let stage = app.descendants(matching: .any)["pipelineStep.intent"].firstMatch
        XCTAssertTrue(stage.exists); stage.tap()
        XCTAssertTrue(app.staticTexts["pipelineInput.intent"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["pipelineInput.intent"].label.contains("nearby_handwriting_context_only"))
        XCTAssertTrue(app.staticTexts["inferredIntent"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["retrievedLecturePassages"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Detailed preview retains pipeline and prompt input"; screenshot.lifetime = .keepAlways; add(screenshot)
        app.buttons["declineAutofill"].tap()
    }

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
        XCTAssertFalse(app.staticTexts["autofillHandwritingSource"].exists)
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
