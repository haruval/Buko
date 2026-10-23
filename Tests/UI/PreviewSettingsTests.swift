import XCTest

final class PreviewSettingsTests: XCTestCase {
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
