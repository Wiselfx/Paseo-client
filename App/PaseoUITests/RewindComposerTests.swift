import XCTest

/// Regression test for a known bug: after a rewind and sending the restored text, the composer
/// takes no input. This test is expected to FAIL until the bug is fixed.
@MainActor
final class RewindComposerTests: XCTestCase {
    private let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launch()
        try connectToTestDaemon(app)
    }

    func testComposerAcceptsTypingAfterRewindAndSend() throws {
        let textView = app.textViews["composer.draft"]
        let composer = textView.exists ? textView : app.textFields["composer.draft"]

        // Send two messages.
        composer.tap()
        composer.typeText("rewind test one")
        app.buttons["Send message"].tap()
        XCTAssertTrue(app.staticTexts["rewind test one"].waitForExistence(timeout: 40))

        composer.tap()
        composer.typeText("rewind test two")
        app.buttons["Send message"].tap()
        XCTAssertTrue(app.staticTexts["rewind test two"].waitForExistence(timeout: 40))

        // Rewind to the first message.
        app.staticTexts["rewind test one"].press(forDuration: 1.0)
        let rewind = app.buttons["Rewind conversation"]
        XCTAssertTrue(rewind.waitForExistence(timeout: 5))
        rewind.tap()

        // Confirm the rewind. The confirmation repeats the label, so take the last match.
        Thread.sleep(forTimeInterval: 3)
        let confirmations = app.buttons.matching(identifier: "Rewind conversation")
        let count = confirmations.count
        XCTAssertGreaterThan(count, 0, "Rewind confirmation not found")
        confirmations.element(boundBy: max(count - 1, 0)).tap()

        // The restored text lands in the composer.
        XCTAssertTrue(waitForComposerValue(composer, "rewind test one"))

        // Send the restored text.
        app.buttons["Send message"].tap()
        XCTAssertTrue(app.staticTexts["rewind test one"].waitForExistence(timeout: 40))

        // This is the bug: the composer must take typing again.
        composer.tap()
        composer.typeText("typed after")
        XCTAssertTrue(waitForComposerValue(composer, "typed after"))

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    /// Polls the composer's value for up to 5 s (10 x 0.5 s).
    private func waitForComposerValue(_ composer: XCUIElement, _ expected: String) -> Bool {
        for _ in 0..<10 {
            if (composer.value as? String) == expected {
                return true
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        return (composer.value as? String) == expected
    }
}
