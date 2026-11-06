import XCTest

final class PreviewSettingsTests: XCTestCase {
    @MainActor func testHandwritingInspectorAndRebuild() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["openSettings"].waitForExistence(timeout: 15))
        app.buttons["openSettings"].tap()
        Thread.sleep(forTimeInterval: 0.7)
        app.buttons["openDevelopment"].tap()
        XCTAssertTrue(app.buttons["previewHandwriting"].waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 0.5)
        app.buttons["previewHandwriting"].tap()
        XCTAssertTrue(app.buttons["rebuildHandwritingCache"].waitForExistence(timeout: 10))
        let status = app.staticTexts["handwritingPreparationStatus"]
        expectation(for: NSPredicate(format: "label ENDSWITH 'scanned for handwriting samples'"), evaluatedWith: status)
        waitForExpectations(timeout: 65)
        let samples = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'handwritingSample.'"))
        XCTAssertTrue(samples.matching(NSPredicate(format: "label CONTAINS 'fallback font'")).firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(samples.matching(NSPredicate(format: "label CONTAINS 'prepared from'")).firstMatch.waitForExistence(timeout: 10))
        app.buttons["rebuildHandwritingCache"].tap()
        XCTAssertFalse(app.buttons["rebuildHandwritingCache"].isEnabled)
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: app.buttons["rebuildHandwritingCache"])
        waitForExpectations(timeout: 65)
        XCTAssertTrue(status.label.hasSuffix("scanned for handwriting samples"))
        XCTAssertTrue(samples.matching(NSPredicate(format: "label CONTAINS 'prepared from'")).firstMatch.waitForExistence(timeout: 10))
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Prepared ink and fallback letters after rebuilding"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["Prepared words"].tap()
        let words = XCTAttachment(screenshot: app.screenshot())
        words.name = "Prepared whole word samples"; words.lifetime = .keepAlways; add(words)
        app.buttons["closeHandwritingPreview"].tap()
    }

    @MainActor func testDetailedPreviewDefaultsOffAndPersists() {
        continueAfterFailure = false
        let app = XCUIApplication()
        func openDev() {
            XCTAssertTrue(app.buttons["openSettings"].waitForExistence(timeout: 15))
            app.buttons["openSettings"].tap()
            Thread.sleep(forTimeInterval: 0.7)
            app.buttons["openDevelopment"].tap()
            XCTAssertTrue(app.switches["detailedPreview"].waitForExistence(timeout: 5))
            Thread.sleep(forTimeInterval: 0.5)
        }
        app.launch(); openDev()
        XCTAssertEqual(app.switches["detailedPreview"].value as? String, "0")
        app.switches["detailedPreview"].tap()
        XCTAssertEqual(app.switches["detailedPreview"].value as? String, "1")
        app.terminate(); app.launch(); openDev()
        XCTAssertEqual(app.switches["detailedPreview"].value as? String, "1")
        app.switches["detailedPreview"].tap()
        XCTAssertEqual(app.switches["detailedPreview"].value as? String, "0")
    }
}
