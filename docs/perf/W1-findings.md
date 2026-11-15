# W1 findings: the accounting

Branch `w1-performance`. Instrument: `Packages/PaseoUI/Sources/PaseoUI/DesignSystem/Perf/`. Method and budgets:
`PERFORMANCE-RULES.md`. Scenarios: `scenarios/`. Every number below is from the gate's Debug simulator
(see "What I could not verify"): trust counts and ratios, not milliseconds on a phone. "Before" is the
foundation head as built at the start (or the first instrumented build), "after" is the commit named.

## Fixed

| # | Where | How found | Cause | Fix commit | Before -> after |
| --- | --- | --- | --- | --- | --- |
| F1 | Whole app, idle | first `-paseo-perf` run: `busy=100 %`, `fr=9..13`, `body=Shell:40..190` with no input changing (`diff.shell.none`) | `ChatScreen.init` evaluated `State(initialValue: ChatController(...))` on every shell body pass; the controller's init registers observers, starts a path monitor and writes into the checkout store, and its reads became dependencies of the shell: a feedback loop (82 to 112 controllers built and thrown away a second) | `d4a71cb` build the chat controller once, lazily | idle: frames 100 ms (10 fps) at 100 % main thread -> 60 fps, no window printed (silent idle), Shell/Sidebar/Composer bodies 20 to 190 a second -> 0 |
| F2 | Streaming reply, every token | `stream.sh`: `md.appear` 145 and `md.disappear` 138 a window with `Markdown` bodies 100 to 250 a second | `.id("row:\(row.seqEnd)")` on the streaming prose: `seqEnd` moves with every delta, so the whole message subtree (every markdown piece, text view, code block, highlight task) was destroyed and rebuilt per token; also `ClaudeMarkdownView` was never equal (closures in the init, a theme whose colour values are re-created per call), so even without the id nothing could be skipped | `298cb66` anchors are overlays; `d20e8c3`/`6a5d058` equatable pieces and theme | 1500-word reply, Debug sim: 113 hitches, 805 dropped frames, worst frame 766 ms, stall max 498 ms, busy 70 % (19 windows) -> 33 hitches, 63 dropped, worst 110 ms, stall max 84 ms, busy 28 % (14 windows); `Markdown` bodies per update 11 to 25 -> about 1 |
| F3 | End of a streamed reply | same run: at completion `md.appear` 33 / `md.disappear` 30 and a 345 ms stall | the streaming prose lived inside the work stack and, when the turn completed, moved to the answer slot after the header: a different place in the tree, so every piece was rebuilt exactly when the user looks at it | `628fc0c` one `answerProse` slot for both states | completion stall 345 ms -> 138 ms (remaining cost is the footer, summary and code highlight) |
| F4 | End of a streamed reply | `md.neq.stream:125` at completion | `isStreaming` passed to every piece flipped for all of them at once; and the reveal wrote four `@State` values per delta, so each delta split the whole message three times (`rich.pieces` 39 calls a second) | `1358201` only the tail piece streams; `PieceMemo` | all pieces re-evaluated at completion -> the tail only; splits per delta 3 -> 1 |
| F5 | Drawer first and last frame (sidebar, panel) | `sidebar-edge` scenario: `Sidebar`, `SidebarRoll`, `Composer` bodies at each motion with a 52 to 156 ms stall | `ShellContainer.applyRoots` re-assigned every hosting controller's `rootView` with new environment values at the start and end of each motion | `9b271ee` `SurfaceFlags` observable per surface | settle stall 52 to 156 ms -> 10 to 36 ms; composer body per motion 1 -> 0 (sidebar bodies still run once, see open O5) |
| F6 | Composer body | spans: `composer.camera` 1.0 to 2.3 ms | `UIImagePickerController.isSourceTypeAvailable(.camera)` asked on every composer pass | `9b271ee` `static let` | 1 to 2.3 ms a pass -> once |

Core tests: `StreamingIdentityTests` (new; passes with the full Core run: 1131 + 221 + 166 tests). No existing test changed.

## Open (found, measured, not fixed)

| # | Where | Evidence | Why it stays |
| --- | --- | --- | --- |
| O1 | Opening a long chat | 1.4 to 1.6 s main-thread stall at mount in Debug: 102 `md.parse` misses, 105 `Markdown` bodies, `rich.pieces` 20 ms for one row, `code.highlight` 88 ms (`perf-run` first window after launch) | needs parse and split off the main actor (or in slices) with reserved space; a design change beyond a timing fix. Rule 11. |
| O2 | Typing in the composer | `new-session`: 41 `Composer` bodies in one window of fast typing, stalls of 43 to 48 ms per keystroke (Debug) | the composer body is one monolith (`text` drives `trimmedText`, slash and mention queries, menus); needs splitting into a narrow text-reading child. Not attempted for budget. |
| O3 | New session page | opening the draft: 177 ms stall; focusing the composer (keyboard): 219 ms (Debug) | not diagnosed (sampler off to keep timing honest); `DictationController()` is created in a `@State` default per composer init (lint `perf-state-default-object`). |
| O4 | Rich media, first appearance while scrolling | `rich-media-scroll`: one 250 ms frame and a 311 ms stall when the first image / diagram cards come on screen; content height moves 6300 -> 9100 pt while scrolling up | cards reserve space, but the first mount (image decode, web view) runs on scroll; needs a sampled run. |
| O5 | Drawer settle | after F5 the sidebar still re-evaluates once per motion (10 to 36 ms Debug); the first open after launch measured 238 ms | what the sidebar reads that flips (`StatusDot` readers, `scenePhase`) was not isolated. |
| O6 | Instrument interplay | with `-paseo-perf` (and `-paseo-perf-sample`) a long chat (over about 15 000 pt) opened blank until the first drag; the same chat opened normally without the flag. A re-seat of the end marker did not help and was reverted. | probably a timing-sensitive lazy-stack layout that the instrument's overhead exposes, so a slow phone may show it too; **needs an eyeball on a device**. Cause not found. |

## What I could not verify

- Release performance: the gate builds Debug only (`GATE-UPGRADE.md`). The structural fixes (F1 to F6) remove
  work and view churn, so they help in Release too, but "no hitch over one frame" is not signed off.
- A phone: no device. Display link on the simulator is 60 Hz; ProMotion (120 Hz, 8.3 ms budget) is untested.
- Hard flings: `scroll up|down` has a fixed speed; scenario 1 is slow to medium scroll only.
- Scenarios 3 to 5 (dynamic type extremes, code block horizontal scroll and collapse, think blocks) were not
  scripted end to end; scenario 6 covers the sidebar by edge swipe and tap but not the keyboard-up and
  mid-drag-cancel variants; link previews, video and audio (scenario 7) were not exercised.
- The "Perf long" chat (60 000 pt) was only usable without the instrument (O6).

## What the owner should feel on a phone

- The app idles: no warmth, no battery drain from a main thread that used to spin at 100 %; every tap lands
  at once because nothing is queued behind the loop.
- A reply streaming in stays at full frame rate; code blocks no longer flash plain and re-highlight each
  token, text no longer re-wraps from scratch, and the end of the reply does not hiccup.
- Opening and closing the sidebar and the panel: the last frame of the settle is quieter. If it still ticks,
  it is O5.
- Check by eye: opening a very long chat (does it ever show blank, O6), typing in the composer (O2), the first
  scroll over images and diagrams (O4).
