import XCTest

final class LectureSourceTests: XCTestCase {
    @MainActor func testSampleImportPreviewPersistenceAndNotebookIsolation() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["lectureSources"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["cubeTool"].exists)
        if app.buttons["Show notes"].exists { app.buttons["Show notes"].tap() }
        app.buttons.matching(NSPredicate(format: "label CONTAINS 'Test PPL Lecture'")).firstMatch.tap()
        if app.buttons["Hide notes"].exists { app.buttons["Hide notes"].tap() }
        app.buttons["lectureSources"].tap()
        XCTAssertTrue(app.buttons["importLecturePDF"].waitForExistence(timeout: 5))
        // This suite runs with an isolated bundle ID; its generated sample note is disposable.
        XCTAssertTrue(app.buttons["importMatchingLecture"].exists)
        app.buttons["importMatchingLecture"].tap()
        let source = app.buttons["lectureDocument"].firstMatch
        XCTAssertTrue(source.waitForExistence(timeout: 30))
        app.buttons["importMatchingLecture"].tap()
        XCTAssertTrue(app.staticTexts["Attached sources · 1"].waitForExistence(timeout: 10))
        source.tap()
        XCTAssertTrue(app.navigationBars["Source · page 1"].waitForExistence(timeout: 5))
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Imported lecture PDF source viewer"
        shot.lifetime = .keepAlways; add(shot)
        app.buttons["closeLecturePDF"].tap()
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        app.buttons["closeLectureSources"].tap()
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["lectureSources"].waitForExistence(timeout: 10))
        // Startup selects the most recently created sample. Select the PPL note explicitly.
        if app.buttons["Show notes"].exists { app.buttons["Show notes"].tap() }
        app.buttons.matching(NSPredicate(format: "label CONTAINS 'Test PPL Lecture'")).firstMatch.tap()
        if app.buttons["Hide notes"].exists { app.buttons["Hide notes"].tap() }
        app.buttons["lectureSources"].tap()
        XCTAssertTrue(source.waitForExistence(timeout: 10))
        app.buttons["closeLectureSources"].tap()
        if app.buttons["Show notes"].exists { app.buttons["Show notes"].tap() }
        app.buttons["New note"].tap()
        if app.buttons["Hide notes"].exists { app.buttons["Hide notes"].tap() }
        app.buttons["lectureSources"].tap()
        XCTAssertTrue(app.staticTexts["No PDFs attached yet."].waitForExistence(timeout: 5))
        XCTAssertFalse(source.exists)
    }
}
