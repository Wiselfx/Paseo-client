import XCTest

/// The reported bug: after a rewind and sending the restored text, the keyboard keeps closing when
/// you try to type. Strict version: one tap only (no retry), the keyboard must come up and must
/// still be up a few seconds after typing.
@MainActor
final class RewindKeyboardTests: XCTestCase {
    private let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launch()
        try connectToTestDaemon(app)
    }

    private var composer: XCUIElement {
        let textView = app.textViews["composer.draft"]
        return textView.exists ? textView : app.textFields["composer.draft"]
    }

    private func sendAndWaitForReply(_ text: String) {
        composer.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "keyboard before typing \(text)")
        composer.typeText(text)
        XCTAssertTrue(app.buttons["Send message"].waitForExistence(timeout: 10))
        app.buttons["Send message"].tap()
        XCTAssertTrue(app.staticTexts[text].waitForExistence(timeout: 40))
        // The agent has finished when the button reads "Send message" or the mic button is back.
        Thread.sleep(forTimeInterval: 6)
    }

    func testKeyboardStaysUpAfterRewindSendAndTap() throws {
        sendAndWaitForReply("keyboard one")
        sendAndWaitForReply("keyboard two")

        app.staticTexts["keyboard one"].press(forDuration: 1.0)
        let rewind = app.buttons["Rewind conversation"]
        XCTAssertTrue(rewind.waitForExistence(timeout: 5))
        rewind.tap()
        Thread.sleep(forTimeInterval: 3)
        let confirmations = app.buttons.matching(NSPredicate(format: "label == %@", "Rewind conversation"))
        XCTAssertGreaterThan(confirmations.count, 0, "Rewind confirmation not found")
        confirmations.element(boundBy: max(confirmations.count - 1, 0)).tap()
        Thread.sleep(forTimeInterval: 3)

        // The restored text is in the composer: send it.
        XCTAssertTrue(app.buttons["Send message"].waitForExistence(timeout: 10))
        app.buttons["Send message"].tap()
        XCTAssertTrue(app.staticTexts["keyboard one"].waitForExistence(timeout: 40))
        Thread.sleep(forTimeInterval: 8)

        // One tap, as a person does.
        composer.tap()
        let appeared = app.keyboards.firstMatch.waitForExistence(timeout: 3)
        add(shot("after-one-tap"))
        XCTAssertTrue(appeared, "keyboard did not appear after ONE tap on the composer")

        composer.typeText("typed after")
        Thread.sleep(forTimeInterval: 3)
        add(shot("three-seconds-after-typing"))
        XCTAssertTrue(app.keyboards.firstMatch.exists, "keyboard closed by itself after typing")
        XCTAssertEqual(composer.value as? String, "typed after")
    }

    private func shot(_ name: String) -> XCTAttachment {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        return attachment
    }
}
