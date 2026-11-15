import XCTest

/// Settings for the throwaway test daemon. They come from the environment (the Mac gate passes
/// `PASEO_*` lines from `~/paseo-sim.env`), never from the repo.
enum TestDaemon {
    /// `host:port`, for example `192.0.2.10:6768`.
    static var hostAndPort: String? { ProcessInfo.processInfo.environment["PASEO_TEST_HOST"] }
    static var password: String { ProcessInfo.processInfo.environment["PASEO_TEST_PASSWORD"] ?? "" }
    static var host: String? { hostAndPort?.split(separator: ":").first.map(String.init) }
    static var port: String? { hostAndPort?.split(separator: ":").dropFirst().first.map(String.init) }
}

/// Connects the app to the test daemon from `TestDaemon`, unless the composer is already on screen.
/// Skips the test when `PASEO_TEST_HOST` is not set.
@MainActor
func connectToTestDaemon(_ app: XCUIApplication) throws {
    guard let host = TestDaemon.host, let port = TestDaemon.port else {
        throw XCTSkip("PASEO_TEST_HOST is not set")
    }

    // Already connected: the composer is on screen.
    if app.textViews["composer.draft"].waitForExistence(timeout: 3)
        || app.textFields["composer.draft"].exists
    {
        return
    }

    let directConnection = app.buttons
        .matching(NSPredicate(format: "label BEGINSWITH 'Direct connection'")).firstMatch
    XCTAssertTrue(directConnection.waitForExistence(timeout: 5), "Direct connection button not found")
    directConnection.tap()

    let hostField = app.textFields["connect.host"]
    XCTAssertTrue(hostField.waitForExistence(timeout: 5), "connect.host did not appear")
    hostField.tap()
    hostField.typeText(host)

    // Select the prefilled port so typing replaces it.
    let portField = app.textFields["connect.port"]
    portField.press(forDuration: 1.0)
    let selectAll = app.menuItems["Select All"]
    if selectAll.exists {
        selectAll.tap()
    }
    portField.typeText(port)

    let passwordField = app.secureTextFields["connect.password"]
    passwordField.tap()
    if !TestDaemon.password.isEmpty {
        passwordField.typeText(TestDaemon.password)
    }

    app.buttons["connect.submit"].tap()

    // The system may offer to save the password to the keychain.
    let notNow = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Not Now"]
    if notNow.waitForExistence(timeout: 5) {
        notNow.tap()
    }

    let composerShown = app.textViews["composer.draft"].waitForExistence(timeout: 20)
        || app.textFields["composer.draft"].waitForExistence(timeout: 1)
    XCTAssertTrue(composerShown, "composer did not appear after connecting")
}
