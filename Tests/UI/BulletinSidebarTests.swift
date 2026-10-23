import XCTest

final class BulletinSidebarTests: XCTestCase {
    @MainActor func testAFolderDragRenameAndPersistence() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication(); app.launch()
        XCTAssertTrue(app.buttons["openSettings"].waitForExistence(timeout: 20))
        if app.buttons["showNotes"].exists { app.buttons["showNotes"].tap() }
        XCTAssertTrue(app.buttons["openBulletinBoard"].waitForExistence(timeout: 5))
        app.buttons["openBulletinBoard"].tap()
        XCTAssertTrue(app.staticTexts["Your bulletin board"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["closeBulletinBoard"].waitForExistence(timeout: 10))
        app.buttons["closeBulletinBoard"].tap()
        app.buttons["newNote"].tap()
        Thread.sleep(forTimeInterval: 1)
        app.buttons["newNote"].tap()
        Thread.sleep(forTimeInterval: 1)
        let cards = app.buttons.matching(identifier: "noteRow")
        XCTAssertGreaterThanOrEqual(cards.count, 2)
        let first = cards.element(boundBy: 0)
        let second = cards.allElementsBoundByIndex.first { abs($0.frame.midX - first.frame.midX) > 100 }!
        first.press(forDuration: 1.2, thenDragTo: second)
        let folder = app.buttons["folderCard"].firstMatch
        XCTAssertTrue(folder.waitForExistence(timeout: 8))
        folder.tap()
        let title = app.textFields["folderTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        title.press(forDuration: 1.1)
        if app.menuItems["Select All"].waitForExistence(timeout: 2) { app.menuItems["Select All"].tap() }
        else { title.tap(withNumberOfTaps: 3, numberOfTouches: 1) }
        title.typeText("Semester\n")
        XCTAssertEqual(title.value as? String, "Semester")
        screenshot(app, "Expanded folder inside sidebar")
        app.buttons["folderBack"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier == 'folderCard' AND label CONTAINS 'Semester'")).firstMatch.waitForExistence(timeout: 5))
        app.terminate(); app.launch()
        if app.buttons["showNotes"].waitForExistence(timeout: 3) { app.buttons["showNotes"].tap() }
        let restored = app.buttons.matching(NSPredicate(format: "identifier == 'folderCard' AND label CONTAINS 'Semester'")).firstMatch
        XCTAssertTrue(restored.waitForExistence(timeout: 10))
        screenshot(app, "Two-column glass library landscape")
        restored.tap()
        XCTAssertEqual(app.buttons.matching(identifier: "noteRow").count, 2)
        app.buttons["noteRow"].firstMatch.tap()
        app.buttons["folderBack"].tap()
        XCUIDevice.shared.orientation = .portrait
        Thread.sleep(forTimeInterval: 1)
        screenshot(app, "Two-column glass library portrait")
    }

    @MainActor func testBExtractionReviewBoardCompletionAndSource() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launch()
        XCTAssertTrue(app.buttons["captureBulletinFixture"].waitForExistence(timeout: 20))
        app.buttons["captureBulletinFixture"].tap()
        XCTAssertTrue(app.buttons["cancelBulletinExtraction"].waitForExistence(timeout: 8))
        app.buttons["cancelBulletinExtraction"].tap()
        XCTAssertTrue(app.staticTexts["bulletinFixtureInkIntact"].waitForExistence(timeout: 5))
        app.buttons["captureBulletinFixture"].tap()
        let add = app.buttons["addBulletinItems"]
        XCTAssertTrue(add.waitForExistence(timeout: 8))
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: add)
        waitForExpectations(timeout: 65)
        screenshot(app, "Real handwriting and local model extraction review")
        add.tap()
        XCTAssertTrue(app.staticTexts["bulletinFixtureInkIntact"].waitForExistence(timeout: 8))
        if app.buttons["showNotes"].exists { app.buttons["showNotes"].tap() }
        app.buttons["openBulletinBoard"].tap()
        let complete = app.buttons["completeBulletinItem"].firstMatch
        XCTAssertTrue(complete.waitForExistence(timeout: 8))
        screenshot(app, "Bulletin board with dated event and action")
        complete.tap()
        XCTAssertFalse(complete.exists)
        app.buttons["showCompletedBulletinItems"].tap()
        XCTAssertTrue(complete.waitForExistence(timeout: 5))
        app.buttons["closeBulletinBoard"].tap()
        app.terminate(); app.launch()
        if app.buttons["showNotes"].waitForExistence(timeout: 3) { app.buttons["showNotes"].tap() }
        app.buttons["openBulletinBoard"].tap()
        XCTAssertTrue(app.buttons["openBulletinSource"].firstMatch.waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["completeBulletinItem"].firstMatch.exists)
        app.buttons["openBulletinSource"].firstMatch.tap()
        XCTAssertTrue(app.buttons["showNotes"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["closeBulletinBoard"].exists)
        screenshot(app, "Return to original source handwriting")
    }

    @MainActor func testCGestureToolsPointerSelectionAndVisibility() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        // Prepare ink only; every selection below goes through real UIKit input.
        app.launchArguments = ["--band-tool-fixture"]
        app.launch()
        XCTAssertTrue(app.buttons["captureBulletinFixture"].waitForExistence(timeout: 20))
        app.buttons["captureBulletinFixture"].tap()
        XCTAssertTrue(app.staticTexts["bulletinFixtureInkIntact"].waitForExistence(timeout: 8))
        let circle = app.buttons["circleIntentTool"], band = app.buttons["bandSelectionTool"]
        XCTAssertTrue(circle.exists); XCTAssertTrue(band.exists)
        XCTAssertGreaterThan(band.frame.minX, circle.frame.maxX)
        band.tap()
        XCTAssertTrue(band.isSelected)
        screenshot(app, "Green square band tool beside Circle")
        let canvas = app.descendants(matching: .any)["Note canvas"].firstMatch
        let origin = canvas.coordinate(withNormalizedOffset: .zero)
        let width = canvas.frame.width
        let top = origin.withOffset(CGVector(dx: width * 0.055, dy: width * 0.125))
        let bottom = origin.withOffset(CGVector(dx: width * 0.705, dy: width * 0.230))
        // A tap and a zero-height horizontal drag must not capture or write ink.
        top.tap()
        top.press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: width * 0.705, dy: width * 0.125)))
        XCTAssertFalse(app.buttons["cancelBulletinExtraction"].exists)
        XCTAssertTrue(app.staticTexts["bulletinFixtureInkIntact"].exists)
        top.press(forDuration: 0.05, thenDragTo: bottom)
        XCTAssertTrue(app.buttons["cancelBulletinExtraction"].waitForExistence(timeout: 8))
        app.buttons["cancelBulletinExtraction"].tap()
        XCTAssertTrue(app.staticTexts["bulletinFixtureInkIntact"].waitForExistence(timeout: 5))
        // Reverse corners exercise the same selection, including real recognition.
        bottom.press(forDuration: 0.05, thenDragTo: top)
        let add = app.buttons["addBulletinItems"]
        XCTAssertTrue(add.waitForExistence(timeout: 8))
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: add)
        waitForExpectations(timeout: 65)
        screenshot(app, "Trackpad-style drag reaches extraction review")
        app.buttons["cancelBulletinExtraction"].tap()
        XCTAssertTrue(app.staticTexts["bulletinFixtureInkIntact"].waitForExistence(timeout: 5))
        openGestureSettings(app)
        let visibility = app.switches["showGestureTestTools"]
        XCTAssertEqual(visibility.value as? String, "1")
        visibility.tap()
        XCTAssertFalse(band.exists); XCTAssertFalse(circle.exists)
        XCTAssertTrue(app.buttons["Pen"].isSelected)
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["openSettings"].waitForExistence(timeout: 15))
        XCTAssertFalse(band.exists); XCTAssertFalse(circle.exists)
        openGestureSettings(app)
        XCTAssertEqual(visibility.value as? String, "0")
        visibility.tap()
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.6)).tap()
        XCTAssertTrue(circle.waitForExistence(timeout: 5)); XCTAssertTrue(band.exists)
        circle.tap()
        XCTAssertTrue(circle.isSelected)
        openGestureSettings(app)
        visibility.tap()
        XCTAssertTrue(app.buttons["Pen"].isSelected)
        XCTAssertFalse(circle.exists); XCTAssertFalse(band.exists)
        visibility.tap()
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.6)).tap()
        XCTAssertTrue(circle.waitForExistence(timeout: 5)); XCTAssertTrue(band.exists)
    }

    @MainActor private func openGestureSettings(_ app: XCUIApplication) {
        app.buttons["openSettings"].tap()
        XCTAssertTrue(app.buttons["openDevelopment"].waitForExistence(timeout: 5))
        app.buttons["openDevelopment"].tap()
        XCTAssertTrue(app.switches["showGestureTestTools"].waitForExistence(timeout: 5))
    }

    @MainActor private func screenshot(_ app: XCUIApplication, _ title: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = title; attachment.lifetime = .keepAlways; add(attachment)
    }
}
