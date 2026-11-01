import XCTest

final class CanvasRefinementTests: XCTestCase {
    @MainActor
    func testHardScrollRequiresFreshPullAndInlineTitlePersists() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--canvasGestureTestArea"]
        app.launch()
        let canvas = app.descendants(matching: .any)["Note canvas"].firstMatch
        XCTAssertTrue(canvas.waitForExistence(timeout: 10))
        if app.buttons["Show notes"].exists { app.buttons["Show notes"].tap() }
        app.buttons["New note"].tap()
        app.buttons["Hide notes"].tap()
        Thread.sleep(forTimeInterval: 0.7)

        let title = app.textFields["currentNoteTitle"]
        let oldTitle = title.value as! String
        let width = title.frame.width
        title.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        let newTitle = "Lecture " + UUID().uuidString.prefix(6)
        title.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: oldTitle.count) + newTitle + "\n")
        XCTAssertEqual(title.value as? String, newTitle)
        XCTAssertEqual(title.frame.width, width, accuracy: 1)
        app.buttons["Settings"].tap()
        Thread.sleep(forTimeInterval: 0.7)
        XCTAssertEqual(title.frame.width, width, accuracy: 1)
        XCTAssertTrue(app.switches["gridLines"].exists)
        XCTAssertFalse(app.staticTexts["Enable infinite canvas (experimental)"].exists)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        // A single hard drag reaches the bottom, even with sustained overshoot.
        drag(canvas, velocity: .fast, hold: 0.8)
        Thread.sleep(forTimeInterval: 1)
        XCTAssertEqual(canvas.value as? String, "Page 1 of 1")
        XCTAssertFalse(app.staticTexts["Release to create page"].exists)

        // Lift, then deliberately pull again from the settled bottom.
        // The recording must show the release cue and unchanged 1/1 count for
        // this entire hold, followed by exactly one append when the finger lifts.
        drag(canvas, velocity: .slow, hold: 2)
        expect("Page 2 of 2", on: canvas)
        Thread.sleep(forTimeInterval: 0.8)
        drag(canvas, velocity: .fast, hold: 0)
        Thread.sleep(forTimeInterval: 1.2)
        XCTAssertEqual(canvas.value as? String, "Page 2 of 2")
        drag(canvas, velocity: .slow, hold: 0.3)
        expect("Page 3 of 3", on: canvas)

        XCUIDevice.shared.press(.home)
        app.terminate()
        app.launch()
        expect("Page 3 of 3", on: canvas)
        app.buttons["Hide notes"].tap()
        XCTAssertEqual(title.value as? String, newTitle)
        Thread.sleep(forTimeInterval: 0.8) // Pinch must begin after the sidebar leaves its touch area.
        app.descendants(matching: .any)["Canvas zoom test area"].pinch(withScale: 0.5, velocity: -0.5)
        expectation(for: NSPredicate(format: "value CONTAINS 'overview'"), evaluatedWith: canvas)
        waitForExpectations(timeout: 5)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Crisp overview after screen-edge bezel transition"
        shot.lifetime = .keepAlways
        add(shot)
    }

    @MainActor private func drag(_ canvas: XCUIElement, velocity: XCUIGestureVelocity, hold: TimeInterval) {
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.72, dy: 0.85))
            .press(forDuration: 0.05, thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.72, dy: 0.15)),
                   withVelocity: velocity, thenHoldForDuration: hold)
    }

    @MainActor private func expect(_ value: String, on canvas: XCUIElement) {
        expectation(for: NSPredicate(format: "value == %@", value), evaluatedWith: canvas)
        waitForExpectations(timeout: 8)
    }
}
