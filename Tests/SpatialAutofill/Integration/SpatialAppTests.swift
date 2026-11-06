import XCTest

final class SpatialAppTests: XCTestCase {
    @MainActor private func launch(_ name: String, baseline: Bool = false, resume: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--spatial-fixture",name,"-detailedAutofillPreview","NO","-canvasAllowsFingerDrawing","YES"]
        if baseline { app.launchArguments.append("--spatial-baseline") }
        if resume { app.launchArguments.append("--spatial-resume") }
        app.launch()
        XCTAssertTrue(app.buttons["spatialSetup"].waitForExistence(timeout:20))
        app.buttons["spatialSetup"].tap()
        XCTAssertTrue(app.staticTexts["spatialReady"].waitForExistence(timeout:40),app.staticTexts["spatialStatus"].label)
        return app
    }
    @MainActor private func capture(_ app: XCUIApplication, expected: String? = nil) {
        app.buttons["spatialCapture"].tap()
        XCTAssertTrue(app.staticTexts["spatialResult"].waitForExistence(timeout:120))
        Thread.sleep(forTimeInterval:1.2) // Inspect the settled production transition.
        screenshot(app,"Finished circle")
        if let expected { XCTAssertEqual(app.staticTexts["spatialResult"].label,expected) }
        if expected == "proposal" {
            let name=app.launchArguments[1]
            let target=["static":"static scope","dynamic":"dynamic scope","wrapped":"static scope","single":"parsing","threads":"thread","question-dimensions":"ab","question-new-dimensions":"ab","question-why":"matrix multiplication"][name]!
            XCTAssertTrue(app.staticTexts["spatialTarget"].label.lowercased().contains(target),app.staticTexts["spatialTarget"].label)
            let requestAndDraft = (app.staticTexts["spatialTarget"].value as? String ?? "").lowercased()
            let parts = requestAndDraft.components(separatedBy:" | ")
            XCTAssertEqual(parts.count,2,requestAndDraft)
            guard parts.count == 2 else { return }
            let criteria: [String:[[String]]] = [
                "static":[["nested","enclosing","lexical"]],
                "wrapped":[["nested","enclosing","lexical"]],
                "dynamic":[["call"],["search"]],
                "single":[["grammar"],["syntax tree"]],
                "threads":[["share","sharing"],["address space"],["own"],["stack"]],
                "question-dimensions":[["ab"],["ba"],["2 by 2","2×2","2 × 2","2x2","2 x 2"],["3 by 3","3×3","3 × 3","3x3","3 x 3"]],
                "question-new-dimensions":[["ab"],["ba"],["4 by 4","4×4","4 × 4","4x4","4 x 4"],["6 by 6","6×6","6 × 6","6x6","6 x 6"]],
                "question-why":[["order","compos"],["different","differ","chang"]]
            ]
            for alternatives in criteria[name]! {
                XCTAssertTrue(alternatives.contains { parts[1].contains($0) },requestAndDraft)
            }
            if name == "threads" { XCTAssertTrue(parts[0].contains("memory ownership"),requestAndDraft) }
        }
    }
    @MainActor private func checkpoint(_ app: XCUIApplication, original: Bool, records: Int) {
        app.buttons["spatialCheckpoint"].tap()
        let status=app.staticTexts["spatialStatus"].label
        XCTAssertTrue(status.contains("original=\(original);"),status)
        XCTAssertTrue(status.contains("liveOriginal=\(original);"),status)
        XCTAssertTrue(status.contains("liveMatchesStore=true;"),status)
        XCTAssertTrue(status.contains("records=\(records);"),status)
    }
    @MainActor private func ready(_ app: XCUIApplication) {
        let accept=app.buttons["acceptAutofill"]
        XCTAssertTrue(accept.waitForExistence(timeout:10))
        expectation(for:NSPredicate(format:"enabled == true"),evaluatedWith:accept)
        waitForExpectations(timeout:15)
        let visible = app.windows.firstMatch.frame.insetBy(dx: -1, dy: -1)
        for button in [accept, app.buttons["declineAutofill"]] {
            XCTAssertTrue(visible.contains(button.frame), "Preview control outside viewport: \(button.frame)")
            XCTAssertTrue(button.isHittable)
        }
    }
    @MainActor private func gone(_ app: XCUIApplication) {
        expectation(for:NSPredicate(format:"exists == false"),evaluatedWith:app.buttons["acceptAutofill"])
        waitForExpectations(timeout:8)
    }
    @MainActor func testQQuestionDimensionsAcceptUndo() {
        let app=launch("question-dimensions"); capture(app,expected:"proposal"); ready(app)
        checkpoint(app,original:true,records:0)
        XCTAssertEqual(app.staticTexts["autofillPreviewTitle"].label, "Calculated from your notes")
        XCTAssertFalse(app.buttons["autofillSourceLink"].exists)
        app.buttons["acceptAutofill"].tap(); gone(app)
        checkpoint(app,original:false,records:1)
        app.buttons["Undo"].tap(); checkpoint(app,original:true,records:0)
    }
    @MainActor func testRQuestionWhyDecline() {
        let app=launch("question-why"); capture(app,expected:"proposal"); ready(app)
        checkpoint(app,original:true,records:0)
        XCTAssertTrue(app.buttons["autofillSourceLink"].firstMatch.exists)
        app.buttons["autofillSourceLink"].firstMatch.tap()
        XCTAssertTrue(app.buttons["closeLecturePDF"].waitForExistence(timeout:8))
        screenshot(app,"Explanation cited lecture")
        app.buttons["closeLecturePDF"].tap()
        app.buttons["declineAutofill"].tap(); gone(app)
        checkpoint(app,original:true,records:0)
    }
    @MainActor func testSQuestionNewDimensionsAcceptUndo() {
        let app=launch("question-new-dimensions"); capture(app,expected:"proposal"); ready(app)
        XCTAssertEqual(app.staticTexts["autofillPreviewTitle"].label, "Calculated from your notes")
        checkpoint(app,original:true,records:0)
        app.buttons["acceptAutofill"].tap(); gone(app)
        checkpoint(app,original:false,records:1)
        app.buttons["Undo"].tap(); checkpoint(app,original:true,records:0)
    }
    @MainActor func testTQuestionMissingInputWithheld() {
        let app=launch("question-missing-input"); capture(app,expected:"no-proposal")
        XCTAssertFalse(app.buttons["acceptAutofill"].exists)
        checkpoint(app,original:true,records:0)
    }
    @MainActor func testAStaticAcceptUndoRedoAndPersistence() {
        let app=launch("static"); capture(app,expected:"proposal"); ready(app)
        checkpoint(app,original:true,records:0)
        XCTAssertTrue(app.buttons["autofillSourceLink"].firstMatch.exists)
        app.buttons["autofillSourceLink"].firstMatch.tap()
        XCTAssertTrue(app.buttons["closeLecturePDF"].waitForExistence(timeout:8))
        screenshot(app,"Actual cited PDF")
        app.buttons["closeLecturePDF"].tap()
        app.buttons["acceptAutofill"].tap(); gone(app)
        checkpoint(app,original:false,records:1); screenshot(app,"Accepted grounded handwriting")
        XCTAssertTrue(app.buttons["Undo"].isEnabled); app.buttons["Undo"].tap()
        checkpoint(app,original:true,records:0)
        XCTAssertTrue(app.buttons["Redo"].isEnabled); app.buttons["Redo"].tap()
        checkpoint(app,original:false,records:1)
        app.terminate()
        let resumed=launch("static",resume:true)
        checkpoint(resumed,original:false,records:1); screenshot(resumed,"Accepted content after relaunch")
    }
    @MainActor func testBDynamicDeclineAndRepeat() {
        let app=launch("dynamic"); capture(app,expected:"proposal"); ready(app)
        checkpoint(app,original:true,records:0)
        app.buttons["declineAutofill"].tap(); gone(app)
        Thread.sleep(forTimeInterval:1)
        checkpoint(app,original:true,records:0)
        capture(app,expected:"proposal"); ready(app)
        app.buttons["declineAutofill"].tap(); gone(app)
        checkpoint(app,original:true,records:0)
    }
    @MainActor func testCWrappedAcceptUndo() {
        let app=launch("wrapped"); capture(app,expected:"proposal"); ready(app)
        checkpoint(app,original:true,records:0)
        app.buttons["acceptAutofill"].tap(); gone(app)
        checkpoint(app,original:false,records:1)
        app.buttons["Undo"].tap(); checkpoint(app,original:true,records:0)
    }
    @MainActor func testDOrdinaryHeadingFallback() {
        let app=launch("single"); capture(app,expected:"proposal"); ready(app)
        checkpoint(app,original:true,records:0)
        app.buttons["acceptAutofill"].tap(); gone(app)
        checkpoint(app,original:false,records:1)
        app.buttons["Undo"].tap(); checkpoint(app,original:true,records:0)
    }
    @MainActor func testECompletePatternDoesNotWrite() {
        let app=launch("complete"); capture(app,expected:"no-proposal")
        XCTAssertFalse(app.buttons["acceptAutofill"].exists); checkpoint(app,original:true,records:0)
    }
    @MainActor func testFAmbiguousPatternDoesNotChooseArbitrarily() {
        let app=launch("ambiguous"); capture(app,expected:"no-proposal")
        XCTAssertFalse(app.buttons["acceptAutofill"].exists); checkpoint(app,original:true,records:0)
    }
    @MainActor func testGNoPDFDoesNotInvent() {
        let app=launch("no-source"); capture(app,expected:"no-proposal")
        XCTAssertFalse(app.buttons["acceptAutofill"].exists); checkpoint(app,original:true,records:0)
    }
    @MainActor func testHRotationAndBackgroundCancellation() {
        let app=launch("static"); capture(app,expected:"proposal"); ready(app)
        XCUIDevice.shared.orientation = .landscapeLeft
        Thread.sleep(forTimeInterval:1)
        ready(app); checkpoint(app,original:true,records:0); screenshot(app,"Landscape preview")
        XCUIDevice.shared.press(.home)
        app.activate(); gone(app)
        checkpoint(app,original:true,records:0)
        XCUIDevice.shared.orientation = .portrait
    }
    @MainActor func testIBaselineStatic() { baseline("static") }
    @MainActor func testJBaselineDynamic() { baseline("dynamic") }
    @MainActor func testKBaselineWrapped() { baseline("wrapped") }
    @MainActor func testLBaselineOrdinaryHeading() { baseline("single") }
    @MainActor func testMThreadsFromSecondPDF() {
        let app=launch("threads"); capture(app,expected:"proposal"); ready(app)
        checkpoint(app,original:true,records:0)
        app.buttons["acceptAutofill"].tap(); gone(app)
        checkpoint(app,original:false,records:1)
        app.buttons["Undo"].tap(); checkpoint(app,original:true,records:0)
    }
    @MainActor func testNBaselineThreads() { baseline("threads") }
    @MainActor func testOCancelDuringProcessing() {
        let app=launch("static")
        app.buttons["spatialCapture"].tap()
        let dismiss=app.buttons["Dismiss autofill"]
        XCTAssertTrue(dismiss.waitForExistence(timeout:8)); dismiss.tap()
        Thread.sleep(forTimeInterval:8)
        XCTAssertFalse(app.buttons["acceptAutofill"].exists)
        XCTAssertFalse(app.staticTexts["spatialResult"].exists)
        checkpoint(app,original:true,records:0)
    }
    @MainActor func testPDrawingCancelsAndInterleavedUndo() {
        let app=launch("single")
        app.buttons["Pen"].press(forDuration:1)
        let toggle=app.switches["Draw with finger"]
        if toggle.waitForExistence(timeout:3) { toggle.tap() }
        else { app.buttons["Draw with finger"].tap() }
        checkpoint(app,original:true,records:0)
        capture(app,expected:"proposal"); ready(app)
        app.coordinate(withNormalizedOffset:CGVector(dx:0.25,dy:0.78)).press(forDuration:0.1,
            thenDragTo:app.coordinate(withNormalizedOffset:CGVector(dx:0.55,dy:0.78)))
        gone(app)
        Thread.sleep(forTimeInterval:1)
        checkpoint(app,original:false,records:0)
        app.buttons["Undo"].tap(); checkpoint(app,original:true,records:0)
        capture(app,expected:"proposal"); ready(app)
        app.buttons["acceptAutofill"].tap(); gone(app)
        checkpoint(app,original:false,records:1)
        app.coordinate(withNormalizedOffset:CGVector(dx:0.25,dy:0.78)).press(forDuration:0.1,
            thenDragTo:app.coordinate(withNormalizedOffset:CGVector(dx:0.55,dy:0.78)))
        app.buttons["Undo"].tap(); checkpoint(app,original:false,records:1)
        app.buttons["Undo"].tap(); checkpoint(app,original:true,records:0)
    }
    @MainActor private func baseline(_ name: String) {
        let app=launch(name,baseline:true); capture(app)
        checkpoint(app,original:true,records:0)
        if app.buttons["declineAutofill"].exists { app.buttons["declineAutofill"].tap() }
        else if app.buttons["Dismiss autofill"].exists { app.buttons["Dismiss autofill"].tap() }
        checkpoint(app,original:true,records:0)
    }
    @MainActor private func screenshot(_ app:XCUIApplication,_ title:String) {
        let a=XCTAttachment(screenshot:app.screenshot()); a.name=title; a.lifetime = .keepAlways; add(a)
    }
}
