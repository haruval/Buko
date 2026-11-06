import XCTest

/// Run each pose-specific case with Device Hub already in the named pose.
/// Prepare with Tests/Duo/prepare_ui.py --production-ui and run the isolated app first.
/// Add --finger-input for the history cases; select a note with one source before
/// the populated Sources case. Attaches without relaunching after each pose change.
final class DuoChromeTests: XCTestCase {
    @MainActor private func launch() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))
        if app.otherElements["PopoverDismissRegion"].exists {
            app.otherElements["PopoverDismissRegion"].coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.75)).tap()
        } else if app.descendants(matching: .any)["settingsPanel"].firstMatch.exists {
            button(app, "openSettings").tap()
        }
        return app
    }
    @MainActor private func newNote(_ app: XCUIApplication) {
        if !app.buttons.matching(identifier: "newNote").allElementsBoundByIndex.contains(where: \.isHittable) {
            button(app, "showNotes").tap()
        }
        button(app, "newNote").tap()
    }
    @MainActor private func button(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        let visible = app.buttons.matching(identifier: id).allElementsBoundByIndex.filter(\.isHittable)
        XCTAssertEqual(visible.count, 1, "One visible \(id): \(app.debugDescription)")
        return visible.first ?? app.buttons[id].firstMatch
    }
    @MainActor private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
        print("DUO CHROME \(name)\n\(app.debugDescription)")
    }
    @MainActor private func assertVerticalOrder(_ app: XCUIApplication) {
        let page = button(app, "pageNavigator"), settings = button(app, "openSettings"), pen = button(app, "Pen")
        XCTAssertLessThan(page.frame.maxY, settings.frame.minY)
        XCTAssertLessThan(settings.frame.maxY, pen.frame.minY)
        XCTAssertEqual(settings.frame.midX, pen.frame.midX, accuracy: 6)
    }
    @MainActor private func verifyCombinedHistory(_ app: XCUIApplication) {
        XCTAssertFalse(app.buttons["Undo"].exists)
        XCTAssertFalse(app.buttons["Redo"].exists)
        newNote(app)
        // This optional functional check uses an isolated copy with the
        // CanvasSession finger-input default enabled; all UI sources stay exact.
        if app.buttons.matching(identifier: "showNotes").allElementsBoundByIndex.contains(where: \.isHittable),
           app.buttons.matching(identifier: "newNote").allElementsBoundByIndex.contains(where: \.isHittable) {
            button(app, "showNotes").tap()
        }
        let canvas = app.scrollViews.matching(NSPredicate(format: "label == 'Note canvas'"))
            .firstMatch
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.30, dy: 0.48)).press(forDuration: 0.1,
            thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.60, dy: 0.54)))

        let source = button(app, "openSettings").frame
        let titleFrame = app.textFields["currentNoteTitle"].frame
        button(app, "openSettings").tap()
        assertCombinedPopover(app, source: source, canvas: canvas.frame)
        let undo = button(app, "undo"), redo = button(app, "redo")
        XCTAssertTrue(undo.isEnabled); XCTAssertFalse(redo.isEnabled)
        shot(app, "Combined Undo Redo Settings")
        undo.tap()
        XCTAssertFalse(undo.isEnabled)
        XCTAssertTrue(redo.isEnabled)
        redo.tap()
        XCTAssertTrue(undo.isEnabled)
        XCTAssertFalse(redo.isEnabled)
        app.otherElements["PopoverDismissRegion"].coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.75)).tap()
        XCTAssertEqual(app.textFields["currentNoteTitle"].frame, titleFrame)
    }
    @MainActor private func assertCombinedPopover(_ app: XCUIApplication, source: CGRect, canvas: CGRect) {
        let popover = app.popovers.firstMatch
        XCTAssertTrue(popover.waitForExistence(timeout: 5), "Compact mode must remain a popover")
        XCTAssertTrue(popover.frame.contains(CGPoint(x: source.midX, y: source.midY)))
        XCTAssertGreaterThanOrEqual(popover.frame.minX, canvas.minX)
        XCTAssertLessThanOrEqual(popover.frame.maxX, canvas.maxX + 1)
        let undo = button(app, "undo"), redo = button(app, "redo")
        let grid = app.descendants(matching: .any)["gridLines"].firstMatch
        XCTAssertLessThan(undo.frame.maxY, redo.frame.minY)
        XCTAssertLessThan(redo.frame.maxY, grid.frame.minY)
        XCTAssertLessThan(undo.frame.minY, popover.frame.minY + 65)
    }
    @MainActor func testCombinedMenuPopoverLayout() {
        let app = launch()
        let canvas = app.scrollViews.matching(NSPredicate(format: "label == 'Note canvas' ")).firstMatch
        let source = button(app, "openSettings").frame
        button(app, "openSettings").tap()
        assertCombinedPopover(app, source: source, canvas: canvas.frame)
        XCTAssertTrue(app.textFields["currentNoteTitle"].exists)
        shot(app, "Native combined menu")
    }
    @MainActor func testBookMenuAndHistory() {
        let app = launch()
        XCTAssertTrue(app.descendants(matching: .any)["bookLibraryPanel"].firstMatch.isHittable, "Set Device Hub to book pose")
        assertVerticalOrder(app)
        verifyCombinedHistory(app)
        shot(app, "Book toolbar")
    }
    @MainActor func testClosed02LibraryAndHistory() {
        let app = launch()
        if !app.buttons.matching(identifier: "newNote").allElementsBoundByIndex.contains(where: \.isHittable) {
            button(app, "showNotes").tap()
        }
        XCTAssertTrue(button(app, "newNote").isHittable)
        XCTAssertFalse(app.buttons.matching(identifier: "hideNotes").allElementsBoundByIndex.contains(where: \.isHittable))
        shot(app, "Closed library without duplicate toggle")
        button(app, "showNotes").tap()
        assertVerticalOrder(app)
        verifyCombinedHistory(app)
        shot(app, "Closed toolbar")
        button(app, "openSettings").tap()
        shot(app, "Closed menu final")
    }
    @MainActor func testOpenToolbarOrder() {
        let app = launch()
        XCTAssertFalse(app.descendants(matching: .any)["bookLibraryPanel"].firstMatch.isHittable, "Set Device Hub to fully open")
        let canvas = app.scrollViews.matching(NSPredicate(format: "label == 'Note canvas'")).firstMatch
        XCTAssertGreaterThan(canvas.frame.width, 800, "Set Device Hub to fully open")
        assertVerticalOrder(app)
        XCTAssertTrue(app.buttons["Undo"].exists)
        XCTAssertTrue(app.buttons["Redo"].exists)
        button(app, "openSettings").tap()
        XCTAssertTrue(app.descendants(matching: .any)["settingsPanel"].firstMatch.exists)
        XCTAssertFalse(app.buttons["undo"].exists)
        app.otherElements["PopoverDismissRegion"].coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.75)).tap()
        shot(app, "Open toolbar page menu tools")
    }
    @MainActor func testOpenSettingsAnchorsToToolbar() {
        let app = launch()
        if app.buttons["hideNotes"].isHittable { app.buttons["hideNotes"].tap() }
        let canvas = app.scrollViews.matching(NSPredicate(format: "label == 'Note canvas'")).firstMatch
        XCTAssertGreaterThan(canvas.frame.width, 800, "Set Device Hub to fully open")
        let title = app.textFields["currentNoteTitle"]
        XCTAssertTrue(title.exists)
        let titleFrame = title.frame
        let source = button(app, "openSettings").frame
        button(app, "openSettings").tap()
        let panel = app.descendants(matching: .any)["settingsPanel"].firstMatch
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        // Native Liquid Glass popovers grow over their source control.
        XCTAssertLessThanOrEqual(panel.frame.maxX, source.maxX + 16)
        XCTAssertGreaterThanOrEqual(panel.frame.maxX, source.midX - 30)
        XCTAssertEqual(panel.frame.midY, source.midY, accuracy: 30)
        XCTAssertGreaterThan(panel.frame.minX, titleFrame.maxX)
        XCTAssertFalse(app.buttons["undo"].exists)
        shot(app, "Settings anchored to ellipsis")
        app.buttons["openTrash"].tap()
        XCTAssertTrue(app.staticTexts["Trash is empty"].waitForExistence(timeout: 5))
        app.buttons["Back to settings"].tap()
        XCTAssertTrue(app.buttons["openDevelopment"].waitForExistence(timeout: 5))
        // Dismiss through the native outside-tap behavior.
        app.otherElements["PopoverDismissRegion"].coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.75)).tap()
        XCTAssertTrue(NSPredicate(format: "exists == false").evaluate(with: panel))
        XCTAssertEqual(title.frame, titleFrame)
        button(app, "openSettings").tap()
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        shot(app, "Settings reopened at ellipsis")
    }
    @MainActor func testOpenSettingsAlphabetPresentation() {
        let app = launch()
        if app.buttons["hideNotes"].isHittable { app.buttons["hideNotes"].tap() }
        button(app, "openSettings").tap()
        app.buttons["openDevelopment"].tap()
        let alphabet = app.buttons["writeAlphabet"]
        XCTAssertTrue(alphabet.waitForExistence(timeout: 5))
        let scroll = app.popovers.firstMatch.scrollViews.firstMatch
        for _ in 0..<6 {
            let viewport = scroll.frame.insetBy(dx: 0, dy: 24)
            if viewport.contains(CGPoint(x: alphabet.frame.midX, y: alphabet.frame.midY)) { break }
            let startY: CGFloat = alphabet.frame.midY > viewport.midY ? 0.75 : 0.25
            scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: startY)).press(forDuration: 0.1,
                thenDragTo: scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)),
                withVelocity: .slow, thenHoldForDuration: 0.3)
        }
        print("Alphabet action \(alphabet.frame), scroll \(scroll.frame)")
        XCTAssertTrue(alphabet.isHittable)
        XCTAssertTrue(app.popovers.firstMatch.frame.contains(alphabet.frame))
        shot(app, "Visible alphabet action in popover")
        alphabet.tap()
        XCTAssertTrue(app.buttons["closeAlphabet"].waitForExistence(timeout: 8))
        app.buttons["closeAlphabet"].tap()
        XCTAssertTrue(app.textFields["currentNoteTitle"].waitForExistence(timeout: 5))
        shot(app, "Returned from alphabet")
    }
    @MainActor func testClosed01SourcesCountImportAndEmptyState() {
        let app = launch()
        func checkSources(_ expected: String) {
            button(app, "lectureSources").tap()
            let count = app.staticTexts["attachedSourcesCount"]
            XCTAssertTrue(count.waitForExistence(timeout: 8))
            XCTAssertEqual(count.label, expected)
            let importer = button(app, "importLecturePDF")
            XCTAssertLessThanOrEqual(count.frame.maxX, importer.frame.minX)
            XCTAssertEqual(count.frame.midY, importer.frame.midY, accuracy: 2)
            for text in ["Sources for this note", "No sources yet", "Import a PDF to read alongside your notes and use with autofill."] {
                XCTAssertFalse(app.staticTexts[text].exists)
            }
            let panel = app.descendants(matching: .any)["sourcesPanel"].firstMatch
            XCTAssertFalse(panel.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Spatial validation'")).firstMatch.exists)
        }
        checkSources("1 attached source")
        let document = button(app, "lectureDocument")
        XCTAssertGreaterThan(document.frame.minY, app.staticTexts["attachedSourcesCount"].frame.maxY)
        document.tap()
        XCTAssertTrue(app.descendants(matching: .any)["lecturePDFContent"].firstMatch.waitForExistence(timeout: 8))
        app.buttons["closeLecturePDF"].tap()
        shot(app, "Populated Sources")
        app.buttons["closeLectureSources"].tap()
        newNote(app)
        checkSources("0 attached sources")
        XCTAssertFalse(app.buttons["lectureDocument"].exists)
        shot(app, "Empty Sources")
        button(app, "closeLectureSources").tap()
    }
}
