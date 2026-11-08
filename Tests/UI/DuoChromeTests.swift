import XCTest
import Vision

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
    @MainActor private func verifyCombinedHistory(_ app: XCUIApplication, book: Bool = false) {
        XCTAssertFalse(app.buttons["Undo"].exists)
        XCTAssertFalse(app.buttons["Redo"].exists)
        newNote(app)
        // This optional functional check uses an isolated copy with the
        // CanvasSession finger-input default enabled; all UI sources stay exact.
        if app.buttons.matching(identifier: "showNotes").allElementsBoundByIndex.contains(where: \.isHittable),
           app.buttons.matching(identifier: "newNote").allElementsBoundByIndex.contains(where: \.isHittable) {
            button(app, "showNotes").tap()
        }
        let canvases = app.scrollViews.matching(NSPredicate(format: "label == 'Note canvas'"))
        if book {
            XCTAssertEqual(canvases.count, 2)
            XCTAssertFalse(app.buttons["switchWorkspacePane"].exists)
            XCTAssertFalse(app.buttons["pageNavigator"].exists)
            XCTAssertLessThan(button(app, "secondPaneTitle").frame.maxX, button(app, "firstPaneTitle").frame.minX)
            XCTAssertEqual(button(app, "showNotes").frame.midX, button(app, "openSettings").frame.midX, accuracy: 6)
        }
        let canvas = book ? app.descendants(matching: .any)["workspaceFirstPane"].firstMatch.scrollViews.firstMatch : canvases.firstMatch
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.30, dy: 0.48)).press(forDuration: 0.1,
            thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.60, dy: 0.54)))

        let source = button(app, "openSettings").frame
        let title = book ? app.buttons["firstPaneTitle"] : app.textFields["currentNoteTitle"]
        let titleFrame = title.frame
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
        XCTAssertEqual(title.frame, titleFrame)
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

    @MainActor func testOpenSettingsOpensFromVisibleRailButton() throws {
        let app = launch()
        let canvases = app.scrollViews.matching(NSPredicate(format: "label == 'Note canvas'"))
        XCTAssertEqual(canvases.count, 1)
        XCTAssertGreaterThan(canvases.firstMatch.frame.width, 800, "Set Device Hub to fully open")
        try verifySettingsOrigin(app, combinedHistory: false)
    }

    @MainActor func testBookSettingsOpensFromVisibleRailButton() throws {
        let app = launch()
        newNote(app)
        XCTAssertEqual(app.scrollViews.matching(NSPredicate(format: "label == 'Note canvas'")).count, 2,
                       "Set Device Hub to Book")
        try verifySettingsOrigin(app, combinedHistory: true)
    }

    @MainActor func testFoldedSettingsOpensFromVisibleRailButton() throws {
        let app = launch()
        let canvases = app.scrollViews.matching(NSPredicate(format: "label == 'Note canvas'"))
        XCTAssertEqual(canvases.count, 1)
        XCTAssertLessThan(canvases.firstMatch.frame.width, 800, "Set Device Hub to the folded cover display")
        try verifySettingsOrigin(app, combinedHistory: true)
    }

    // The rail can report the correct button frame even when the popover opens at the window origin.
    @MainActor private func verifySettingsOrigin(_ app: XCUIApplication, combinedHistory: Bool) throws {
        for attempt in 0..<2 {
            let ellipsis = button(app, "openSettings")
            let source = ellipsis.frame
            XCTAssertGreaterThan(source.midX, app.frame.midX)
            ellipsis.tap()
            let panel = app.descendants(matching: .any)["settingsPanel"].firstMatch
            XCTAssertTrue(panel.waitForExistence(timeout: 5))
            let popover = app.popovers.firstMatch
            XCTAssertTrue(popover.frame.contains(CGPoint(x: source.midX, y: source.midY)),
                          "Popover \(popover.frame) must cover its ellipsis \(source)")
            XCTAssertGreaterThan(panel.frame.maxX, source.minX)
            XCTAssertLessThan(panel.frame.minY, source.midY)
            XCTAssertGreaterThan(panel.frame.maxY, source.midY)
            if attempt == 0 { try assertVisibleSettingsText(panel, history: combinedHistory) }
            XCTAssertEqual(panel.buttons["undo"].exists, combinedHistory)
            XCTAssertEqual(panel.buttons["redo"].exists, combinedHistory)
            button(app, "openTrash").tap()
            button(app, "Back to settings").tap()
            app.otherElements["PopoverDismissRegion"].coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.75)).tap()
            XCTAssertTrue(panel.waitForNonExistence(timeout: 5))
        }
    }
    // Device Hub supplies the hinge input. Keep the same app and the current menu
    // alive between poses to exercise teardown of the old rail and its presenter.
    // Set BUKO_LIVE_FOLD=1 in the test runner. Start on the closed cover for
    // cover → Book → open, or fully open for the direct return to the cover.
    @MainActor func testOpenMenuAcrossLiveHingeChanges() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["BUKO_LIVE_FOLD"] == "1")
        executionTimeAllowance = 1800
        let app = launch()
        newNote(app)
        let canvases = app.scrollViews.matching(NSPredicate(format: "label == 'Note canvas'"))
        let panel = app.descendants(matching: .any)["settingsPanel"].firstMatch
        let popover = app.popovers.firstMatch

        func openMenu(history: Bool) throws {
            let ellipsis = button(app, "openSettings")
            let source = ellipsis.frame
            ellipsis.tap()
            XCTAssertTrue(panel.waitForExistence(timeout: 5))
            XCTAssertTrue(popover.frame.contains(CGPoint(x: source.midX, y: source.midY)))
            try assertVisibleSettingsText(panel, history: history)
        }
        func awaitFold(_ instruction: String) {
            print("DEVICE HUB: \(instruction)")
            XCTAssertTrue(panel.waitForNonExistence(timeout: 480), "The previous menu must dismiss on a fold")
            XCTAssertFalse(popover.exists)
        }
        func waitForCanvases(_ count: Int, width: ClosedRange<CGFloat>) {
            let matches = NSPredicate { _, _ in
                canvases.count == count && width.contains(canvases.firstMatch.frame.width)
            }
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: matches, object: nil)],
                                          timeout: 15), .completed)
        }
        if canvases.count == 1 && canvases.firstMatch.frame.width > 800 {
            try openMenu(history: false)
            awaitFold("Close to cover")
            waitForCanvases(1, width: 200...799)
            try verifySettingsOrigin(app, combinedHistory: true)
            return
        }

        waitForCanvases(1, width: 200...799)
        try openMenu(history: true)
        let grid = panel.switches["gridLines"].switches.firstMatch
        let originalGrid = grid.value as? String
        grid.tap()
        XCTAssertNotEqual(grid.value as? String, originalGrid)
        grid.tap()
        awaitFold("Fold out to Book")
        waitForCanvases(2, width: 200...800)
        try openMenu(history: true)
        button(app, "openTrash").tap()
        awaitFold("Unfold fully")
        waitForCanvases(1, width: 800...2000)
        try verifySettingsOrigin(app, combinedHistory: false)
    }

    // Icon-only toolbar labels expose the same accessibility names as visible
    // text. Check the actual menu pixels so hiding a title fails this test.
    @MainActor private func assertVisibleSettingsText(_ panel: XCUIElement, history: Bool) throws {
        let picture = panel.screenshot()
        let attachment = XCTAttachment(screenshot: picture)
        attachment.name = history ? "Grid and history menu" : "Grid menu"
        attachment.lifetime = .keepAlways
        add(attachment)
        let image = try XCTUnwrap(picture.image.cgImage)
        let request = VNRecognizeTextRequest()
        request.recognitionLanguages = ["en-US"]
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: image).perform([request])
        let words = (request.results ?? []).flatMap { observation in
            (observation.topCandidates(1).first?.string ?? "").split(whereSeparator: { !$0.isLetter }).map(String.init)
        }
        for title in history ? ["Grid", "Undo", "Redo"] : ["Grid"] {
            XCTAssertTrue(words.contains(title), "Missing visible \(title) in \(words)")
        }
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
    @MainActor func testBookSidebarAndPaneHeaders() {
        let app = launch()
        newNote(app)
        let toggle = button(app, "showNotes")
        if app.buttons.matching(identifier: "newNote").allElementsBoundByIndex.contains(where: \.isHittable) {
            toggle.tap()
        }
        let canvases = app.scrollViews.matching(NSPredicate(format: "label == 'Note canvas'"))
        let frames = canvases.allElementsBoundByIndex.map(\.frame).sorted { $0.minX < $1.minX }
        XCTAssertEqual(frames.count, 2, "Set Device Hub to book pose")
        XCTAssertEqual(frames[1].minX - frames[0].maxX, 20, accuracy: 1)
        let left = button(app, "secondPaneTitle"), right = button(app, "firstPaneTitle")
        XCTAssertLessThan(left.frame.maxX, right.frame.minX)
        for id in ["firstPaneTitle", "fullscreenFirstPane", "fullscreenSecondPane"] {
            XCTAssertEqual(button(app, id).frame.midY, left.frame.midY, accuracy: 1)
        }
        XCTAssertEqual(toggle.frame.midX, button(app, "openSettings").frame.midX, accuracy: 6)
        XCTAssertFalse(app.buttons["switchWorkspacePane"].exists)
        shot(app, "Book headers and right sidebar control")
        toggle.tap()
        XCTAssertLessThan(button(app, "newNote").frame.maxX, frames[0].maxX)
        XCTAssertEqual(canvases.allElementsBoundByIndex.map(\.frame).sorted { $0.minX < $1.minX }, frames)
        toggle.tap()
    }

    @MainActor func testBookMenuAndHistory() {
        let app = launch()
        verifyCombinedHistory(app, book: true)
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
    @MainActor func testWorkspaceToolbarActions() throws {
        let app = launch()
        if app.buttons.matching(identifier: "hideNotes").allElementsBoundByIndex.contains(where: \.isHittable) {
            button(app, "hideNotes").tap()
        }
        button(app, "Eraser").tap()
        button(app, "Pen").tap()
        button(app, "lectureSources").tap()
        XCTAssertTrue(app.buttons["closeLectureSources"].waitForExistence(timeout: 8))
        button(app, "closeLectureSources").tap()
        shot(app, "Clear drawing toolbar and ellipsis")
        button(app, "openSettings").tap()
        XCTAssertTrue(app.buttons["openDevelopment"].waitForExistence(timeout: 8))
        try assertVisibleSettingsText(app.descendants(matching: .any)["settingsPanel"].firstMatch, history: false)
    }

    @MainActor func testOpenToolbarOrder() {
        let app = launch()
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
        let restored = title.frame
        XCTAssertEqual(restored.minX, titleFrame.minX, accuracy: 1.0 / 3)
        XCTAssertEqual(restored.minY, titleFrame.minY, accuracy: 1.0 / 3)
        XCTAssertEqual(restored.width, titleFrame.width, accuracy: 1.0 / 3)
        XCTAssertEqual(restored.height, titleFrame.height, accuracy: 1.0 / 3)
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
