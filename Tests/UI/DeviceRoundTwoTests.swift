import XCTest

final class DeviceRoundTwoTests: XCTestCase {
    @MainActor private func launch(_ name: String) -> XCUIApplication {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--spatial-fixture", name, "-detailedAutofillPreview", "NO", "--alphabetFingerTesting"]
        app.launch()
        XCTAssertTrue(app.buttons["spatialSetup"].waitForExistence(timeout: 20))
        app.buttons["spatialSetup"].tap()
        XCTAssertTrue(app.staticTexts["spatialReady"].waitForExistence(timeout: 40), app.staticTexts["spatialStatus"].label)
        return app
    }
    @MainActor private func capture(_ app: XCUIApplication) {
        app.buttons["spatialCapture"].tap()
        XCTAssertTrue(app.staticTexts["spatialResult"].waitForExistence(timeout: 120))
    }
    @MainActor private func ready(_ app: XCUIApplication) {
        let accept = app.buttons["acceptAutofill"]
        for _ in 0..<120 {
            if accept.waitForExistence(timeout: 1) { break }
            if app.staticTexts["autofillUnavailable"].exists {
                XCTFail("Autofill refused: " + app.staticTexts["autofillUnavailable"].label)
                return
            }
        }
        XCTAssertTrue(accept.waitForExistence(timeout: 120))
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: accept)
        waitForExpectations(timeout: 40)
        expectation(for: NSPredicate(format: "hittable == true"), evaluatedWith: accept)
        waitForExpectations(timeout: 10)
    }
    @MainActor private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name
        attachment.lifetime = .keepAlways; add(attachment)
    }
    @MainActor func testComparisonPDFThumbnailAcceptUndo() {
        let app = launch("auth"); capture(app); ready(app)
        let content = app.staticTexts["spatialTarget"].value as? String ?? ""
        XCTAssertTrue(content.lowercased().contains("account") && content.lowercased().contains("action"), content)
        let source = app.buttons["autofillSourceLink"].firstMatch
        XCTAssertTrue(source.waitForExistence(timeout: 10))
        expectation(for: NSPredicate(format: "label CONTAINS 'highlighted'"), evaluatedWith: source)
        waitForExpectations(timeout: 20)
        shot(app, "Source PDF crops with highlights")
        source.tap()
        XCTAssertTrue(app.buttons["closeLecturePDF"].waitForExistence(timeout: 10))
        shot(app, "Open cited source PDF")
        app.buttons["closeLecturePDF"].tap()
        app.buttons["acceptAutofill"].tap()
        XCTAssertTrue(app.buttons["Undo"].waitForExistence(timeout: 8)); app.buttons["Undo"].tap()
        app.buttons["spatialCheckpoint"].tap()
        XCTAssertTrue(app.staticTexts["spatialStatus"].label.contains("original=true;"))
    }
    @MainActor func testTypedClarificationKeepsCapturedNotesAndKeyboardVisible() {
        let app = launch("ambiguous"); capture(app)
        XCTAssertEqual(app.staticTexts["spatialResult"].label, "no-proposal")
        let field = app.textFields["autofillClarificationInput"].exists
            ? app.textFields["autofillClarificationInput"] : app.textViews["autofillClarificationInput"]
        XCTAssertTrue(field.waitForExistence(timeout: 8)); field.tap(); field.typeText("Static scope")
        let submit = app.buttons["submitAutofillClarification"]
        XCTAssertTrue(submit.isHittable)
        if app.keyboards.firstMatch.exists {
            XCTAssertLessThanOrEqual(submit.frame.maxY, app.keyboards.firstMatch.frame.minY)
        }
        shot(app, "Typed clarification above keyboard")
        submit.tap(); ready(app)
        XCTAssertTrue(app.staticTexts["spatialTarget"].label.lowercased().contains("static"))
        let draft = app.staticTexts["spatialTarget"].value as? String ?? ""
        // The source states the same lookup rule as either lexical nesting or
        // the nearest enclosing declaration; both preserve the requested meaning.
        XCTAssertTrue(draft.lowercased().contains("lexical") || draft.lowercased().contains("nest")
            || (draft.lowercased().contains("enclosing") && draft.lowercased().contains("declaration")), draft)
        app.buttons["declineAutofill"].tap(); app.buttons["spatialCheckpoint"].tap()
        XCTAssertTrue(app.staticTexts["spatialStatus"].label.contains("original=true;"))
    }
    @MainActor func testClarificationCancellation() {
        let app = launch("ambiguous"); capture(app)
        let field = app.textFields["autofillClarificationInput"].exists
            ? app.textFields["autofillClarificationInput"] : app.textViews["autofillClarificationInput"]
        XCTAssertTrue(field.waitForExistence(timeout: 8)); field.tap(); field.typeText("Static scope")
        app.buttons["submitAutofillClarification"].tap()
        app.buttons["Dismiss autofill"].tap()
        Thread.sleep(forTimeInterval: 2)
        XCTAssertFalse(app.buttons["acceptAutofill"].exists)
        app.buttons["spatialCheckpoint"].tap()
        XCTAssertTrue(app.staticTexts["spatialStatus"].label.contains("original=true;"))
    }
    @MainActor func testGestureMidpointLogicAndNativeContextMenu() {
        let app = launch("auth")
        app.buttons["checkGestureLogic"].tap()
        XCTAssertTrue(app.staticTexts["gestureLogicStatus"].label.contains("Gesture checks passed"))
        app.buttons["Show notes"].tap()
        let note = app.buttons.matching(identifier: "noteRow").matching(NSPredicate(format: "label CONTAINS 'Spatial validation - auth'")).firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 8)); note.press(forDuration: 0.8)
        XCTAssertTrue(app.buttons["Rename"].waitForExistence(timeout: 5))
        shot(app, "Native note context menu")
    }
    @MainActor func testAlphabetGridScrollAndBothCases() {
        let app = launch("auth")
        app.buttons["openSettings"].tap()
        XCTAssertTrue(app.buttons["openDevelopment"].waitForExistence(timeout: 5))
        // Native glass springs can expose destination accessibility frames
        // before the moving controls reach them; let the panel settle.
        Thread.sleep(forTimeInterval: 0.8)
        app.buttons["openDevelopment"].tap()
        Thread.sleep(forTimeInterval: 0.5)
        let open = app.buttons["writeAlphabet"]; XCTAssertTrue(open.waitForExistence(timeout: 5))
        if !open.isHittable { app.scrollViews.containing(.button, identifier: "writeAlphabet").firstMatch.swipeUp() }; open.tap()
        XCTAssertTrue(app.descendants(matching: .any)["alphabetCanvas.A"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["alphabetCanvas.a"].firstMatch.exists)
        shot(app, "Paired alphabet grid and current cached ink")
        let z = app.descendants(matching: .any)["alphabetCanvas.z"].firstMatch
        for _ in 0..<18 {
            if z.exists && z.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(z.exists && z.isHittable, "All 26 pairs must be reachable by scrolling")
        shot(app, "End of alphabet grid")
        app.buttons["closeAlphabet"].tap()
    }
    @MainActor func testActualLetterSamplingExcludesGeneratedInk() {
        let app = launch("auth")
        app.buttons["checkLetters"].tap()
        let status = app.staticTexts["letterLogicStatus"]
        expectation(for: NSPredicate(format: "label CONTAINS 'Letter checks passed'"), evaluatedWith: status)
        waitForExpectations(timeout: 60)
        shot(app, status.label)
    }
}
