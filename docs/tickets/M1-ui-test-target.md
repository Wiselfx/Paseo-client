# M1: UI test target, connect-form identifiers, first tests

Read `AGENTS.md`, then `docs/tickets/_L-common.md` (upstream-first rules and proof rules apply), then this file.

## Why
Until now nobody could run the app. Now the Mac gate (`Tools/build-gate/build-gate`, verbs `uitest`
and `test`) can run an XCUITest scheme named `PaseoUITests` on a simulator against a throwaway test
daemon. This ticket creates that target and the first tests. The lead runs them; you cannot compile.

## Owns (touch only these)
- `App/project.yml`
- `App/PaseoUITests/` (new folder: new `.swift` files only)
- `Packages/PaseoUI/Sources/PaseoUI/Onboarding/ConnectView.swift` (accessibility identifiers only)
Do NOT edit `App/PaseoClient.xcodeproj` (no xcodegen here; the lead regenerates it on the Mac).
Do NOT edit existing tests.

## Upstream
No upstream equivalent for XCUITest (upstream's app is React Native). The wording the tests match is
what the app already shows. Cite `Upstream: none, test infrastructure` in the commit message.

## Step 1: project.yml
Add this target under `targets:` (keep every existing target as is):

```yaml
  PaseoUITests:
    type: bundle.ui-testing
    platform: iOS
    sources:
      - PaseoUITests
    dependencies:
      - target: PaseoClient
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.wiselfx.paseoclient.UITests
        GENERATE_INFOPLIST_FILE: YES
        SWIFT_VERSION: "6.0"
        TARGETED_DEVICE_FAMILY: "1"
        CODE_SIGN_STYLE: Automatic
        DEVELOPMENT_TEAM: ""
```

Add this scheme under `schemes:` (keep `PaseoWidgets`):

```yaml
  PaseoUITests:
    build:
      targets:
        PaseoClient: all
        PaseoUITests: [test]
    test:
      targets:
        - PaseoUITests
```

## Step 2: identifiers on the connect form
Open `ConnectView.swift`. Find the Host, Port, Password fields and the Connect button (the placeholder
texts are `example.com or 192.0.2.10`, `6767`, `Host password`; the button is labelled `Connect`). Add
exactly these `.accessibilityIdentifier(...)` modifiers, one per control, nothing else:
`connect.host`, `connect.port`, `connect.password`, `connect.submit`.
Use the existing modifier style in the file. Do not change layout, copy or behaviour. Grep that
`accessibilityIdentifier` is already used elsewhere in `Packages/PaseoUI` before you copy its form.

## Step 3: a small helper file `App/PaseoUITests/PaseoUITestSupport.swift`
```swift
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
```
Add one more helper in the same file: a `@MainActor func connectToTestDaemon(_ app: XCUIApplication) throws`
that does this, in order:
1. `throw XCTSkip("PASEO_TEST_HOST is not set")` if `TestDaemon.host` or `TestDaemon.port` is nil.
2. If the composer `app.textViews["composer.draft"]` or `app.textFields["composer.draft"]` already
   exists within 3 s (use `.waitForExistence(timeout: 3)`), return (the app is already connected).
3. Otherwise tap the button whose label starts with `Direct connection` (`app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Direct connection'")).firstMatch`), wait for `app.textFields["connect.host"]`
   (timeout 5), tap it and `typeText` the host; do the same for `connect.port` (first select its text:
   `press(forDuration: 1.0)`, then `app.menuItems["Select All"].tap()` if it exists, then `typeText` the
   port); then the password field (`app.secureTextFields["connect.password"]`), then tap `connect.submit`
   (`app.buttons["connect.submit"]`).
4. If a system alert "Save Password?" appears (`XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Not Now"]`, timeout 5), tap it.
5. Wait for the composer (timeout 20) and `XCTAssertTrue` it exists.

## Step 4: tests, one new file each, all `@MainActor final class ...: XCTestCase`
Each `setUpWithError` sets `continueAfterFailure = false`, launches `XCUIApplication()` with
`app.launch()`, and calls `try connectToTestDaemon(app)`.

`App/PaseoUITests/LaunchSmokeTests.swift`, class `LaunchSmokeTests`:
- `testWelcomeScreenShowsConnectOptions`: do NOT call connect; launch; XCTAssertTrue either the text
  `Welcome to Paseo` exists (timeout 10) or the composer exists (already connected). Pass in both cases.

`App/PaseoUITests/RewindComposerTests.swift`, class `RewindComposerTests` (this reproduces a KNOWN BUG:
after a rewind and sending the restored text, the composer takes no input; this test is expected to FAIL
today and is the regression test for the fix):
- `testComposerAcceptsTypingAfterRewindAndSend`:
  1. Let `composer = app.textViews["composer.draft"]` (fall back to `app.textFields["composer.draft"]`
     if the first does not exist).
  2. Send two messages: tap composer, `typeText("rewind test one")`, tap `app.buttons["Send message"]`,
     wait until `app.staticTexts["rewind test one"]` exists (timeout 40); same for `"rewind test two"`.
  3. Long-press the first message: `app.staticTexts["rewind test one"].press(forDuration: 1.0)`.
  4. Tap `app.buttons["Rewind conversation"]` (wait for it, timeout 5), then tap `Rewind conversation`
     again in the confirmation (wait 3 s, tap the last match of `app.buttons.matching(identifier: "Rewind conversation")`
     if there are two, otherwise the one).
  5. Assert the composer's `value` as a String equals `rewind test one` (timeout 5 via a short loop of
     `Thread.sleep(forTimeInterval: 0.5)` up to 10 times).
  6. Tap `app.buttons["Send message"]`; wait for `app.staticTexts["rewind test one"]` (timeout 40).
  7. Tap the composer, `typeText("typed after")`, and assert the composer `value` equals `typed after`
     (same polling loop). This last assertion is the bug.
  Attach a screenshot at the end: `let a = XCTAttachment(screenshot: app.screenshot()); a.lifetime = .keepAlways; add(a)`.

## Proof
`swiftc -parse` on every new `.swift` file and on `ConnectView.swift`. XCTest cannot be compiled here:
re-read every API as a compiler would. Allowed APIs only: `XCUIApplication`, `launch()`, `waitForExistence(timeout:)`,
`textFields`, `secureTextFields`, `textViews`, `buttons`, `staticTexts`, `menuItems`, `tap()`, `typeText(_:)`,
`press(forDuration:)`, `exists`, `value`, `screenshot()`, `XCTAssertTrue/Equal`, `XCTSkip`, `NSPredicate`,
`Thread.sleep`, `XCTAttachment`. If you need anything else, list it in "Found, not fixed" instead.
`bash -n` is not relevant. Commit as `M1: UI test target, connect identifiers, first tests`.

## Final message
What you did, the `swiftc -parse` result per file, every API you were unsure of, and anything you found
but did not fix.
