# G-round: rich native UI — the deliverable

One worker, one branch (`g-rich-ui`, from `foundation`), delivered in **phases**. At the end of every
phase you stop, report, and wait: the lead reviews the diff, compiles it on the Mac gate, merges it,
and tells you to continue. Never start the next phase on your own.

**Source plan:** `docs/research/14-rich-ui-plan-full.md` (sections cited as §n). This file is the
contract; the plan is the reference for detail. **Where they disagree, this file wins** — it is
the plan made coherent with what has shipped since (the H-round) and with the user's decisions.

Read first, in full: `AGENTS.md`, `ARCHITECTURE.md`, `docs/tickets/_H-common.md`, this file, then
the plan §1, §4, §5, §9–§13. Skim `docs/UX-SPEC.md`.

---

## 0. Mission-critical objectives (above every feature in this file)

The user lives in this app on an iPhone. The bar is Apple-level: it must feel instant, smooth and
correct. **A feature that works but costs smoothness is a failed feature.** If you must choose
between shipping a card and keeping the transcript perfect, keep the transcript perfect and say
what you cut.

1. **Nothing per frame, per keystroke, per scroll tick, per audio buffer.** O(1) work only, and
   SwiftUI state is written only when a boundary flips. Accumulate in non-observed reference boxes
   and publish edges (pattern: `TranscriptScrollTrack`, `TranscriptChromeState`).
2. **Nothing jumps.** A card's box is reserved before any byte arrives (§1.3). Content the user is
   looking at never moves unless they moved it. The single allowed size change per card is the
   placeholder → true ratio settle, once, animated with `Motion.disclosure`, and never again for
   that URL/path (cache the shape). Failures keep the reserved box (see H5's `boxedFailure`).
3. **Narrow observation (R-1).** A view reads only what it draws. Derived lists (galleries, change
   summaries, media index, usage series) live in PaseoStore, maintained **incrementally per turn**,
   never computed in `body`. Rows and cards are `Equatable` values with **no closures in their
   initializers** (R-2); actions come from one environment object.
4. **Main actor stays free.** Image/video/PDF/ANSI decode, file reads, JSON of large payloads,
   `AVAudioSession`, `setVoiceProcessingEnabled`: off main, one hop back with a finished value.
5. **Web views are scarce.** At most **2 live `WKWebView`s** in the transcript at any time, created
   only on appear, snapshot when off-screen (§1.6.1). Mermaid and SVG render offscreen to an image
   through the shared queue; never one live view per diagram.
6. **Finger-tracked motion is UIKit (R-3)**: the viewer's drag-to-dismiss and paging are a UIKit
   container with `UIPanGestureRecognizer` handing off to `UISpringTimingParameters(dampingRatio:
   1)`, velocity-matched. SwiftUI hosts content and learns open/closed.
7. **Tokens only (R-4).** `Palette`, `Typography` via `.paseo(_:)`, `Space`, `Radius`, `Motion`
   (`resolved(reduceMotion:)`), `Haptics`, `Metrics`. New numbers go into `DesignSystem/` with a
   one-line reason. `Tools/style-lint/style-lint.sh` clean on your files.
8. **Accessibility.** Each card is one element (kind + title + meta), menu items as custom actions,
   44 pt hit areas, `minHeight` on text containers, Reduce Motion everywhere, VoiceOver page
   announcements in the viewer.
9. **Network etiquette (§12).** No surprise downloads on cellular, Low Data Mode or the relay.
10. **Privacy.** The repo is public: no real hostnames, tokens, agent titles in code or fixtures.
    Lock Screen surfaces redact by default.

**"A proper fix, not a hack"** (from `_H-common.md`, applies to every line): root cause first with
`file:line`; no delays, magic offsets, `DispatchQueue.main.async` to let layout settle, forced
`.id()` rebuilds or thresholds nudged until a symptom hides. Design the behaviour, then build it.
Every state: light, dark, pure black, Reduce Motion, VoiceOver, largest Dynamic Type, keyboard
up, empty and long conversations, slow/failed/offline network, the relay.

## 1. Hard rules

- **Never touch Claude agents.** Never send to, prompt, create or probe any agent whose provider is
  `claude`, by any route. For live fixtures create your own `pi` + `opencode-go/beam-free` agent
  and archive it afterwards. Read what a `paseo-probe` subcommand does before running it.
- Upstream reference: `/home/paseo/dev/paseo-upstream-ref` (read-only, v0.16.0-beta.1). **Never
  open `/home/paseo/dev/claude-style-lab`.**
- No new dependencies (Swift packages). The Mermaid runtime is a bundled resource file, not a
  dependency (decision D2).
- **Tests:** never edit, delete, skip or weaken an existing test — with **one** authorised
  exception: `Packages/PaseoCore/Tests/PaseoStoreTests/Rich/RichContentDetectorTests.swift:704-706`
  (mermaid fences produce nothing) changes to assert detection (decision D2). Write the new
  behaviour in a new test file too.
- No force unwraps, no `fatalError`, Swift 6 strict concurrency with no warnings.
- New `App/` source files or targets: regenerate the project (`cd App && USER=paseo
  /usr/local/bin/xcodegen generate`) and commit the pbxproj; check its diff touches only what you
  added.
- Commit per ticket: `G<n>: <what the user will notice>`. Never push, merge or rebase.

## 2. Decisions (made by the lead on the user's delegation, 2026-11-11)

| # | Question | Decision |
|---|---|---|
| D1 | Signing (free vs paid team) | Unknown. **Build nothing that needs an App Group into the default app.** Core snapshot logic ships; extension targets are added but **not embedded** in the app (Phase E). App Intents and Spotlight live in the main app (no extension) and ship. |
| D2 | Bundle Mermaid (~3.5 MB) | **Yes.** Pin a version, record its SHA-256 and MIT licence next to it, bundle offline. One existing test change authorised (above). |
| D3 | Live Activity | **Deferred.** It would lie without push or a proven background window; the G17 spike needs a device. Not in this deliverable. |
| D4 | Allow/Deny on notifications | **Yes, off by default**, simple requests only, device must be unlocked (`.authenticationRequired`). |
| D5 | Share extension | **Deferred** (after widgets ship). |
| D6 | Paid account + Expo push | **No** (costs money; not decided by the lead). |
| D7 | New copy (§15) | **Approved**, with the rule: where upstream `en.ts` has an equivalent, use upstream's text verbatim instead. List every string you add in each phase report (new vs upstream + line). |
| D8 | Permission card's optimistic "Allowed: …" line | **Show the line only after the daemon confirms** (`agent_permission_resolved` / the request leaving `pendingPermissions`). Keep the card's busy state; on the 10 s timeout (HB fix) the card re-enables with an honest inline note. |

## 3. What already exists — build on it, don't duplicate it

- **`RemoteImageLoader`** (`Conversation/Prose/Rich/RemoteImageLoader.swift`, H5): shared session
  + `URLCache`, UA, in-flight de-dupe, decoded `NSCache`, shape cache, failure memo, SVG routing,
  `data:`. **`ImageDownsampler`** (`DesignSystem/ImageDownsampler.swift`): width-exact ImageIO
  downsample. **G2 evolves these into the `MediaPipeline`; there must never be two loaders.**
- `RichRemoteImage` / `RichImageViewer` / `InlineProseImageViewer` (H5) — reserved box, boxed
  failure, inline-image tap. `ClaudeMediaViewer` (`ClaudeMediaView.swift`) and the private
  `ZoomableImageView` (`WorkspaceFileViewer.swift:1076`) — G3 replaces them with one UIKit viewer.
- `RichCard` (`ClaudeRichBlocks.swift:12`), `RichWebCard` slot logic (`:1126`),
  `RichSnapshotQueue` (`RichWebContent.swift:126`, the shared offscreen web view), `RichMapCard`,
  `LinkPreviewView` (LPLinkView), `RichPathChip`, `YouTubeRichCard` (now loader-backed).
- The transcript's runway/header/follow machinery (H2) — cards must not disturb it.

---

## Phase A — Foundations (stop and report after A)

**G1. Card family** — plan §1.1, §1.2, §1.4, §1.5, §5 G1.
- `DesignSystem/Components/PaseoCard.swift`: two layouts only (media card, row card), header slot,
  accessory slot, press style (`scaleEffect(0.98)` + `Motion.feedback`), a context-menu helper
  (items in §1.2's order, `Haptics.selection()` on appear), one accessibility element.
- `RichActions`: one `@MainActor` environment object (open viewer, open file, open diff, open
  artifact, share, copy, save to Photos, add to chat). Cards take values only.
- Migrate every rich block (link, map, YouTube, web/viz, SVG, image, path chip host) to
  `PaseoCard`; delete `RichCard`. Stable identity `(turnId, block range start, kind)` so streaming
  never re-runs a card's entrance.
- Accept: `grep` shows no remaining `RichCard`; no closure parameters on card initialisers; the
  only visual change is unified radius/border; walk light/dark/pure black at 320/393/430 pt.

**G2. Media pipeline** — §4.1, §1.3, §1.6, §12; *evolve* `RemoteImageLoader`.
- Rename/extend into `MediaPipeline` (actor) + `MediaMetadataCache`; keep every H5 behaviour.
- Add: incremental size probe (`CGImageSourceCreateIncremental` fed by a streaming data task) that
  publishes the true size **before** the download finishes; daemon-file source
  (`FileExplorerRequest(mode: .file, acceptBinary: true, maxBytes: 64 MB)`) cached on disk in
  `Caches/daemon-media/<sha256(host+cwd+path+revision)>`, LRU 500 MB; memory-warning purge.
- `MediaFetchPolicy` (§12): a pure enum + decision function in **PaseoStore** with the full §12
  table as a parameterised test; an `NWPathMonitor` wrapper in PaseoKit publishing
  constrained/expensive/interface as a small `@Observable`; relay vs direct from the host
  session. Cards read only the derived policy. The tap-to-download state uses the reserved box,
  shows the size when known, a progress ring in place.
- `RichLocalImage` and the workspace image path go through the pipeline too (one way pixels enter).
- Accept: no `AsyncImage`, no `UIImage(data:)` on main (grep proof); policy tests green; walk "20
  screenshots, scroll, scroll back" (no fade on second visit, no position jump).

**G3. Full-screen viewer** — §4.6, R-3.
- One UIKit viewer (`Conversation/Prose/Media/MediaViewer*.swift`): `UIPageViewController` of
  zooming `UIScrollView` pages; zoom transition from the exact thumbnail
  (`matchedTransitionSource` + `.navigationTransition(.zoom)`), Reduce Motion → `Motion.fade`;
  pinch (1×…max(4, pixel/points)), double-tap 2.5× at point, single tap toggles chrome,
  **drag-down dismiss tracked in UIKit and released into a velocity-matched critically damped
  spring**; full-resolution decode on open off main, neighbours ±1 preloaded.
- Chrome: close, "n of m", Share, Copy, Save to Photos (add `NSPhotoLibraryAddUsageDescription` to
  `App/project.yml`, approved copy), Show in Files, Live Text (`ImageAnalysisInteraction`, analysis
  off main, button only when text is found), Add to chat (existing attachment path).
- Replace `ClaudeMediaViewer`, `RichImageViewer`, `InlineProseImageViewer` and the Files panel's
  `ZoomableImageView` with it. GIF/APNG animate here only.
- Accept: walk enter/exit from each source, interrupted drag, VoiceOver "Image 2 of 5, alt".

## Phase B — The artifacts coding agents actually make (report after G4+G5, then after the rest)

Order: **G4 → G5** (report) → **G6 → G8 → G9 → G7 → G10 → G11 → G12 → G13** (report).

- **G4 Mermaid** (§2 C9, §5 G4, D2): detector case for closed ```` ```mermaid ```` fences only (a
  streaming fence stays code); extract `WebViewSlotPool` (≤ 2 live views) from `RichWebCard`;
  render offscreen → snapshot cache keyed by (source, width, scheme); card tap → full-screen live
  view; syntax error shows source + error. DEBUG log counter of live web views. PARITY row.
- **G5 Artifact page** (§2 C8, §4.8): title, source toggle, Share as `.html`, Reload, the existing
  bridges, "Preview" on html/svg code fences (never auto-render), Files panel "Open full screen"
  for `.html`. Security posture unchanged (offline chat artifacts, CSP, non-persistent store).
- **G6 Turn changes card** (C11): `TurnChangeSummary` in PaseoStore, incremental with the tail
  rebuild (test: incremental == full rebuild); one Equatable row card at turn end; tap → diff.
- **G8 Terminal output + test chip** (C12): `AnsiText` (SGR) and `TestSummaryParser` in
  PaseoStore with captured, scrubbed fixtures; tail-truncated coloured output, exit pill, chip;
  ANSI colours as `Palette` tokens that read in light/dark/pure black; 1 MB parse < 50 ms on Linux.
- **G9 Links v2 + GitHub + PR & checks** (C6, C7, C13): own-rendered link card from
  `LPMetadataProvider` (drop `LinkPreviewView`), OG slot reserved 1.91:1 from first layout;
  `GitHubURL` parser in Core; same-repo items via forge search; PR card bound to the checkout's PR
  status (live). Other repos degrade to the link card.
- **G7 Galleries** (C2): adjacent-image grouping in PaseoStore (tests); grid card; tap opens G3 at
  that index with zoom from that tile.
- **G10 File cards + Quick Look** (C10): standalone path lines; lazy size; PDF thumbnail ≤ 5 MB;
  `QLPreviewController` for non-text kinds after download-on-tap; text/code still open in the
  workspace viewer; the 64 MB cap row.
- **G11 Video + audio** (C3, C4): detector `.localMedia` + remote media (tests); poster card →
  inline AVKit on tap (never autoplay); audio row with waveform (computed off main);
  `MediaPlaybackCoordinator` (one player at a time, scroll-away pauses, generalising YouTube's);
  §12 download policy; `AVAudioSession` off main and coordinated with voice/dictation's
  `MicrophoneSessionOwner` so playback never steals or breaks the mic session.
- **G12 Media sheet** (C15): `ConversationMediaIndex` in PaseoStore (incremental, tests), the
  sheet, jump to source turn; entry in the title menu (H2's `ChatHeader` menu).
- **G13 Context + cost charts** (C16): per-turn usage series (live turns only; chart starts where
  data starts, no fake zeros) in the context sheet; follow the dataviz rules; `accessibilityChartDescriptor`.

## Phase C — Card refinements (§9) (report after C)

- **§9.1 wide tables** (horizontal scroll inside the block, trailing fade, pinned label column
  rule, tap header → full screen; widths memoised in the document model).
- **§9.2 todo/plan card** (one card per turn, replaced in place, collapses when done; reducer in
  Core with tests).
- **§9.3 permission previews** + **D8** (confirmed-only resolution line; suggestions never
  pre-selected).
- **§9.4 subagent cards** (row card matched by `toolCallId`, pushed read-only timeline page).
- **§9.5 images in user bubbles** (this device only, keyed by `clientMessageId`, thumbnail disk
  cache LRU 50 MB; nothing shown when unknown).

## Phase D — System surfaces in the main app (report after D)

- **G16 (main-app part)**: `AgentEntity` + `IndexedEntity`, `OpenAgentIntent`, `NewAgentIntent`
  (focus composer, never autosend), the attention query, App Shortcuts with approved names,
  Spotlight indexing (titles only; respects a "show agent names" setting defaulting **off** for
  Lock Screen surfaces, but Spotlight is in-app search — index titles, document why). Routing via
  the existing deep-link path (`paseo://`). Controls need a widget extension → Phase E.
- **G19 notification Allow/Deny** (D4): a Settings toggle (off by default); actions only on simple
  requests; `.authenticationRequired`; background reconnect sends the response; failure posts an
  "Open" notification. Mapping logic in PaseoStore with tests.
- **§11 notification thumbnails**: local notifications only, from the pipeline cache only (never
  download for a notification), redacted when the Lock Screen setting is off.

## Phase E — Extensions, built but not shipped (report after E)

- **G14 Core part**: `GlanceSnapshot` (Codable, tests), the throttled writer (≤ 1 write / 10 s +
  attention changes + backgrounding) — writing to the App Group container **only if available at
  runtime**, otherwise a no-op.
- **G15 widgets + Controls**: a `PaseoWidgets` extension target in `App/project.yml` with its own
  scheme, **not embedded in the app target** (D1), so the default IPA is unchanged. Small, medium
  and accessory families (§3.1), titles `.privacySensitive()`, redaction setting, deep links,
  "Updated" ticking without reloads; the two Controls (§3.3).
- Report exactly what the user must do to turn it on (signing, the one-line embed).

## Deferred (do not build; listed so nobody does)

Live Activity (D3), G17 spike (device-only), Share extension (D5), Expo push and widget
self-refresh (D6, G22). **G23**: write `docs/research/15-upstream-asks.md` — the daemon-side asks
(Range downloads, >64 MB reads, per-turn usage in history, attachments echoed on `user_message`,
APNs live-activity/widget push types), each with the client feature it unblocks. No code.

---

## 4. Verification (no Xcode, no device here)

- `swiftc -parse` every touched UI file. PaseoCore: `. ~/.local/share/swiftly/env.sh && cd
  Packages/PaseoCore && swift build --build-tests && swift test` green. style-lint clean.
- **Every pure piece goes to PaseoStore/PaseoKit with tests first**, before its UI.
- `swiftc -parse` does not type-check. Known traps the lead keeps catching: Double/CGFloat optional
  bridging; touching `UITextView.layoutManager` (forces TextKit 1 — never do it); new `App/` files
  missing from the pbxproj; `UIView` subclasses missing `init?(coder:)`; `CADisplayLink` without
  `preferredFrameRateRange`; SwiftUI `Canvas`/`TimelineView` not redrawing. Avoid them.
- Replace device-only acceptance (Instruments, 120 Hz feel) with: a DEBUG counter/log line that
  proves it (live web views, decodes on main = 0, writes per second), plus a call-by-call walk of
  the hot path in your report.

## 5. Phase report (your final message at each stop)

1. Per ticket: what the user will see; the design; key `file:line`s; tests added; the hot-path
   statement (what runs per scroll frame / keystroke now).
2. Grep proofs requested in the acceptance lines.
3. Every new user-facing string: new vs upstream (`en.ts` line).
4. Every Apple API you weren't 100 % sure of (name + signature).
5. "Also fixed" (real problems you found and fixed in files you touched, root cause each) and
   "Found, not fixed" (with reason).
6. What you cut or deferred inside the phase, and why (mission-critical wins over scope).
7. "Unsure — needs the device".
