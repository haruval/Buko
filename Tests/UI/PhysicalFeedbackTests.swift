import XCTest

final class PhysicalFeedbackTests: XCTestCase {
    @MainActor func testPinchStillEntersOverviewAndTapReturnsToWriting() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--canvasGestureTestArea"]
        app.launch()
        if app.buttons["hideNotes"].waitForExistence(timeout: 10) { app.buttons["hideNotes"].tap() }
        Thread.sleep(forTimeInterval: 0.8)
        app.descendants(matching: .any)["Canvas zoom test area"].pinch(withScale: 0.5, velocity: -0.5)
        let canvas = app.descendants(matching: .any)["Note canvas"].firstMatch
        expectation(for: NSPredicate(format: "value CONTAINS 'overview'"), evaluatedWith: canvas)
        waitForExpectations(timeout: 8)
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)).tap()
        expectation(for: NSPredicate(format: "NOT (value CONTAINS 'overview')"), evaluatedWith: canvas)
        waitForExpectations(timeout: 8)
    }
    @MainActor func testAlphabetSaveRelaunchAndImmediateScan() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--alphabetFingerTesting"]
        app.launch()
        openAlphabet(app)
        app.buttons["rewriteAlphabet.a"].tap()
        let canvas = app.descendants(matching: .any)["alphabetCanvas.a"].firstMatch
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.7))
            .press(forDuration: 0.05, thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.3)))
        let source = app.staticTexts["alphabetSource.a"]
        expectation(for: NSPredicate(format: "label == 'Your alphabet'"), evaluatedWith: source)
        waitForExpectations(timeout: 8)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.lifetime = .keepAlways; add(shot)
        app.buttons["closeAlphabet"].tap()
        app.terminate(); app.launch()
        openAlphabet(app)
        XCTAssertEqual(app.staticTexts["alphabetSource.a"].label, "Your alphabet")
        app.buttons["closeAlphabet"].tap()
        let scan = app.buttons["scanHandwritingNow"]
        if !scan.isHittable { app.swipeUp() }
        XCTAssertTrue(scan.waitForExistence(timeout: 5)); scan.tap()
        XCTAssertTrue(app.buttons["previewHandwriting"].exists)
    }

    @MainActor private func openAlphabet(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["openSettings"].waitForExistence(timeout: 15))
        app.buttons["openSettings"].tap()
        XCTAssertTrue(app.buttons["openDevelopment"].waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 0.8)
        app.buttons["openDevelopment"].tap()
        Thread.sleep(forTimeInterval: 0.5)
        let button = app.buttons["writeAlphabet"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        if !button.isHittable { app.scrollViews.containing(.button, identifier: "writeAlphabet").firstMatch.swipeUp() }
        button.tap()
        XCTAssertTrue(app.buttons["closeAlphabet"].waitForExistence(timeout: 5))
    }
}
