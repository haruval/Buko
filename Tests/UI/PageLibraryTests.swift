import XCTest

final class PageLibraryTests: XCTestCase {
    @MainActor
    func testPageLibraryRestoreEmptyTrashAndStableTitleWidth() {
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
        Thread.sleep(forTimeInterval: 0.7)
        let title = app.textFields["currentNoteTitle"]
        let titleWidth = title.frame.width
        let noteTitle = title.value as! String
        app.buttons["Settings"].tap()
        Thread.sleep(forTimeInterval: 0.8)
        XCTAssertEqual(title.frame.width, titleWidth, accuracy: 1)
        app.buttons["Close settings"].tap()

        for count in 2...3 {
            for _ in 0..<4 {
                if canvas.value as? String == "Page \(count) of \(count)" { break }
                pull(canvas)
            }
            expect("Page \(count) of \(count)", on: canvas)
        }
        let navigator = app.buttons["pageNavigator"]
        XCTAssertEqual(navigator.value as? String, "3 of 3")
        navigator.tap()
        Thread.sleep(forTimeInterval: 0.8)
        let page2 = app.buttons.matching(identifier: "pageThumbnail").matching(NSPredicate(format: "label == 'Page 2'")).firstMatch
        if !page2.isHittable { app.scrollViews.containing(.button, identifier: "pageThumbnail").firstMatch.swipeDown() }
        page2.press(forDuration: 1)
        app.buttons["Rename page"].tap()
        let field = app.alerts.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.tap()
        field.typeText("Key ideas\n")
        let renamed = app.buttons.matching(identifier: "pageThumbnail").matching(NSPredicate(format: "label CONTAINS 'Key ideas'")).firstMatch
        XCTAssertTrue(renamed.waitForExistence(timeout: 5))
        renamed.tap()
        expect("Page 2 of 3", on: canvas)
        navigator.tap()
        Thread.sleep(forTimeInterval: 0.7)
        renamed.press(forDuration: 1)
        app.buttons["Delete page"].tap()
        expect("Page 2 of 2", on: canvas)
        XCTAssertFalse(renamed.exists)
        app.buttons["Close pages"].tap()

        app.buttons["Settings"].tap()
        Thread.sleep(forTimeInterval: 0.7)
        app.buttons["openTrash"].tap()
        Thread.sleep(forTimeInterval: 0.5)
        let restore = app.buttons["Restore \(noteTitle) (page 2)"]
        XCTAssertTrue(restore.waitForExistence(timeout: 5))
        restore.tap()
        expect("Page 2 of 3", on: canvas)
        app.buttons["Close settings"].tap()
        navigator.tap()
        Thread.sleep(forTimeInterval: 0.7)
        XCTAssertTrue(renamed.exists)
        renamed.press(forDuration: 1)
        app.buttons["Delete page"].tap()
        expect("Page 2 of 2", on: canvas)
        app.buttons["Close pages"].tap()
        app.buttons["Settings"].tap()
        Thread.sleep(forTimeInterval: 0.7)
        app.buttons["openTrash"].tap()
        Thread.sleep(forTimeInterval: 0.5)
        app.buttons["Empty Trash"].tap()
        let confirmation = app.alerts["Empty Trash?"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 3))
        confirmation.buttons["Cancel"].tap()
        XCTAssertTrue(restore.exists)
        app.buttons["Empty Trash"].tap()
        confirmation.buttons["Delete permanently"].tap()
        XCTAssertTrue(app.staticTexts["Trash is empty"].waitForExistence(timeout: 5))
        app.buttons["Close settings"].tap()
        expect("Page 2 of 2", on: canvas)
        XCUIDevice.shared.press(.home)
        app.terminate()
        app.launch()
        expect("Page 2 of 2", on: canvas)
        app.buttons["Page navigator"].tap()
        Thread.sleep(forTimeInterval: 0.7)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Page library after restore and scoped Empty Trash"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testDeletingOnlyPageLeavesEmptyNoteAndRestores() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launch()
        let canvas = app.descendants(matching: .any).matching(identifier: "Note canvas").firstMatch
        XCTAssertTrue(canvas.waitForExistence(timeout: 10))
        if app.buttons["Show notes"].exists { app.buttons["Show notes"].tap() }
        app.buttons["New note"].tap()
        app.buttons["Hide notes"].tap()
        Thread.sleep(forTimeInterval: 0.7)
        let title = app.textFields["currentNoteTitle"].value as! String
        app.buttons["pageNavigator"].tap()
        Thread.sleep(forTimeInterval: 0.7)
        app.buttons.matching(identifier: "pageThumbnail").firstMatch.press(forDuration: 1)
        app.buttons["Delete page"].tap()
        XCTAssertTrue(app.staticTexts["No pages"].waitForExistence(timeout: 5))
        app.buttons["Close pages"].tap()
        XCTAssertEqual(app.buttons["pageNavigator"].value as? String, "0 of 0")
        app.buttons["Settings"].tap()
        Thread.sleep(forTimeInterval: 0.7)
        app.buttons["openTrash"].tap()
        Thread.sleep(forTimeInterval: 0.5)
        app.buttons["Restore \(title) (page 1)"].tap()
        expect("Page 1 of 1", on: canvas)
        XCTAssertFalse(app.staticTexts["No pages"].exists)
    }

    @MainActor private func pull(_ canvas: XCUIElement) {
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.82))
            .press(forDuration: 0.05, thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.18)),
                   withVelocity: .slow, thenHoldForDuration: 0.2)
    }

    @MainActor private func expect(_ value: String, on element: XCUIElement) {
        expectation(for: NSPredicate(format: "value == %@", value), evaluatedWith: element)
        waitForExpectations(timeout: 8)
    }
}
