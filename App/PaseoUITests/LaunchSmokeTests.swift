import XCTest

@MainActor
final class LaunchSmokeTests: XCTestCase {
    private let app = XCUIApplication()

    // This suite does not connect: it checks the screen the app shows on launch.
    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launch()
    }

    func testWelcomeScreenShowsConnectOptions() throws {
        let welcome = app.staticTexts["Welcome to Paseo"].waitForExistence(timeout: 10)
        let alreadyConnected = app.textViews["composer.draft"].exists
            || app.textFields["composer.draft"].exists
        XCTAssertTrue(
            welcome || alreadyConnected,
            "Neither the welcome screen nor the composer is shown after launch")
    }
}
