# Performance rules (R-8)

Read with `AGENTS.md` (R-1 to R-7). These rules come from measurements (`docs/perf/W1-findings.md`),
not taste: each one names the number that motivated it, the pattern to use here, and the check that
keeps it true. `Tools/style-lint/style-lint.sh` greps for the patterns it can (`perf-*` rules).

## How to measure (do this before and after every change that touches a hot path)

- Launch with `-paseo-perf` (off by default, costs one branch per call when off). It prints one
  aggregated line per second of activity through `os.Logger` (`perf t=… fr= hit= drop= worst= p50/p95/p99=
  scroll= busy= stall8= smax= stalls=… body=… n=… sp=…`). `-paseo-perf-sample` adds a sampling profiler
  for stalls (`perf.hot` lines); it suspends the main thread a thousand times a second while it is busy,
  so use it to find a cause, never to take a number.
- `docs/perf/scenarios/perf-run.sh <name> "<gate do steps>"` drives the simulator through the gate and prints
  the windows plus a `VERDICT` line (hitches, dropped frames, worst frame, stalls over 8 ms, busy share).
  `stream.sh` runs the streaming scenario. Scenario descriptions: `docs/perf/scenarios/README.md`.
- Instruments in code (`DesignSystem/Perf/`): `PaseoPerf.body("Name")` as the first line of a body,
  `PaseoPerf.measure("name") { … }` / `begin`+`end` (also an `os_signpost` interval), `PaseoPerf.count`,
  `PaseoPerf.mark`, `PaseoPerf.diff` (which input of a body changed, reaches the gate log) and `PerfProbe`.
- The gate builds Debug. Absolute numbers are inflated several times and the simulator is not a phone:
  trust counts (bodies per update, views created per update, writes per frame), ratios and main-thread
  stalls, never the simulator's headroom.

## Measurement rule (read every number against this)

A single run is an anecdote. For any number you report or fix against: run the scenario **at least 3
times per configuration** with `docs/perf/scenarios/repeat.sh` (cold launch each time, same chat, same
script, 8 s settle before the window opens so the app-start window is excluded, same window length),
report the **median and the range**, and measure the **idle floor on the same build** (`repeat.sh idle
"wait 12"`) and read every other number against it. A difference counts only if it is larger than the
run-to-run range. Compare Debug and Release with the same script and the same chat: two different
scripts (one including the keyboard appearing, one not) once made Release look 8 times worse than Debug.
Say so when the script sends steps faster than the app can take them (AXe types about 2 to 3 keys a
second, so each key lands in its own window).

## Budgets

| Scenario | Budget |
| --- | --- |
| Idle after launch | no window printed (zero hitches, zero stalls over 8 ms, `busy` under 5 %); any `body=` counter above 0 at idle is a bug |
| 1 Chat scroll (slow, fling, reverse) | 0 hitches over one frame, no stall over 8 ms |
| 2 Streaming (a reply growing, nothing else) | per delta: at most one `Markdown` body per changed piece, no view created for a settled piece (`md.appear` only for new pieces), `busy` under 35 % in the Debug simulator |
| 6 Sidebar and panel | 0 hitches over one frame, no stall over 8 ms at the first or last frame of a motion |
| 7 Rich media | 0 hitches over one frame while scrolling over cards, no layout shift |
| Any user action | no main-thread stall over 8 ms from an action the user did not ask for |

The numbers in the findings file are the Debug simulator's. Where a scenario still misses its budget the
finding says so and names the cause; a change that makes a budgeted scenario worse does not merge.

## Rules

1. **Idle is silent.** Nothing runs when nothing changed. Motive: the idle app held the main thread at
   100 % with 9 to 13 fps (`Shell` body 40 to 190 a second, 82 to 112 chat controllers built and thrown
   away a second). Check: `perf-run.sh idle "wait 10"` prints no window. A body that runs at idle is a loop.

2. **No side effects in `init`, no object creation in a property default.** A view struct is rebuilt every
   time its parent evaluates, and `State(initialValue: Thing())` / `@State var x = Thing()` run the
   initialiser each time (SwiftUI keeps the first). Anything that registers observers, starts a task or
   monitor, or writes into a store must not live there. Pattern: hold a lazy builder
   (`ChatControllerHolder`: the closure is cheap, the object is built once, on first use, inside an
   observation scope of its own) or build in the parent's action (`select`), never in `body`.
   Lint: `perf-eager-state-object`, `perf-state-default-object` (reports `DictationController()` in the
   composer and `VoiceAudioEngine()` in Diagnostics to review).

3. **View identity follows stable values only.** `.id(x)` on content with an `x` that changes destroys
   the subtree. A streaming row's `seqEnd` moves with every delta, so `.id("row:\(seqEnd)")` rebuilt every
   markdown piece, text view and code block of the message on every token (145 creates a second).
   Pattern: scroll and find anchors are `rowAnchor(_:)`, an overlay of the row's own size that carries the
   changing id; the content keeps a stable identity (`row.id` is `seq:<seqStart>`). Core test:
   `StreamingIdentityTests`. Lint: `perf-id-seqEnd`, `perf-id-count`.

4. **Repeated items are `Equatable` and skip `body`.** A closure in an initialiser is never equal, so a
   non-`Equatable` item re-runs every time its parent does. Pattern: `Equatable` conformance that compares
   the inputs that decide layout and ignores closures to stable objects (`ClaudeMarkdownView`,
   `ClaudeSelectableInlineCode`, `TurnRow`), applied with `.equatable()`. Compare values by what they
   draw, not by every field: a theme holds colour values the builder re-creates on each call, so a
   synthesised `==` was never true and the whole optimisation was dead (measure `body=` after adding it).

5. **Do not feed one changing fact to every item.** `isStreaming` was passed to every piece, so the turn
   ending changed all of them at once (40 views, 345 ms). Pass each item what is true for it
   (`isStreaming && ref.isTailMarkdown`), and keep an item in one place in the tree across its states: the
   streaming answer and the completed answer are one slot (`answerProse`), so completion rebuilds nothing.

6. **No synchronous system call in a body.** `UIImagePickerController.isSourceTypeAvailable` cost 1 to
   2 ms per composer pass. Ask once (`static let`) or cache in a store. Pasteboard, Keychain, file system,
   `UserDefaults` reads with I/O, date formatters and regex construction belong outside `body`.
   Lint: `perf-body-ipc`.

7. **Chrome state flips through observable flags, never by re-assigning roots.** The drawer container
   re-assigned each hosting controller's `rootView` with new environment values at the first and last frame
   of every motion, re-running the sidebar, composer and chat chrome (52 to 156 ms stall at the settle).
   Pattern: `SurfaceFlags` (one `@Observable` object per surface, read through `\.isSurfaceObscured` /
   `\.isPanelVisible`); only readers re-evaluate, and only when the value changed (write only on change).

8. **Memoise derived structures where they are used.** A body that runs three times per delta
   (the reveal writes four `@State` values) must not split the whole message three times. Pattern: a small
   class held in `@State` remembering the last input and result (`PieceMemo`), or a `ProseCache`.

9. **Per-frame and per-token work is O(1) in the content.** Scroll callbacks do arithmetic and write state
   only at boundaries; stream deltas change the tail only. A number that grows with message length is
   a bug even when it is small today (`rich.pieces` grows 1 to 3 ms in Debug over a 1500-word reply).

10. **Rows are measured before they are visible.** Reserve size, never change a row's height after it
    appears, no `GeometryReader` per row, no web view started by scrolling (see `_V-common.md`).

11. **Heavy first appearance is a finding, not a fact of life.** Opening a long chat built about a hundred
    markdown pieces in one pass (1.4 to 1.6 s in Debug). Parse and split off the main actor or in chunks and
    show reserved space; do not accept a stall because it happens once.

12. **A lazy stack gets only what is near the viewport.** Handing it a whole long conversation made it
    estimate the content, land on an estimated bottom, build about a hundred pieces in one pass and leave
    the stack without rows under the final offset (a blank screen on a normal launch). Mount a window
    (`windowSize`, `windowStep`), reveal more on demand with the history anchor, and when the stack opens
    at the end, re-seat the real bottom (`repinOpen`). Find and jumps need every turn: reveal first.

13. **A view reads a flag only if it draws it.** The sidebar read the drawer flag to start a poll, so every
    drawer motion re-ran the directory body; the read belongs in a child (`SidebarUsageDriver`).

14. **The open re-seat ends when the reader acts, never on a layout heuristic.** It ends on composer focus,
    a finger, a send or a find/jump. "Only the insets moved" ended it too early and left a long chat blank
    with a tall saved draft.

15. **No programmatic jump of tens of thousands of points in a lazy stack.** The stack builds no rows
    under an offset it was moved to in one step until a real scroll event (a find step landed blank).
    Lead most of the way and glide the last stretch, scroll in bounded hops, or mount a window around the
    target first.

16. **No IPC in a hot callback.** `UIPasteboard.hasImages` is a round trip to the pasteboard daemon and was
    asked from `canPerformAction(paste:)` (called repeatedly while editing) and from the composer body:
    cache it (`PasteboardImageState`) and refresh on `UIPasteboard.changedNotification`.

17. **Every perf change carries its before and after** (the commit subject, `W1: <what> (<before> ->
    <after>)`, and a line in `W1-findings.md`). A fix without a number is a guess.

18. **A parent never builds a binding whose getter reads a store.** SwiftUI evaluates a `Binding` when it
    compares a child's inputs, and the read is charged to the parent's body. A binding reading the draft,
    created in `ChatScreen.body`, made the draft a dependency of the whole screen: `ChatScreen`, `Composer`
    and the bars re-ran on every keystroke. Pattern: the child takes the store and reads/writes it itself
    (`ComposerView.text`, `textBinding` built inside its own body). Lint: `perf-binding-store-get`.

19. **A big body does not read a re-created closure just to forward it.** Environment values that are
    closures (`notificationPermissionAction`) and bindings count as changed whenever the environment is
    re-delivered, so `ShellView.body` ran at the first composer focus and re-assigned all three hosting
    roots (sidebar, chat, panel). Pattern: gate the downstream work on a value key that holds only what the
    roots are built from (`ShellRootsKey`, compared in `ShellContainer.updateUIViewController`).

20. **Do not assign a tracked struct on every event.** `controller.mascot.handle(.userActivity)` ran per
    keystroke and notified every reader of `mascot` though the crab did not change. Pattern: keep the
    machine `@ObservationIgnored`, publish the one value views draw (`mascotState`) only when it changes.

21. **Scans over message text are O(n), and what only a sheet needs is built when the sheet asks.**
    `nextHTTPScheme` took `text[i...].count` per character (O(n^2) per message) and ran for every message of
    a conversation on main in `updateTurns` while a chat opened (179 of 949 samples). Never call `count` on
    a suffix inside a scan loop; build derived indexes lazily (`ConversationStore.mediaIndex`). Parsing the
    same ISO stamp again and again belongs in a cache (`PaseoDate.parse`), so does a per-bubble format
    (`PaseoFormat.messageTimestamp`). Lint: `perf-suffix-count`.

22. **The instrument must not cost what it measures.** The shell's `diff` interpolated environment values
    through `Mirror` on every pass (45 of 110 samples in the first-focus window were
    `swift_conformsToProtocol` under `ShellView.body`), and every fit-memo hit re-ran `sizeThatFits`. Before
    believing a "cold conformance lookup" stack, check that its caller is not `PaseoPerf`. Probes are removed
    when the cause is found.

23. **Read simulator numbers against what drives it.** AXe works through the accessibility server: the first
    interaction after a launch initialises `AXValidationManager` / `AXCoreUtilities` in the app (protocol
    conformance lookups for every UIKit class: about 110 to 140 ms at the first tap and again at the first
    new view). Absorb it with a throwaway `ui reading` step before the measured action; a phone with
    VoiceOver off pays none of it. The first software keyboard show (about 340 ms in the Release simulator:
    UIKit's keyboard views, the render server, the key-command walk) is the system's, and no invisible
    prewarm was found for it.

## Sweep rules (W3, code read, not measured on a device)

24. **Read the lists in a child, not in the page that owns the chrome.** The sidebar body read `session.agents` and
    the workspace list, so every agent or workspace update re-evaluated the header, navigation, footer and the sheet
    and dialog modifiers with it. The directory is `SidebarDirectoryHost`, a child that reads them; rows are
    `SidebarWorkspaceRow` (`Equatable` on a value model, one `SidebarRowActions` object per pass).
25. **An `@Observable` setter always notifies, even for an equal value.** A store that receives repeated snapshots
    (workspace pushes, terminal and script lists, checkout status, usage phase) writes only when the value differs
    (`WorkspaceDirectory`, `TerminalsStore.setTerminals/setScripts`, `CheckoutStore`, `HostUsageStore`), and sorts
    into a copy, assigning only when the order changed (an in-place `sort` notifies even when nothing moved).
26. **A page that owns text-field state re-evaluates per keystroke.** Anything it sorts or filters is remembered per
    input (`FileListMemo`; `ScrubMemo` for the diagnostics bundle); regexes are compiled once in a `static let`.
27. **Do not build a lookup once per row.** `Set(session.agents.map(\.id))` was a computed property read by every
    schedule row; build it once per pass and only when a row needs it. Lint: `perf-agents-set-in-view`,
    `perf-groups-in-view`, `perf-regex-compile`.

## Keeping it true

- Run `Tools/style-lint/style-lint.sh` and read the `perf-*` lines; new hits need a reason or a fix.
- Re-run the scenarios in `docs/perf/scenarios/` after any change to transcript, composer, sidebar, shell or
  prose code, and compare the `VERDICT` lines with `W1-findings.md`.
- Core: `StreamingIdentityTests` pins row and segment identity under streaming.
