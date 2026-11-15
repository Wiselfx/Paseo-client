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

12. **Every perf change carries its before and after** (the commit subject, `W1: <what> (<before> ->
    <after>)`, and a line in `W1-findings.md`). A fix without a number is a guess.

## Keeping it true

- Run `Tools/style-lint/style-lint.sh` and read the `perf-*` lines; new hits need a reason or a fix.
- Re-run the scenarios in `docs/perf/scenarios/` after any change to transcript, composer, sidebar, shell or
  prose code, and compare the `VERDICT` lines with `W1-findings.md`.
- Core: `StreamingIdentityTests` pins row and segment identity under streaming.
