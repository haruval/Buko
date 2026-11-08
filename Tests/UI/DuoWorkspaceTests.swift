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
        if !app.buttons.matching(identifier: "newNote").allElementsBoundByIndex.contains(where: \.isHittable) {
            visibleButton(app, "showNotes").tap()
        }
        XCTAssertTrue(app.buttons["noteRow"].firstMatch.waitForExistence(timeout: 8))
        Thread.sleep(forTimeInterval: 0.7)
    }
    @MainActor private func openBeside(_ item: XCUIElement, in app: XCUIApplication,
                                       action: String = "Open beside current note") {
        let option = app.buttons[action].firstMatch
        if !option.exists {
            item.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.14)).press(forDuration: 1.2)
        }
        XCTAssertTrue(option.waitForExistence(timeout: 8))
        option.tap()
    }
    @MainActor private func prepareSecondNote(in app: XCUIApplication, libraryOrientation: UIDeviceOrientation? = nil) -> XCUIElement {
        app.buttons["duoSecond"].tap()
        if let libraryOrientation { XCUIDevice.shared.orientation = libraryOrientation }
        openNotes(app)
        return app.buttons.matching(identifier: "noteRow")
            .matching(NSPredicate(format: "label CONTAINS 'Spatial validation - auth'"))
            .allElementsBoundByIndex.filter { $0.isHittable }.min { $0.frame.minY < $1.frame.minY }!
    }
    @MainActor func testReleasingNoteOverCanvasKeepsSinglePane() {
        let app = launch()
        let first = prepareSecondNote(in: app)
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.45))
        first.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.8, thenDragTo: end)
        XCTAssertFalse(app.descendants(matching: .any)["workspaceDivider"].firstMatch.waitForExistence(timeout: 1))
        XCTAssertEqual(app.scrollViews.matching(NSPredicate(format: "label == 'Note canvas'")).count, 1)
    }
    @MainActor func testNoteMenuSplitDividerAndRotation() {
        let app = launch()
        openBeside(prepareSecondNote(in: app), in: app)
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
        openBeside(prepareSecondNote(in: app), in: app)
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

    @MainActor func testBookUsesPreviousNoteAndReturnsToOriginalEditor() {
        let app = launch(fold: true)
        app.buttons["duoSecond"].tap()
        let panes = app.scrollViews.matching(NSPredicate(format: "label == 'Note canvas'"))
        XCTAssertEqual(panes.count, 1)
        let openFrame = panes.firstMatch.frame
        app.buttons["duoFold"].tap()
        let left = app.buttons["secondPaneTitle"], right = app.buttons["firstPaneTitle"]
        XCTAssertTrue(left.waitForExistence(timeout: 8))
        XCTAssertTrue(left.label.hasPrefix("Spatial validation - auth"), left.label)
        XCTAssertTrue(right.label.hasPrefix("Duo second note"), right.label)
        XCTAssertLessThan(left.frame.maxX, right.frame.minX)
        let canvases = panes.allElementsBoundByIndex.map(\.frame).sorted { $0.minX < $1.minX }
        XCTAssertEqual(canvases.count, 2)
        XCTAssertEqual(canvases[0].maxX, openFrame.midX - 10, accuracy: 1)
        XCTAssertEqual(canvases[1].minX, openFrame.midX + 10, accuracy: 1)
        XCTAssertFalse(app.buttons["switchWorkspacePane"].exists)
        openNotes(app)
        XCTAssertLessThan(visibleButton(app, "newNote").frame.maxX, openFrame.width * 0.4)
        XCTAssertEqual(panes.allElementsBoundByIndex.map(\.frame).sorted { $0.minX < $1.minX }, canvases)
        visibleButton(app, "hideNotes").tap()
        left.tap()
        shot(app, "Book split with previous and current notes")
        app.buttons["duoFold"].tap()
        XCTAssertFalse(left.exists)
        XCTAssertEqual(panes.count, 1)
        XCTAssertEqual(panes.firstMatch.frame, openFrame)
        XCTAssertTrue((app.textFields["currentNoteTitle"].value as? String)?.hasPrefix("Duo second note") == true)
        app.buttons["duoFold"].tap()
        XCTAssertTrue(left.waitForExistence(timeout: 8))
        XCTAssertTrue(left.label.hasPrefix("Spatial validation - auth"))
        XCTAssertTrue(right.label.hasPrefix("Duo second note"))

        let originalTitle = right.label
        app.buttons["duoSecond"].tap()
        XCTAssertNotEqual(right.label, originalTitle)
        app.buttons["duoFold"].tap()
        XCTAssertEqual(app.textFields["currentNoteTitle"].value as? String, originalTitle)
    }

    @MainActor func testBookCompanionSourceOpensBesideItsOwner() {
        let app = launch(fold: true)
        app.buttons["duoSecond"].tap()
        app.buttons["duoFold"].tap()
        let previous = app.buttons["secondPaneTitle"]
        XCTAssertTrue(previous.waitForExistence(timeout: 8))
        let owner = previous.label
        previous.tap()
        app.buttons["lectureSources"].tap()
        let source = app.buttons["lectureDocument"].firstMatch
        XCTAssertTrue(source.waitForExistence(timeout: 10))
        openBeside(source, in: app, action: "Open beside note")
        XCTAssertTrue(app.descendants(matching: .any)["lecturePDFContent"].firstMatch.waitForExistence(timeout: 8))
        XCTAssertEqual(app.buttons["firstPaneTitle"].label, owner)
        app.buttons["duoFold"].tap()
        XCTAssertEqual(app.buttons["firstPaneTitle"].label, owner)
        XCTAssertTrue(app.buttons["fullscreenSecondPane"].isHittable)
    }

    @MainActor func testManualSplitSurvivesBookAndTabletop() {
        let app = launch(fold: true)
        openBeside(prepareSecondNote(in: app, libraryOrientation: .portrait), in: app)
        let first = app.buttons["firstPaneTitle"], second = app.buttons["secondPaneTitle"]
        XCTAssertTrue(first.waitForExistence(timeout: 8))
        XCUIDevice.shared.orientation = .landscapeLeft
        let openHeaderY = first.frame.midY
        first.tap()
        app.buttons["duoFold"].tap()
        XCTAssertLessThan(second.frame.maxX, first.frame.minX)
        for id in ["firstPaneTitle", "secondPaneTitle", "fullscreenFirstPane", "fullscreenSecondPane"] {
            XCTAssertEqual(app.buttons[id].frame.midY, openHeaderY, accuracy: 2)
        }
        XCTAssertFalse(app.buttons["switchWorkspacePane"].exists)
        app.buttons["duoTable"].tap()
        let panes = app.scrollViews.matching(NSPredicate(format: "label == 'Note canvas'"))
        let table = panes.allElementsBoundByIndex.sorted { $0.frame.minY < $1.frame.minY }
        XCTAssertEqual(table.count, 2)
        XCTAssertGreaterThanOrEqual(table[1].frame.minY - table[0].frame.maxY, 39)
        XCTAssertEqual(table[0].frame.width, table[1].frame.width, accuracy: 1)
        let handle = app.descendants(matching: .any)["workspaceDivider"].firstMatch
        XCTAssertTrue(handle.isHittable)
        XCTAssertLessThanOrEqual(handle.frame.maxY, table[0].frame.maxY + 1)
        openNotes(app)
        XCTAssertLessThanOrEqual(visibleButton(app, "newNote").frame.maxY, table[0].frame.maxY)
        visibleButton(app, "hideNotes").tap()
        second.tap()
        app.buttons["lectureSources"].tap()
        let panel = app.descendants(matching: .any)["sourcesPanel"].firstMatch
        XCTAssertTrue(panel.waitForExistence(timeout: 8))
        XCTAssertGreaterThanOrEqual(panel.frame.minY, table[1].frame.minY)
        XCTAssertLessThanOrEqual(panel.frame.maxY, table[1].frame.maxY + 1)
        app.buttons["closeLectureSources"].tap()
        app.buttons["duoTable"].tap()
        XCTAssertLessThan(first.frame.maxX, second.frame.minX)
        XCTAssertEqual(panes.count, 2)
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

    @MainActor func testCompactPaneSelectionFromLibrary() {
        let app = launch()
        // Leave room for library rows above the fixture's observation strip.
        openBeside(prepareSecondNote(in: app, libraryOrientation: .portrait), in: app)
        XCTAssertTrue(app.buttons["fullscreenSecondPane"].isHittable)
        XCTAssertFalse(app.buttons["switchWorkspacePane"].exists)
        openNotes(app)
        app.buttons.matching(identifier: "noteRow").matching(NSPredicate(format: "label BEGINSWITH 'Duo second note'")).firstMatch.tap()
        XCTAssertTrue(app.buttons["fullscreenFirstPane"].isHittable)
        XCTAssertFalse(app.buttons["fullscreenSecondPane"].isHittable)
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.buttons["fullscreenFirstPane"].isHittable)
        app.buttons["fullscreenFirstPane"].tap()
        XCTAssertEqual(app.scrollViews.matching(NSPredicate(format: "label == 'Note canvas'")).count, 1)
    }

    @MainActor func testSourceOpensBesideOnlyFromMenuAndPreviewsFullscreen() {
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
        XCTAssertFalse(app.descendants(matching: .any)["workspaceDivider"].firstMatch.waitForExistence(timeout: 1))
        openBeside(source, in: app, action: "Open beside note")
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
