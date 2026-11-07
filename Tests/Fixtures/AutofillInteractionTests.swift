import XCTest

final class AutofillInteractionTests: XCTestCase {
    @MainActor func testPreviewTitleDragKeepsControlsAndInkSafe() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--sourced-preview", "--undo-controls", "-detailedAutofillPreview", "NO"]
        app.launch()
        let title = app.staticTexts["autofillPreviewTitle"]
        let accept = app.buttons["acceptAutofill"]
        XCTAssertTrue(accept.waitForExistence(timeout: 20))
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: accept)
        waitForExpectations(timeout: 15)
        Thread.sleep(forTimeInterval: 0.6)
        let before = title.frame
        let start = title.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: -220, dy: 120)))
        Thread.sleep(forTimeInterval: 0.5)
        XCTAssertLessThan(title.frame.minX, before.minX - 100)
        XCTAssertGreaterThan(title.frame.minY, before.minY + 60)
        let landing = title.frame.origin
        XCTAssertLessThanOrEqual(hypot(landing.x - (before.minX - 220), landing.y - (before.minY + 120)), 47)
        XCTAssertTrue(accept.isEnabled, "Dragging the title must not edit ink or dismiss the proposal")
        app.buttons["autofillSourceLink"].firstMatch.tap()
        XCTAssertTrue(app.buttons["closeLecturePDF"].waitForExistence(timeout: 5))
        app.buttons["closeLecturePDF"].tap()
        XCTAssertEqual(title.frame.minX, landing.x, accuracy: 3)
        XCTAssertEqual(title.frame.minY, landing.y, accuracy: 3)
        accept.tap()
        XCTAssertFalse(accept.waitForExistence(timeout: 1))
        app.buttons["Validation undo"].tap()
        XCTAssertEqual(app.staticTexts["validationUndoStatus"].label, "Original restored", "Moving and tapping the popup cannot leave stray ink")
    }
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
        XCTAssertTrue(title.waitForExistence(timeout: 30))
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
        XCTAssertEqual(title.label, "Sources")
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label == 'Sources'")).count, 1)
        for control in [app.buttons["declineAutofill"], app.buttons["acceptAutofill"]] {
            XCTAssertGreaterThanOrEqual(control.frame.height, 44)
        }
        XCTAssertFalse(app.descendants(matching: .any)["detailedAutofillContent"].exists)
        let links = app.buttons.matching(identifier: "autofillSourceLink")
        let hierarchy = XCTAttachment(string: app.debugDescription); hierarchy.lifetime = .keepAlways; add(hierarchy)
        XCTAssertEqual(links.count, 1, "Only sources cited by the draft belong in the compact preview")
        XCTAssertFalse(app.staticTexts["autofillSourcePassage"].exists)
        expectation(for: NSPredicate(format: "label CONTAINS 'highlighted'"), evaluatedWith: links.firstMatch)
        waitForExpectations(timeout: 10)
        XCTAssertGreaterThan((links.firstMatch.value as? String ?? "").count, 40)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Compact autofill with highlighted PDF thumbnail"; screenshot.lifetime = .keepAlways; add(screenshot)
        links.firstMatch.tap()
        XCTAssertTrue(app.buttons["closeLecturePDF"].waitForExistence(timeout: 5))
        app.buttons["closeLecturePDF"].tap()
        app.buttons["declineAutofill"].tap()
        XCTAssertFalse(app.buttons["acceptAutofill"].exists)
    }

    @MainActor func testDetailedResultsRetainPipelineAndInputs() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--sourced-preview", "--cold-handwriting", "-detailedAutofillPreview", "YES"]
        app.launch()
        XCTAssertTrue(app.buttons["acceptAutofill"].waitForExistence(timeout: 20))
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: app.buttons["acceptAutofill"])
        waitForExpectations(timeout: 15)
        XCTAssertTrue(app.descendants(matching: .any)["detailedAutofillContent"].exists)
        XCTAssertGreaterThan(app.staticTexts.matching(identifier: "autofillSourcePassage").firstMatch.label.count, 40)
        XCTAssertFalse(app.staticTexts["autofillHandwritingSource"].exists)
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
        // Writing below the captured selection now preserves and rebases the fill.
        XCTAssertTrue(app.buttons["acceptAutofill"].exists, "Outside ink must preserve the staged preview")
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: app.buttons["acceptAutofill"])
        waitForExpectations(timeout: 15)
        app.buttons["acceptAutofill"].tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.buttons["acceptAutofill"])
        waitForExpectations(timeout: 5)
        app.buttons["Validation undo"].tap()
        XCTAssertEqual(app.staticTexts["validationUndoStatus"].label, "Edited", "Undoing the fill must retain the new outside ink")
        app.buttons["Validation undo"].tap()
        expectation(for: NSPredicate(format: "label == 'Original restored'"), evaluatedWith: app.staticTexts["validationUndoStatus"])
        waitForExpectations(timeout: 5)
        let status = app.staticTexts["validationUndoStatus"]
        app.buttons["Validation redo"].tap()
        expectation(for: NSPredicate(format: "value == 'Before fill'"), evaluatedWith: status)
        waitForExpectations(timeout: 5)
        app.buttons["Validation redo"].tap()
        expectation(for: NSPredicate(format: "value == 'With fill'"), evaluatedWith: status)
        waitForExpectations(timeout: 5)
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
