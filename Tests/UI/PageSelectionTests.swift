import XCTest

final class PageSelectionTests: XCTestCase {
    @MainActor
    func testSelectNonadjacentPagesDeleteTogetherAndRestore() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launch()
        let canvas = app.descendants(matching: .any)["Note canvas"].firstMatch
        XCTAssertTrue(canvas.waitForExistence(timeout: 10))
        if app.buttons["Show notes"].exists { app.buttons["Show notes"].tap() }
        app.buttons["New note"].tap()
        app.buttons["Hide notes"].tap()
        Thread.sleep(forTimeInterval: 0.7)
        let noteTitle = app.textFields["currentNoteTitle"].value as! String
        for count in 2...3 {
            for _ in 0..<4 {
                if canvas.value as? String == "Page \(count) of \(count)" { break }
                canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.72, dy: 0.85))
                    .press(forDuration: 0.05, thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.72, dy: 0.15)),
                           withVelocity: .slow, thenHoldForDuration: 0.2)
            }
            expect("Page \(count) of \(count)", on: canvas)
        }
        app.buttons["pageNavigator"].tap()
        Thread.sleep(forTimeInterval: 0.8)
        let third = app.buttons["selectPage-3"]
        XCTAssertTrue(third.waitForExistence(timeout: 3))
        third.tap()
        XCTAssertEqual(third.value as? String, "Selected")
        let list = app.scrollViews["pageThumbnailList"]
        let first = app.buttons["selectPage-1"]
        for _ in 0..<4 {
            if first.exists && first.isHittable { break }
            list.swipeDown()
        }
        first.tap()
        XCTAssertTrue(app.staticTexts["2 selected"].exists)
        first.tap()
        XCTAssertEqual(first.value as? String, "Not selected")
        first.tap()
        XCTAssertEqual(canvas.value as? String, "Page 3 of 3") // Selection never navigates.
        let selectionShot = XCTAttachment(screenshot: app.screenshot())
        selectionShot.name = "Page selection circles and grouped selection"
        selectionShot.lifetime = .keepAlways
        add(selectionShot)
        first.press(forDuration: 1)
        let delete = app.buttons["Delete 2 selected pages"]
        XCTAssertTrue(delete.waitForExistence(timeout: 3))
        delete.tap()
        expect("Page 1 of 1", on: canvas)
        XCTAssertFalse(app.staticTexts["2 selected"].exists)
        app.buttons["Close pages"].tap()
        app.buttons["Settings"].tap()
        Thread.sleep(forTimeInterval: 0.7)
        app.buttons["openTrash"].tap()
        Thread.sleep(forTimeInterval: 0.5)
        let restore1 = app.buttons["Restore \(noteTitle) (page 1)"]
        let restore3 = app.buttons["Restore \(noteTitle) (page 3)"]
        XCTAssertTrue(restore1.waitForExistence(timeout: 3))
        restore3.tap()
        expect("Page 2 of 2", on: canvas)
        restore1.tap()
        expect("Page 1 of 3", on: canvas)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        app.buttons["pageNavigator"].tap()
        Thread.sleep(forTimeInterval: 0.7)
        XCTAssertEqual(app.buttons["selectPage-1"].value as? String, "Not selected")
        XCUIDevice.shared.press(.home)
        app.terminate()
        app.launch()
        expect("Page 1 of 3", on: canvas)
    }

    @MainActor private func expect(_ value: String, on element: XCUIElement) {
        expectation(for: NSPredicate(format: "value == %@", value), evaluatedWith: element)
        waitForExpectations(timeout: 8)
    }
}
