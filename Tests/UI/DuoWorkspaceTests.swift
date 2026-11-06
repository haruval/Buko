import XCTest

final class DuoWorkspaceTests: XCTestCase {
    @MainActor private func launch(fold: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments = ["--spatial-fixture", "auth", "-detailedAutofillPreview", "NO"]
        if fold { app.launchArguments.append("--duo-fold-fixture") }
        app.launch()
        XCTAssertTrue(app.buttons["spatialSetup"].waitForExistence(timeout: 20))
        app.buttons["spatialSetup"].tap()
        XCTAssertTrue(app.staticTexts["spatialReady"].waitForExistence(timeout: 40))
        XCTAssertFalse(app.buttons["lectureSources"].frame.intersects(app.buttons["duoAppend"].frame),
                       "Fixture controls must stay outside the native toolbar")
        return app
    }
    @MainActor private func shot(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
    }
    @MainActor private func visibleButton(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        // The native overlay retains its covered library to preserve transition
        // identity. XCTest still lists that library's noninteractive elements.
        let buttons = app.buttons.matching(identifier: identifier).allElementsBoundByIndex.filter { $0.isHittable }
        XCTAssertEqual(buttons.count, 1, "Exactly one visible \(identifier) control")
        return buttons.first ?? app.buttons.matching(identifier: identifier).firstMatch
    }
    @MainActor private func openNotes(_ app: XCUIApplication) {
        if app.buttons["showNotes"].exists { app.buttons["showNotes"].tap() }
        else if app.buttons["Show notes"].exists { app.buttons["Show notes"].tap() }
        XCTAssertTrue(app.buttons["noteRow"].firstMatch.waitForExistence(timeout: 8))
        Thread.sleep(forTimeInterval: 0.7)
    }
    @MainActor func testNoteDragSplitDividerAndRotation() {
        let app = launch()
        app.buttons["duoSecond"].tap()
        openNotes(app)
        let candidates = app.buttons.matching(identifier: "noteRow").matching(NSPredicate(format: "label CONTAINS 'Spatial validation - auth'")).allElementsBoundByIndex
        let first = candidates.filter { $0.isHittable }.min { $0.frame.minY < $1.frame.minY }!
        XCTAssertTrue(first.isHittable)
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.45))
        first.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.8, thenDragTo: end)
        XCTAssertTrue(app.descendants(matching: .any)["workspaceDivider"].firstMatch.waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertEqual(app.scrollViews.matching(NSPredicate(format: "label == 'Note canvas'")).count, 2)
        shot(app, "Two note split")
        XCUIDevice.shared.orientation = .portrait
        Thread.sleep(forTimeInterval: 1)
        shot(app, "Portrait split or compact continuation")
        XCUIDevice.shared.orientation = .landscapeLeft
        Thread.sleep(forTimeInterval: 1)
        let divider = app.descendants(matching: .any)["workspaceDivider"].firstMatch
        let start = divider.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.15, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)))
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: divider)
        waitForExpectations(timeout: 8)
        shot(app, "Divider keeps one note")
    }
    @MainActor func testIndependentSplitInkUndoAndPersistence() {
        let app = launch()
        app.buttons["duoSecond"].tap()
        openNotes(app)
        let source = app.buttons.matching(identifier: "noteRow")
            .matching(NSPredicate(format: "label CONTAINS 'Spatial validation - auth'"))
            .allElementsBoundByIndex.filter { $0.isHittable }.min { $0.frame.minY < $1.frame.minY }!
        source.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.8, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.45)))
        XCTAssertTrue(app.descendants(matching: .any)["workspaceDivider"].firstMatch.waitForExistence(timeout: 8))
        func counts() -> [String: Int] {
            app.buttons["duoCheckpoint"].tap()
            return Dictionary(uniqueKeysWithValues: app.staticTexts["duoCheck"].label.split(separator: ";").compactMap { pair in
                let p = pair.split(separator: "="); guard p.count == 2, let n = Int(p[1]) else { return nil }; return (String(p[0]), n)
            })
        }
        let before = counts()
        let canvases = app.scrollViews.matching(NSPredicate(format: "label == 'Note canvas'")).allElementsBoundByIndex.sorted { $0.frame.minX < $1.frame.minX }
        XCTAssertEqual(canvases.count, 2)
        for canvas in canvases {
            canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.6)).press(forDuration: 0.1,
                thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.66)))
        }
        let written = counts()
        XCTAssertGreaterThan(written["first"]!, before["first"]!, app.staticTexts["duoCheck"].label)
        XCTAssertGreaterThan(written["second"]!, before["second"]!)
        XCTAssertEqual(written["diskFirst"], written["first"])
        XCTAssertEqual(written["diskSecond"], written["second"])
        app.buttons["Undo"].tap()
        let undone = counts()
        XCTAssertEqual(undone["first"], written["first"], app.staticTexts["duoCheck"].label)
        XCTAssertEqual(undone["second"], before["second"])
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Duo second note'")).firstMatch.tap()
        app.buttons["Undo"].tap()
        let bothUndone = counts()
        XCTAssertEqual(bothUndone["first"], before["first"])
        XCTAssertEqual(bothUndone["second"], before["second"])
        XCTAssertEqual(bothUndone["diskFirst"], before["first"])
        XCTAssertEqual(bothUndone["diskSecond"], before["second"])
        shot(app, "Independent pane writing and Undo")
    }

    @MainActor func testReservedRegionBookAndTabletop() {
        let app = launch(fold: true)
        app.buttons["duoSecond"].tap()
        let library = app.descendants(matching: .any)["bookLibraryPanel"].firstMatch
        app.buttons["duoCheckpoint"].tap()
        XCTAssertTrue(app.staticTexts["duoCheck"].label.contains("paperTop=0;"), app.staticTexts["duoCheck"].label)
        XCTAssertTrue(library.exists)
        XCTAssertFalse(app.buttons["hideNotes"].exists)
        let source = app.buttons.matching(identifier: "noteRow")
            .matching(NSPredicate(format: "label CONTAINS 'Spatial validation - auth'"))
            .allElementsBoundByIndex.filter { $0.isHittable }.min { $0.frame.minY < $1.frame.minY }!
        let panes = app.scrollViews.matching(NSPredicate(format: "label == 'Note canvas'"))
        XCTAssertLessThan(library.frame.maxX, panes.firstMatch.frame.minX)
        let background = app.descendants(matching: .any)["bookLibraryBackground"].firstMatch
        print("Book library \(library.frame), background \(background.frame), canvas \(panes.firstMatch.frame)")
        shot(app, "Book library fills black region")
        XCTAssertEqual(library.frame.minY, background.frame.minY + 12, accuracy: 1)
        // XCTest clips the background at the iPad harness's bottom strip;
        // the library must still fill, and remain within, the visible region.
        XCTAssertLessThanOrEqual(library.frame.maxY, background.frame.maxY + 1)
        XCTAssertGreaterThanOrEqual(library.frame.maxY, background.frame.maxY - 13)
        XCTAssertFalse(visibleButton(app, "newNote").frame.intersects(app.buttons["duoFold"].frame))
        source.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05)).press(forDuration: 0.8,
            thenDragTo: panes.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.45)))
        XCTAssertTrue(app.buttons["switchWorkspacePane"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["fullscreenSecondPane"].isHittable)
        XCTAssertFalse(app.buttons["fullscreenFirstPane"].isHittable)
        XCTAssertTrue(library.exists)
        XCTAssertFalse(app.descendants(matching: .any)["workspaceDivider"].firstMatch.exists)
        app.buttons["switchWorkspacePane"].tap()
        XCTAssertTrue(app.buttons["fullscreenFirstPane"].isHittable)
        app.buttons["switchWorkspacePane"].tap()
        shot(app, "Book library fills left screen and editors stay on right")
        app.buttons["duoFold"].tap()
        Thread.sleep(forTimeInterval: 0.7)
        let table = panes.allElementsBoundByIndex.sorted { $0.frame.minY < $1.frame.minY }
        XCTAssertEqual(table.count, 2)
        XCTAssertGreaterThanOrEqual(table[1].frame.minY - table[0].frame.maxY, 39)
        XCTAssertEqual(table[0].frame.width, app.frame.width, accuracy: 1)
        XCTAssertEqual(table[1].frame.width, app.frame.width, accuracy: 1)
        let handle = app.descendants(matching: .any)["workspaceDivider"].firstMatch
        XCTAssertTrue(handle.isHittable)
        XCTAssertLessThanOrEqual(handle.frame.maxY, table[0].frame.maxY + 1)
        openNotes(app)
        XCTAssertLessThanOrEqual(visibleButton(app, "newNote").frame.maxY, table[0].frame.maxY)
        app.buttons["hideNotes"].tap()
        app.buttons["lectureSources"].tap()
        let panel = app.descendants(matching: .any)["sourcesPanel"].firstMatch
        XCTAssertTrue(panel.waitForExistence(timeout: 8))
        XCTAssertGreaterThanOrEqual(panel.frame.minY, table[1].frame.minY)
        XCTAssertLessThanOrEqual(panel.frame.maxY, table[1].frame.maxY + 1)
        app.buttons["closeLectureSources"].tap()
        shot(app, "Tabletop keeps two separated editors")
        app.buttons["duoFold"].tap()
        Thread.sleep(forTimeInterval: 0.7)
        let open = panes.allElementsBoundByIndex.sorted { $0.frame.minX < $1.frame.minX }
        XCTAssertEqual(open.count, 2)
        XCTAssertEqual(open[0].frame.minX, app.frame.minX, accuracy: 1)
        XCTAssertEqual(open[1].frame.maxX, app.frame.maxX, accuracy: 1)
        XCTAssertEqual(open[0].frame.width, open[1].frame.width, accuracy: 1)
        XCTAssertTrue(app.buttons["fullscreenFirstPane"].isHittable)
        XCTAssertTrue(app.buttons["fullscreenSecondPane"].isHittable)
        shot(app, "Fully open restores equal split")
    }

    @MainActor func testOpenLibraryOverlayAndPaperFit() {
        let app = launch()
        let canvas = app.scrollViews.matching(NSPredicate(format: "label == 'Note canvas'")).firstMatch
        let initialFrame = canvas.frame
        openNotes(app)
        XCTAssertEqual(canvas.frame.width, initialFrame.width, accuracy: 1, "Opening the library must not shrink paper")
        XCTAssertLessThan(visibleButton(app, "newNote").frame.maxX, app.frame.width * 0.4)
        app.buttons["hideNotes"].tap()
        XCTAssertTrue(app.textFields["currentNoteTitle"].isHittable)
        app.buttons["duoSecond"].tap()
        app.buttons["duoCheckpoint"].tap()
        func metrics() -> [String: Int] {
            Dictionary(uniqueKeysWithValues: app.staticTexts["duoCheck"].label.split(separator: ";").compactMap { pair in
                let p = pair.split(separator: "="); guard p.count == 2, let n = Int(p[1]) else { return nil }; return (String(p[0]), n)
            })
        }
        let fit = metrics()
        XCTAssertEqual(fit["paperWidth"], fit["viewportWidth"])
        XCTAssertEqual(fit["paperTop"], 0)
        openNotes(app)
        XCTAssertEqual(canvas.frame.width, initialFrame.width, accuracy: 1)
        app.buttons["hideNotes"].tap()
        XCTAssertTrue(app.textFields["currentNoteTitle"].isHittable)
        shot(app, "Open library overlay and uniform blank-note fit")
    }

    @MainActor func testCompactPaneSwitch() {
        let app = launch()
        app.buttons["duoSecond"].tap()
        openNotes(app)
        let first = app.buttons.matching(identifier: "noteRow")
            .matching(NSPredicate(format: "label CONTAINS 'Spatial validation - auth'"))
            .allElementsBoundByIndex.filter { $0.isHittable }.min { $0.frame.minY < $1.frame.minY }!
        first.press(forDuration: 0.7)
        let open = app.buttons["Open beside current note"]
        XCTAssertTrue(open.waitForExistence(timeout: 8)); open.tap()
        let toggle = app.buttons["switchWorkspacePane"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        func counts() -> [String: Int] {
            app.buttons["duoCheckpoint"].tap()
            return Dictionary(uniqueKeysWithValues: app.staticTexts["duoCheck"].label.split(separator: ";").compactMap { pair in
                let p = pair.split(separator: "="); guard p.count == 2, let n = Int(p[1]) else { return nil }; return (String(p[0]), n)
            })
        }
        func write(second: Bool) {
            let pane = app.descendants(matching: .any)[second ? "workspaceSecondPane" : "workspaceFirstPane"].firstMatch
            let canvas = pane.scrollViews.matching(NSPredicate(format: "label == 'Note canvas'")).firstMatch
            canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.42)).press(forDuration: 0.1,
                thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.48)))
        }
        XCTAssertTrue(app.buttons["fullscreenSecondPane"].isHittable)
        XCTAssertFalse(app.buttons["fullscreenFirstPane"].isHittable)
        let before = counts()
        write(second: true)
        let secondWritten = counts()
        XCTAssertGreaterThan(secondWritten["second"]!, before["second"]!)
        XCTAssertEqual(secondWritten["first"], before["first"])
        shot(app, "Compact second pane")
        toggle.tap()
        XCTAssertTrue(app.buttons["fullscreenFirstPane"].isHittable)
        XCTAssertFalse(app.buttons["fullscreenSecondPane"].isHittable)
        write(second: false)
        let firstWritten = counts()
        XCTAssertGreaterThan(firstWritten["first"]!, secondWritten["first"]!)
        XCTAssertEqual(firstWritten["second"], secondWritten["second"])
        shot(app, "Compact first pane")
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(toggle.waitForExistence(timeout: 8))
        toggle.tap()
        XCTAssertTrue(app.buttons["fullscreenSecondPane"].isHittable)
        app.buttons["fullscreenSecondPane"].tap()
        XCTAssertFalse(app.buttons["switchWorkspacePane"].exists)
    }

    @MainActor func testSourceDragAndSoloCard() {
        let app = launch()
        app.buttons["lectureSources"].tap()
        XCTAssertTrue(app.buttons["importLecturePDF"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["sampleLectureMenu"].exists)
        let source = app.buttons["lectureDocument"].firstMatch
        XCTAssertTrue(source.waitForExistence(timeout: 10))
        shot(app, "Glass sources")
        source.tap()
        XCTAssertTrue(app.buttons["closeLecturePDF"].waitForExistence(timeout: 8))
        shot(app, "Solo PDF card")
        app.buttons["closeLecturePDF"].tap()
        source.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.8, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.86, dy: 0.5)))
        XCTAssertTrue(app.descendants(matching: .any)["workspaceDivider"].firstMatch.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.descendants(matching: .any)["lecturePDFContent"].firstMatch.exists)
        shot(app, "Note beside source PDF")
        app.buttons["fullscreenSecondPane"].tap()
        XCTAssertTrue(app.buttons["closeLecturePDF"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.descendants(matching: .any)["workspaceDivider"].firstMatch.isHittable)
        XCTAssertTrue(app.descendants(matching: .any)["lecturePDFContent"].firstMatch.exists)
        app.buttons["closeLecturePDF"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["workspaceDivider"].firstMatch.waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["fullscreenFirstPane"].isHittable)
        XCTAssertTrue(app.buttons["fullscreenSecondPane"].isHittable)
    }
    @MainActor func testWritingDuringAutofillAcceptUndo() {
        let app = launch()
        app.buttons["duoAppend"].tap()
        let check = app.staticTexts["duoCheck"]
        expectation(for: NSPredicate(format: "label CONTAINS 'running=true;preserved=true'"), evaluatedWith: check)
        waitForExpectations(timeout: 10)
        let accept = app.buttons["acceptAutofill"]
        XCTAssertTrue(accept.waitForExistence(timeout: 120), app.debugDescription)
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: accept)
        waitForExpectations(timeout: 40)
        shot(app, "Autofill survives new handwriting")
        accept.tap()
        app.buttons["Undo"].tap()
        app.buttons["spatialCheckpoint"].tap()
        XCTAssertTrue(app.staticTexts["spatialStatus"].label.contains("original=true;"), app.staticTexts["spatialStatus"].label)
    }
}
