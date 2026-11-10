# R9: prose, code highlighting, rich content

Branch: `r9-prose`, from `foundation` after R6 is merged. Read `docs/tickets/_R-common.md`, PLAN §RC8 and
§RC9, and audit B (H, #10, N11).

**Owns:**
- `Conversation/Prose/` (incl. `Rich/`);
- `DesignSystem/ClaudeLoader.swift`;
- `Conversation/Turn/ClaudeStatusLine.swift`;
- `Conversation/Mascot/ClaudeCrabView.swift`;
- `Workspace/WorkspaceFileViewer.swift`, the highlighter call only.

## 1. Code highlighting off the main actor

- **Actor:** `ClaudeCodeHighlighter` becomes an `actor CodeHighlighter`. It owns the JavaScriptCore context,
  created lazily on the actor.
  - API: `func highlight(_ code: String, language: String?, theme: Theme) async -> AttributedString?`.
  - Results are cached in an LRU (`ProseCache`, already in the codebase from P5-B) keyed by
    `(theme, language, code.hashValue, code.utf16.count)`. **Don't key by the full source string.**
- **Code block view:**
  - first paint: plain `.code` mono text in `ink`;
  - `.task(id: key)` requests the highlight and swaps it in. Same font and metrics, so there is no
    layout jump.
  - Skip highlighting while the block is still streaming: the last code block of a running turn
    highlights once its fence closes or the turn ends. Use the existing "is streaming" signal that
    the reveal uses.
- **The file viewer** uses the same actor.

## 2. Rich web content: few live `WKWebView`s

- **SVG** (`RichSVGCard` or equivalent):
  - render once in a shared offscreen `WKWebView` (one per app, created lazily, `.nonPersistent`
    data store, JavaScript **off**);
  - use `takeSnapshot(with:)` at display width × scale;
  - cache the `UIImage` by content hash (`NSCache`);
  - the chat shows the image, fit to width, with an aspect ratio from the snapshot;
  - tap opens a sheet (`SheetScaffold`, `.large`) with the live `SandboxedHTMLView` for zooming;
  - serialize the snapshots (one at a time) through an actor queue.
- **HTML / `visualize`:**
  - the live `SandboxedHTMLView` stays mounted only while the card is on screen (`onAppear` /
    `onDisappear` plus a 1-screen margin via `onScrollVisibilityChange` (iOS 18) if available,
    else `onAppear`);
  - off screen it shows its last snapshot, taken just before teardown;
  - at most 2 live web views exist at once (a static counter); a third card shows its snapshot or a
    placeholder until a slot frees.
- **Height reporter:**
  - throttle the `MutationObserver` posts to one per animation frame
    (`requestAnimationFrame` debounce in the injected script);
  - write `contentHeight` only when it changed by more than 0.5 pt;
  - build the document HTML string once per content (`@State` / memo), not in `body`.
- **Images:** `RichLocalImage` and `ProseMarkdownImage` load through `chatActions.loadImage` (R6: off
  main, cached). `RichRemoteImage` keeps `AsyncImage` but adds a downsampling transaction if trivial.
  Otherwise leave it.
- **`LPLinkView`:** fetch metadata only on appear; keep the existing cache. Verify it exists, and add
  an `NSCache` keyed by URL if it doesn't.

## 3. Continuous animations

- `ClaudeLoader`'s `TimelineView(.animation)` becomes
  `TimelineView(.animation(minimumInterval: 1/30, paused: isPaused))`.
  `isPaused = reduceMotion || isSurfaceObscured || scenePhase != .active`.
- Apply the same `paused` rule to the status line's sweep timeline and the crab's timeline (P6-F made
  them 30 Hz; add the obscured and scene-phase pause).

## 4. Prose leftovers

- `FilePathLinks.protectedRanges`: confirm its regexes are `static let` (P5-B may have done it). If
  not, make them static.
- The inline code plate: R2 implemented it; verify it renders in links and plain text. Fix only if
  it's broken.

## Proof

- `swiftc -parse`.
- Style lint 0.
- **Unsure:** `WKWebView.takeSnapshot(with:)` with an offscreen view (it must be in a window: attach
  the shared web view to a 1×1 hidden `UIWindow`, or check the documented requirement),
  `onScrollVisibilityChange`, and `TimelineView` `paused`.
