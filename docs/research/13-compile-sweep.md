# 13 · Compile sweep (pre-Xcode)

Branch `p2-compile-sweep`, audited against `foundation` at `ca71579` (range `dbad49b..foundation`).
Scope: the **120 existing** Swift files under `Packages/PaseoUI` and `App/` that changed in that
range. The range names 157 paths; 37 are files deleted before `foundation`, so they cannot fail a
build and were dropped. The two changed `PaseoUITests` files are included in the parse sweep.

No Apple SDK is installed here. This is a source-level audit, not a compiler run: every changed
file was parsed with `swiftc -parse`, Apple signatures were checked against Apple's documentation
JSON, and every PaseoKit/PaseoStore symbol was checked against its declaration and access level.
Anything needing the real SDK is called out below as medium/low, not claimed as clean.

## High-confidence errors, fixed

### 1. Public `View` sheets had internal `body` — `PairingFlow.swift`

- `PairingFlow.swift:22` `AddHostMethodsSheet`, `:104` `PairScanSheet`, `:321`
  `PastePairingSheet`, `:412` `HostConfirmationPairingSheet`, `:507`
  `PairingPasswordSheet`: each is a `public struct ...: View`, but each `body` was declared
  `var body: some View` (internal).
- **Why:** a public type's witness for a public protocol requirement must be public. Verified with
  `swiftc`: a public `struct` conforming to a public protocol with an internal witness reports
  “method must be declared public because it matches a requirement in public protocol”.
- **Fix:** all five are now `public var body: some View`.
- Confidence: **high**.

### 2. `Chart` fed non-`Identifiable` data — `ClaudeUsageReportsSheet.swift:113,130`

- `Chart(overview.days)` and `Chart(overview.models.prefix(6))` used the single-argument data
  initializer. `UsageOverview.Day` and `UsageOverview.Model` are `Sendable, Hashable` only
  (`PaseoStore/UsageOverview.swift:30-38`).
- **Why:** Charts' data initializer is
  `init<Data, C>(_ data: Data, content:) where Data.Element: Identifiable`. The non-identifiable
  form is `init(_:id:content:)`.
- **Fix:** `Chart(overview.days, id: \.date)` and
  `Chart(overview.models.prefix(6), id: \.model)`.
- Confidence: **high**.

### 3. `WelcomeView` was internal but constructed from `App` — `WelcomeView.swift:9`

- `RootView.swift:76` constructs `WelcomeView`, but the type (and its `init`/`body`) was internal
  in the `PaseoUI` module.
- **Why:** `App` is a separate module; internal declarations are not visible there.
- **Fix:** type, `init` and `body` are now public. The generic `DirectForm` and private state stay
  private to the implementation.
- Confidence: **high**.

### 4. `QRScannerView` exposed an internal coordinator — `PairingFlow.swift:214,248,252`

- `public struct QRScannerView` declared `public func makeCoordinator() -> Coordinator`, but
  `Coordinator` is an internal nested class (`:252`), and the same public `View` was only used by
  `PairScanSheet`.
- **Why:** a public method cannot return an internal type; the compiler reports “method cannot be
  declared public because its result uses an internal type”.
- **Fix:** `QRScannerView` and its representable methods are internal; its public API was never
  needed outside the module.
- Confidence: **high**.

### 5. `.draggable` received an optional — `WorkspaceFilesView.swift:421`

- `row(...)` applied `.draggable(entry.isDirectory ? nil : relative(entry))`. `draggable` requires
  `T: Transferable`; `String?` does not conform to `Transferable`.
- **Why:** Apple exposes `draggable<T>(_ payload: @autoclosure @escaping () -> T) where T:
  Transferable`; there is no optional overload. A conditional `nil` needs a conditional modifier.
- **Fix:** the row content is a helper; directories get the plain row, files get
  `.draggable(relative(entry))`.
- Confidence: **high**.

## Medium / low, left unchanged

These compile risks depend on SDK attributes that cannot be tested here. None has a definite
source-level mismatch, so none was changed.

- `ClaudeRichBlocks.swift:234` — `fetchMetadata` is a `static async` returning non-Sendable
  `LPLinkMetadata`, and its `withCheckedThrowingContinuation` body runs inside
  `LPMetadataProvider.startFetchingMetadata`'s completion handler. If the enclosing `View` is not
  inferred `@MainActor`, Swift 6 can reject returning that value across an isolation boundary.
  Confidence: **medium**; needs an Xcode build.
- `NotificationCoordinator.swift:91` — `Task { try? await UNUserNotificationCenter.current().add(request) }`
  captures `UNNotificationRequest`. The method is main-actor isolated, so this is probably fine,
  but the SDK's `Sendable` annotation decides. Confidence: **low**.
- `RootView.swift:90` — the `@Sendable` environment closure has a single-expression `Task` body
  whose result is discarded. This is a warning shape, not a hard error, but strict mode should be
  checked. Confidence: **low**.
- `SandboxedHTMLView.swift:101` — async `WKNavigationDelegate` form
  `webView(_:decidePolicyFor:) async -> WKNavigationActionPolicy` is used. It exists in current
  SDKs; confirm it is present for the iOS 26 SDK in Xcode. Confidence: **low**.
- `VoiceAudioEngine.swift:324-330, 405-412` — the thinking-tone loop uses a `Task` inherited from
  the main actor plus `PlaybackCompletion` (unchecked `Sendable`). No source-level violation was
  found; the actor-inheritance/continuation race deserves an Xcode concurrency pass.
  Confidence: **low**.

## Verified clean

Apple signatures checked directly against Apple documentation JSON:

- `DataScannerViewController` init labels, `.ScanningUnavailable` delegate method, `didAdd` and
  `didTapOn` (`PairingFlow.swift:230-310`) — correct.
- `PasteButton(payloadType:onPaste:)` — correct.
- `UIPasteboard.setItems(_:options:)` with `.localOnly` and `.expirationDate`
  (`PairDevicePage.swift:232`) — correct.
- `AVAudioApplication.requestRecordPermission() async -> Bool` (`VoiceAudioEngine.swift:74`) —
  correct.
- `.glassEffect(_:in:)` and the `Shape.circle`/`Shape.capsule` static shapes — correct.
- `.fileExporter(isPresented:document:contentType:defaultFilename:onCompletion:)` — correct.
- `Chart(_:id:content:)` — correct after the fix.

SwiftTerm 1.99.3 API used by `PaseoTerminalView.swift` was checked against the tagged source:
`TerminalView(frame:font:)`, `feed(byteArray:)`, `changeScrollback(_:)`, `resetToInitialState()`,
`sendKey*`, and every implemented `TerminalViewDelegate` requirement match.

All other changed files — **clean** in the checked categories:

- `App/Sources/` except the low/medium items above: clean.
- `Packages/PaseoUI/Sources/PaseoUI/Chat/` except `PairingFlow.swift`,
  `ClaudeUsageReportsSheet.swift`: clean.
- `Packages/PaseoUI/Sources/PaseoUI/Conversation/`, `Rich/`, `Settings/`, `Sidebar/`,
  `Schedules/`, `Workspace/`, top-level `PaseoUI/*.swift`: clean.
- `Packages/PaseoUITests/{MediaTests,ScheduleWordsTests}.swift`: clean.

The API audit was rerun after the edits: the remaining findings are all baseline false positives —
`Content.blur`, `Content.simultaneousGesture`, `Option.AllCases`/`Option.RawValue`, the
`AVAudioPCMBuffer`/`AVAudioConverter` members the index does not model (the index treats those
Apple classes as opaque), and two `DaemonEndpoint(url:credential:)` label reports that ignore the
`relay:` default. No finding names new code.

## Verification

- `swiftc -parse` on all 120 existing changed files: clean.
- `git diff --check`: clean.
- `cd Packages/PaseoCore && swift build --build-tests`: **passes**, 203/206 steps, no warnings.
- `swift test`: **134 tests in 14 suites passed**.
- Full `xcodebuild` still required for `PaseoUI`/`App`; that is the reason for the medium/low list.
