import XCTest

final class PDFZoomTests: XCTestCase {
    @MainActor private func open(secondPage: Bool = false) -> (XCUIApplication, XCUIElement) {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = secondPage ? ["--second-page"] : []
        app.launch()
        let pdf = app.descendants(matching: .any)["pdfZoomTestArea"].firstMatch
        XCTAssertTrue(pdf.waitForExistence(timeout: 10))
        XCTAssertEqual(zoom(pdf), 1, accuracy: 0.001)
        return (app, pdf)
    }

    @MainActor private func zoom(_ pdf: XCUIElement) -> Double { Double(pdf.value as? String ?? "") ?? -1 }
    @MainActor private func location(_ pdf: XCUIElement) -> [Double] {
        let values = pdf.label.split(separator: "|").compactMap { Double($0) }
        XCTAssertEqual(values.count, 3)
        return values
    }

    @MainActor func testRepeatedPinchesKeepFocusAndReturnToFit() {
        let (app, pdf) = open()
        let initial = location(pdf)
        pdf.pinch(withScale: 1.8, velocity: 0.5)
        XCTAssertGreaterThan(zoom(pdf), 1.4)
        let enlarged = location(pdf)
        XCTAssertEqual(enlarged[0], initial[0])
        XCTAssertEqual(enlarged[1], initial[1], accuracy: 6)
        XCTAssertEqual(enlarged[2], initial[2], accuracy: 6)
        pdf.pinch(withScale: 1.5, velocity: 0.5)
        XCTAssertGreaterThan(zoom(pdf), 2)
        let twice = location(pdf)
        XCTAssertEqual(twice[1], initial[1], accuracy: 6)
        XCTAssertEqual(twice[2], initial[2], accuracy: 6)
        pdf.swipeLeft()
        XCTAssertGreaterThan(location(pdf)[1], twice[1] + 10, "Zoomed PDFs must still pan normally")
        pdf.pinch(withScale: 3, velocity: 1)
        XCTAssertEqual(zoom(pdf), 6, accuracy: 0.02)
        pdf.pinch(withScale: 0.1, velocity: -1)
        XCTAssertEqual(zoom(pdf), 1, accuracy: 0.001)
        pdf.pinch(withScale: 0.3, velocity: -1)
        XCTAssertEqual(zoom(pdf), 1, accuracy: 0.001)
        pdf.pinch(withScale: 1.6, velocity: 1)
        XCTAssertGreaterThan(zoom(pdf), 1.3, "Reaching the floor must not trap the next zoom-in gesture")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "PDF enlarged with native pinch"; shot.lifetime = .keepAlways; add(shot)
    }

    @MainActor func testCitedPageAndRotation() {
        let (app, pdf) = open(secondPage: true)
        defer { XCUIDevice.shared.orientation = .portrait }
        XCTAssertTrue(app.staticTexts["Page 2 of 2"].waitForExistence(timeout: 5))
        pdf.pinch(withScale: 1.8, velocity: 1)
        let enlarged = zoom(pdf)
        XCTAssertGreaterThan(enlarged, 1.4)
        XCUIDevice.shared.orientation = .landscapeLeft
        Thread.sleep(forTimeInterval: 1)
        XCTAssertEqual(zoom(pdf), enlarged, accuracy: 0.04)
        pdf.pinch(withScale: 0.2, velocity: -1)
        XCTAssertEqual(zoom(pdf), 1, accuracy: 0.001)
        pdf.pinch(withScale: 1.6, velocity: 1)
        XCTAssertGreaterThan(zoom(pdf), 1.3)
        XCUIDevice.shared.orientation = .portrait
        Thread.sleep(forTimeInterval: 1)
        pdf.pinch(withScale: 0.2, velocity: -1)
        XCTAssertEqual(zoom(pdf), 1, accuracy: 0.001)
        XCTAssertTrue(app.staticTexts["Page 2 of 2"].exists)
    }
}
