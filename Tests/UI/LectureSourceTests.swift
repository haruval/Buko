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
        XCTAssertFalse(app.descendants(matching: .any)["lectureTextDisagreement"].exists,
                       "The sample grammar notation must not quarantine the PPL lecture on iPadOS")
        app.buttons["importMatchingLecture"].tap()
        XCTAssertTrue(app.staticTexts["1 attached source"].waitForExistence(timeout: 10))
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: app.buttons["sampleLectureMenu"])
        waitForExpectations(timeout: 10)
        app.buttons["sampleLectureMenu"].tap()
        XCTAssertTrue(app.buttons["Linear Algebra Lecture"].waitForExistence(timeout: 5))
        app.buttons["Linear Algebra Lecture"].tap()
        XCTAssertTrue(app.staticTexts["2 attached sources"].waitForExistence(timeout: 30))
        let cards = app.buttons.matching(identifier: "lectureDocument")
        XCTAssertEqual(cards.count, 2)
        XCTAssertEqual(cards.element(boundBy: 0).frame.minY, cards.element(boundBy: 1).frame.minY, accuracy: 3)
        XCTAssertLessThan(cards.element(boundBy: 0).frame.maxX, cards.element(boundBy: 1).frame.minX)
        let gridShot = XCTAttachment(screenshot: app.screenshot())
        gridShot.name = "Two-column lecture PDF thumbnails"; gridShot.lifetime = .keepAlways; add(gridShot)
        source.tap()
        XCTAssertTrue(app.buttons["closeLecturePDF"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Page 1 of'")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertLessThan(app.buttons["closeLecturePDF"].frame.midX, app.frame.midX)
        XCTAssertLessThan(app.buttons["closeLecturePDF"].frame.maxY, app.frame.height * 0.15)
        let close = app.buttons["closeLecturePDF"]
        XCTAssertEqual(close.frame.width, close.frame.height, accuracy: 2)
        let pdf = app.descendants(matching: .any)["pdfZoomTestArea"].firstMatch
        Thread.sleep(forTimeInterval: 0.8)
        XCTAssertEqual(pdf.value as? String, "1.000")
        pdf.pinch(withScale: 0.4, velocity: -1)
        Thread.sleep(forTimeInterval: 0.8)
        XCTAssertEqual(pdf.value as? String, "1.000", "Pinching out cannot shrink below the opening fit")
        pdf.pinch(withScale: 1.6, velocity: 1)
        Thread.sleep(forTimeInterval: 0.8)
        XCTAssertGreaterThan(Double(pdf.value as? String ?? "0") ?? 0, 1.1)
        pdf.pinch(withScale: 0.3, velocity: -1)
        Thread.sleep(forTimeInterval: 0.8)
        XCTAssertEqual(pdf.value as? String, "1.000")
        XCUIDevice.shared.orientation = .landscapeLeft
        Thread.sleep(forTimeInterval: 1)
        pdf.pinch(withScale: 0.4, velocity: -1)
        Thread.sleep(forTimeInterval: 0.8)
        XCTAssertEqual(pdf.value as? String, "1.000", "Rotation recomputes the fitted zoom floor")
        XCUIDevice.shared.orientation = .portrait
        Thread.sleep(forTimeInterval: 1)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Imported lecture PDF source viewer"
        shot.lifetime = .keepAlways; add(shot)
        app.buttons["closeLecturePDF"].tap()
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        source.press(forDuration: 1.1)
        app.buttons["Delete"].tap()
        app.buttons["Delete source"].tap()
        XCTAssertTrue(app.staticTexts["1 attached source"].waitForExistence(timeout: 10))
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
