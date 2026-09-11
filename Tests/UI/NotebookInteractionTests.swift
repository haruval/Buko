import XCTest

final class NotebookInteractionTests: XCTestCase {
    @MainActor
    func testStickyZoomReleasesIntoOverview() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--canvasGestureTestArea"]
        app.launch()
        let canvas = app.descendants(matching: .any).matching(identifier: "Note canvas").firstMatch
        XCTAssertTrue(canvas.waitForExistence(timeout: 10))
        if app.buttons["Show notes"].exists { app.buttons["Show notes"].tap() }
        app.buttons["New note"].tap()
        app.buttons["Hide notes"].tap()
        Thread.sleep(forTimeInterval: 0.6)
        let pinchArea = app.descendants(matching: .any)["Canvas zoom test area"]
        // Letting go inside the resistance returns to fit; a short additional
        // squeeze crosses the detent and completes the snap into overview.
        pinchArea.pinch(withScale: 0.95, velocity: -0.2)
        expect("Page 1 of 1", on: canvas)
        pinchArea.pinch(withScale: 0.84, velocity: -0.2)
        expectation(for: NSPredicate(format: "value CONTAINS 'overview'"), evaluatedWith: canvas)
        waitForExpectations(timeout: 5)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Sticky zoom released into sharp overview"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        pinchArea.pinch(withScale: 0.8, velocity: -0.5)
        XCTAssertTrue((canvas.value as? String ?? "").contains("overview"))
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.5)).tap()
        expect("Page 1 of 1", on: canvas)
    }

    @MainActor
    func testLandscapeScrollAndRoundedOverview() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication()
        app.launchArguments = ["--canvasGestureTestArea"]
        app.launch()
        let canvas = app.descendants(matching: .any).matching(identifier: "Note canvas").firstMatch
        XCTAssertTrue(canvas.waitForExistence(timeout: 10))
        if app.buttons["Show notes"].exists { app.buttons["Show notes"].tap() }
        app.buttons["New note"].tap()
        expect("Page 1 of 1", on: canvas)
        app.buttons["Hide notes"].tap()
        Thread.sleep(forTimeInterval: 0.6)
        XCTAssertGreaterThan(canvas.frame.width, canvas.frame.height)

        // A modest landscape scroll stays within the tall portrait-shaped page.
        pull(canvas, from: 0.70, to: 0.45)
        expect("Page 1 of 1", on: canvas)
        for _ in 0..<4 {
            if canvas.value as? String == "Page 2 of 2" { break }
            pull(canvas, from: 0.82, to: 0.18)
        }
        expect("Page 2 of 2", on: canvas)
        app.descendants(matching: .any)["Canvas zoom test area"].pinch(withScale: 0.5, velocity: -1)
        let overview = NSPredicate(format: "value CONTAINS 'overview'")
        expectation(for: overview, evaluatedWith: canvas)
        waitForExpectations(timeout: 5)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Rounded iPad page in landscape overview"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.5)).tap()
        expect("Page 2 of 2", on: canvas)
    }

    @MainActor
    func testPagePullsPersistence() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--canvasGestureTestArea"]
        app.launch()
        let canvas = app.descendants(matching: .any).matching(identifier: "Note canvas").firstMatch
        XCTAssertTrue(canvas.waitForExistence(timeout: 10))

        // Run on an isolated simulator. Start a new note to keep reruns independent.
        if app.buttons["Show notes"].exists { app.buttons["Show notes"].tap() }
        app.buttons["New note"].tap()
        expect("Page 1 of 1", on: canvas)
        if app.buttons["Hide notes"].exists { app.buttons["Hide notes"].tap() }
        app.buttons["Settings"].tap()
        // Accessibility exposes final frames before the expanding glass settles.
        Thread.sleep(forTimeInterval: 1)
        if app.switches["gridLines"].value as? String == "0" { app.switches["gridLines"].tap() }
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        Thread.sleep(forTimeInterval: 0.6)

        pull(canvas, from: 0.60, to: 0.57)
        expect("Page 1 of 1", on: canvas)

        // At page width, scroll within the portrait iPad sheet, then pull beyond its edge.
        for _ in 0..<4 {
            if canvas.value as? String == "Page 2 of 2" { break }
            pull(canvas, from: 0.82, to: 0.18)
        }
        expect("Page 2 of 2", on: canvas)
        pull(canvas, from: 0.20, to: 0.85)
        expect("Page 1 of 2", on: canvas)
        pull(canvas, from: 0.82, to: 0.18)
        expect("Page 2 of 2", on: canvas)

        XCUIDevice.shared.press(.home)
        app.terminate()
        app.launch()
        expect("Page 2 of 2", on: canvas)

        app.buttons["Settings"].tap()
        Thread.sleep(forTimeInterval: 1)
        XCTAssertTrue(app.switches["gridLines"].exists)
        XCTAssertFalse(app.staticTexts["Enable infinite canvas (experimental)"].exists)
        expect("Page 2 of 2", on: canvas)
    }

    @MainActor
    func testThreePagesScrollWithoutInternalCreation() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--canvasGestureTestArea"]
        app.launch()
        let canvas = app.descendants(matching: .any).matching(identifier: "Note canvas").firstMatch
        XCTAssertTrue(canvas.waitForExistence(timeout: 10))
        if app.buttons["Show notes"].exists { app.buttons["Show notes"].tap() }
        app.buttons["New note"].tap()
        app.buttons["Hide notes"].tap()
        Thread.sleep(forTimeInterval: 0.6)
        for count in 2...3 {
            for _ in 0..<4 {
                if canvas.value as? String == "Page \(count) of \(count)" { break }
                pull(canvas, from: 0.82, to: 0.18)
            }
            expect("Page \(count) of \(count)", on: canvas)
        }
        for _ in 0..<4 {
            if canvas.value as? String == "Page 1 of 3" { break }
            pull(canvas, from: 0.18, to: 0.82)
        }
        expect("Page 1 of 3", on: canvas)
        for _ in 0..<4 {
            if canvas.value as? String == "Page 3 of 3" { break }
            pull(canvas, from: 0.82, to: 0.18)
        }
        expect("Page 3 of 3", on: canvas)
        app.descendants(matching: .any)["Canvas zoom test area"].pinch(withScale: 0.5, velocity: -1)
        let overview = NSPredicate(format: "value CONTAINS 'overview'")
        expectation(for: overview, evaluatedWith: canvas)
        waitForExpectations(timeout: 5)
        Thread.sleep(forTimeInterval: 0.8)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Three crisp pages in overview with title pill"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testNewNoteSelectionTitlesAndEditOrdering() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--canvasGestureTestArea"]
        app.launch()
        let rows = app.buttons.matching(identifier: "noteRow")
        if app.buttons["Show notes"].exists { app.buttons["Show notes"].tap() }
        app.buttons["New note"].tap()
        Thread.sleep(forTimeInterval: 0.6)
        let firstTitle = rows.element(boundBy: 0).label
        XCTAssertTrue(rows.element(boundBy: 0).isSelected)
        app.buttons["Hide notes"].tap()
        let pill = app.textFields["currentNoteTitle"]
        XCTAssertTrue(pill.waitForExistence(timeout: 3))
        let oldTitle = pill.value as! String
        XCTAssertTrue(firstTitle.contains(oldTitle))
        app.buttons["Show notes"].tap()
        Thread.sleep(forTimeInterval: 0.6)
        app.buttons["New note"].tap()
        Thread.sleep(forTimeInterval: 0.6)
        XCTAssertTrue(rows.element(boundBy: 0).isSelected)
        XCTAssertFalse(rows.element(boundBy: 0).label.contains(oldTitle + ","))
        app.buttons["Hide notes"].tap()
        XCTAssertTrue(pill.waitForExistence(timeout: 3))
        XCTAssertNotEqual(pill.value as? String, oldTitle)
        XCTAssertTrue((pill.value as? String ?? "").contains("Untitled ("))
        app.buttons["Show notes"].tap()
        Thread.sleep(forTimeInterval: 0.6)
        // Editing the older note promotes it above the more recently created note.
        rows.element(boundBy: 1).press(forDuration: 1)
        app.buttons["Rename"].tap()
        let title = "Edited " + UUID().uuidString.prefix(8)
        let field = app.alerts.textFields.firstMatch
        field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: (field.value as? String ?? "").count))
        field.typeText(title)
        // Submit through the alert's default action; this avoids the simulator's
        // stale alert coordinates while the hardware/software keyboard changes.
        field.typeText("\n")
        let predicate = NSPredicate(format: "label CONTAINS %@", title)
        expectation(for: predicate, evaluatedWith: rows.element(boundBy: 0))
        waitForExpectations(timeout: 5)
    }

    @MainActor
    private func pull(_ canvas: XCUIElement, from: CGFloat, to: CGFloat) {
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.72, dy: from))
            .press(forDuration: 0.05, thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.72, dy: to)),
                   withVelocity: .slow, thenHoldForDuration: 0.2)
    }

    @MainActor
    private func expect(_ value: String, on element: XCUIElement) {
        let predicate = NSPredicate(format: "value == %@", value)
        expectation(for: predicate, evaluatedWith: element)
        waitForExpectations(timeout: 8)
    }
}
