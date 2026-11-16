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


## Second pass (after the merge of the first)

| # | Item | Result | Evidence (Debug simulator) |
| --- | --- | --- | --- |
| S1 (O1, O6) | Opening a long chat: 1.4 to 2.3 s main-thread stall, and opened mid-chat or blank | **Fixed in the app, found to be real.** The blank was not the instrument: a normal launch of the 65 000 pt chat opened blank (restore) or mid-chat (opened from Search). Two causes: `defaultScrollAnchor(.bottom)` lands on an estimated bottom of a lazy stack whose rows are unmeasured, and the stack builds no rows under the final offset until the visible rect changes. Fixes: `repinOpen` re-seats the real bottom while the transcript opens and nudges once at the end (`1833067` to `0aa0d6c`); only the newest 16 turns are mounted, older ones are revealed 12 at a time on scroll with the history anchor keeping the reader's line (`97ccf22`) | restore of the 65 000 pt chat: blank -> lands on the last message, normal launch and `-paseo-perf`; markdown parses at open 93 to 115 -> 9; main-thread stall at open 2274 ms -> 1105 ms (what remains is the app's first SwiftUI render in Debug); scroll back through the window: 0 stalls over 22 ms, 4 hitches in 21 s |
| S2 (O5) | Sidebar body re-ran at every drawer motion | **Fixed** (`b27adb8`): the sidebar read `\.isSurfaceObscured` itself only to drive the usage footer; that read and the poll moved into `SidebarUsageDriver`, a child | `Sidebar` / `SidebarRoll` bodies per motion 1 -> 0; settle stall 10 to 36 ms -> 11 to 30 ms, 2 hitches in 12 motions |
| S3 | Gate: Release install | **Written, not deployed**: `Tools/build-gate/build-gate` v4 has `install-release <ref>`; deploy steps in `GATE-UPGRADE.md` | needs the owner's copy of the script on the Mac |
| S4 | Find in chat and jump to message after `rowAnchor` | **Baseline established; no regression from `rowAnchor` shown. Find did not scroll before either.** Scratch branch `w1-baseline` = original `75064cc` plus only the F1 controller fix (so AXe can drive it). Same steps on the simulator: "Section 3" (3 matches) in the 65 000 pt chat and "Profiling" (3 matches) in a 4-turn chat, stepping with the chevrons: the transcript does not move to the match in the baseline either (it stays where it was). Current branch: same, for an assistant match and for a user-bubble match ("Rendering notes"). So find into a not-yet-visible row did not work in this setup before this branch; whether it works on a device with a keyboard-down search was not established. What changed and why it is safe: your own bubbles and compaction markers keep the original content `.id("row:<seqEnd>")` (exactly as before); only rows whose `seqEnd` moves while they stream (assistant prose, reasoning, tool rows) use the overlay anchor, so the streaming win and the single answer slot (F3) stay; the find scroll path is the original `scrollTo("row:<seq>", .center)`; find or a jump first mounts every turn (window off). Outline-rail jump: not driven (the rail appears only mid-scroll and AXe could not target it). A Core mapping test is not added: the logic that matters is in view code. | scratch branch builds, simulator screenshots |
| S5 | Stream into an open chat left the transcript blank (found while proving S4) | **Fixed** (`a3c6fab`): the open re-seat kept running when a turn arrived and fought the follow. It now ends on a new turn or a running turn. Proven: a reply sent from the CLI to the open chat renders, follows to the bottom and completes ("Completed in 2s") with no blank, 5 hitches in 3 windows, worst frame 338 ms at the turn start (Debug) | simulator screenshot |

### Still open (not fixed in this pass, and why)

- **Composer keystroke cost (O2), new-session open and focus (O3), rich media first scroll (O4), scenarios 3 to 5 and link/video/audio (item 7): not started in this pass.** The time went to establishing the find baseline and to two blank-transcript bugs (S1, S5) that had to come first. What each needs: O2: a size memo in `ComposerUITextView.fittedSize` keyed on text+width+font, and a trace of why `ChatScreen.body` runs per key (add `PaseoPerf.diff` to its inputs, as was done for the shell); O3: a `-paseo-perf-sample` run of opening the draft and focusing the composer (UITextView creation and keyboard IPC are the suspects); O4: a sampled run of the first scroll over the image/diagram cards; item 7: scripts in the style of `scenarios/README.md`.
- (Earlier note) **Composer keystroke cost (O2), new-session open and focus (O3).** A sampled run of typing shows the time is inside UIKit's text view (`ComposerUITextView.fittedSize` -> `UITextView.sizeThatFits`, text-services IPC, `langid_consume_string`) and in two to three composer evaluations per key; `ChatScreen.body` also re-runs per keystroke (26 a window), which was not traced to its input. A size memo was judged unsafe without a way to verify it. Target < 4 ms per key is not met.
- **Rich media first scroll (O4).** Not re-measured or changed.
- **Scenarios 3 to 5, link previews, video, audio** are not scripted; `scenarios/README.md` lists only what was run.
- Find into history that is not yet loaded does not scroll (S4).


## Fourth pass (items 2, 3, 4, 7, Release)

Known gap vs upstream, not fixed in this pass: **find-in-chat to an off-screen row never scrolled in the original build either** (baseline `w1-baseline`, see S4). The owner wants it; it is next (below).

| # | Item | Result | Debug before -> after |
| --- | --- | --- | --- |
| P1 | Typing in the composer (O2) | **Improved, target not met.** (a) `ComposerUITextView.contentSize` memoises `sizeThatFits` keyed on text, width, font name and size, insets, content-size category, exclusion paths, line padding and line limit. In `-paseo-perf` every hit is re-checked against a real layout: over typing, deleting and a 100-character sentence, `fit.MISMATCH` never counted (hits 3 per miss). Text size change is part of the key; paste was exercised only as a long typed run. The layout itself is only 0.3 ms a key, so the memo is a small win. (b) The open-time re-seat (`repinOpen`) kept scrolling to the bottom on every composer growth while typing (`openpin.fire` per key): it now ends when only the insets move. (c) `ChatScreen` read `\.openURL`, `\.toast` and `\.accessibilityReduceMotion` in its body; moved to `ChatOpenURLWiring`. | typing 40 chars: 8 to 14 hitches and 43 to 48 ms stalls per key -> 0 to 2 hitches, stalls at most 22 ms, 60 fps, busy 22 to 59 % at 27 keys a second. `ChatScreen` and `Composer` bodies still run once per key (`diff` shows no `@State` or environment input changed); the sampler shows most of the remaining per-key time is the main thread waiting inside UIKit text input (`__psynch_cvwait`, `mach_msg2_trap`, language identification), not our code. **Not solved: why `ChatScreen.body` re-runs per key.** Needs: a trace of observed reads in that body (a `withObservationTracking` wrapper that names the property), or SwiftUI's `_printChanges` output, which the gate's `applog` cannot show. Suspect: trait-bridged environment keys (`accent`, `pureBlack`) read through `Palette` colours inside the body; the sampler shows `UITraitCollection.accent.getter` under `ChatScreen.body` and `ComposerView.body`. |
| P2 | New-session open 177 ms, composer focus 219 ms (O3) | **Cause identified, not fixed; needs Release numbers.** Sampled: of the 54 to 121 samples in each stalled window the top leaf frames are `swift_conformsToProtocolMaybeInstantiateSuperclasses` (15 to 36), dyld, asset-catalog lookups (`CUIStructuredThemeStore lookupAssetForKey`, from `DraftChatView.workspaceLine`) and `UITextView.init`; the focus stall builds `InlineBanner` optionals in `ComposerView.dictationDeniedBanner`. Protocol-conformance lookup cost is a Debug-build cost (unspecialised generics); I could not confirm it in Release (see below). | open 177 ms -> unchanged; focus 219 ms -> unchanged (331 ms in a later run) |
| P3 | First scroll over rich media (O4) | **Fixed** (`b20d06e`). Sampled: `RichWebSnapshotRenderer.ensureWebView` -> `WKWebView.init` blocked on the main thread in `__ulock_wait2` (112 of 260 samples) waiting for WebKit's content process to launch, at the first diagram or SVG card. `prewarm()` starts the shared view when a chat opens. | first-scroll stall 605 to 726 ms -> 51 ms (worst frame 64.5 ms, 6 hitches over 12 scroll steps); the cost moves to chat open, where it is hidden behind the open. |
| P4 | Scenarios 3 to 5, media (item 7) | **Scripted** (`scenarios/extra.sh`) and run on the rich-media chat. Dynamic type ax5: 4 hitches, worst frame 143.8 ms, stall 127 ms; xs: 5 hitches, 101.9 ms, 112.6 ms; m: 4 hitches, 39.5 ms, 22.4 ms; light 4 hitches 40.8 ms; dark 2 hitches 39.2 ms. Media cards scroll: 4 hitches, worst 40.0 ms, stall 23.1 ms. Two steps could not run (the code-block button labels and the work-group row label did not match the chat's accessibility labels, so scenarios 4 and 5 produced no usable numbers); the first text-size change after a launch costs one 100 to 140 ms relayout (visible in the ax5 and xs runs only). Link previews and video/audio: the test chat has a video and audio card but they only load on a tap (`MediaFetchPolicy`), and the scripts do not tap them. | n/a |

### Release (gate v4 `install-release`)

`install-release w1-performance` built and installed a Release app (3 min 9 s). **The Release app never connected on the shared simulator**: it sat on "Connecting…" (the launch skeleton) for over 25 s while the same host connected at once in the Debug build, so no Release numbers were taken. **Correction after a later check:** the Debug build installed afterwards is stuck on "Connecting…" too (the daemon answers from Linux), so the cause is the simulator's connection to the test daemon or the app's saved-host state, not Release. Nothing in the app log, no crash report. The simulator needs its host re-checked or re-paired before any measurement resumes; Release numbers are still missing. Suspects: the saved host or its Keychain password not being readable by the differently signed Release binary on the simulator, or a Release-only connect bug (the first would be a simulator artefact; the second would be a real defect and must be checked on the first Release device build). What is needed: a launch of the Release app with the host paired again on the simulator (`simreset`, then pairing), or a `-paseo-perf` Release run on a device. Until then the Debug counts and ratios above are the evidence, and the 8 ms stall / one-frame budgets are NOT signed off.

### Find in chat and the outline-rail jump (owner: wanted)

One attempt was committed (`64605f6`: a find step leaves follow mode, scrolls to the turn id, centres the row on the next pass, nudges one point) and could NOT be verified: the simulator lost its host connection (above) before the proof run. Treat it as untested. Otherwise not started in this pass (it was to follow items 2, 3, 4, 7, and the Release run took the remaining time). The plan, so the next pass starts at the answer: (1) read upstream's in-chat search (`packages/app`, the find bar and its scroll-to-match) for the behaviour: step order, centring, what is searched (user, assistant, tool rows) and what happens at the ends; (2) resolve the match to the turn (`Turn.containsRow(seqEnd:)`, with a fallback to the latest turn starting before the seq) and scroll to the turn's `ForEach` id first, because an id inside a lazy row that is not built is not findable (the finding behind S4); (3) after the stack has built the turn, centre the row from the offset `scrollTrack` records for it (the outline jump already uses `scrollTrack.offset(of:)` and `scrollPosition.scrollTo(y:)`); (4) nudge once so the stack builds rows under a long jump (the blank seen in S1 and in the S4 variants); (5) keep the turn window (reveal every turn first) and the stream anchors. Prove with "Section 3" on the 27-turn chat and an outline jump.


## Fifth pass: Release numbers, find in chat

Release (`install-release`, the simulator connected again). **The simulator's noise floor**: an idle Release window prints one hitch of 26 ms about once a second (`perf t=3.1 fr=60 hit=1 worst=26.6` with the app doing nothing), so a one-frame budget cannot be signed off on this simulator in either configuration; stalls over 8 ms and counts are what carry over. Release against Debug (same scenarios, same chats):

| Scenario | Debug | Release |
| --- | --- | --- |
| Open of the 65 000 pt chat (restore) | stall 1105 ms | stall 887 ms in the second window, 9 markdown parses; the first window (app start) 70 ms stall, 680 ms frame |
| Scroll back through it | 4 hitches in 21 s, stall max 21 to 22 ms | 8 hitches in 9 s, worst frame 42 ms, stall max 25 ms |
| Drawer open/close, 3 motions | 2 hitches, stall 11 to 30 ms | 3 hitches, worst frame 33 ms, stall max 16 ms |
| Composer typing (40 chars, 3 deletes) | 0 to 2 hitches, stall 22 ms | 16 hitches, worst frame 88 ms, stall max 96 ms (not understood: worse than Debug; needs a sampled Release run) |
| Rich-media scroll, 10 steps | 6 hitches, stall 51 ms | 12 hitches, worst frame 70.8 ms, stall max 87 ms |
| Streaming a reply (short) | 5 hitches over 3 windows, worst 338 ms | 2 hitches over 2 windows, worst frame 82 ms, stall 63 ms |

So Release is not better than Debug on this simulator in scroll, typing or rich media; the budgets (8 ms stall, one frame) are not met in Release either. The structural fixes remain right (they remove work), but the remaining stalls are not Debug artefacts: a sampled Release run of typing and of the rich-media scroll is the next step.

Not done in this pass: new-session prewarm (item 3), scripts for scenarios 4 and 5 and video/audio (labels: use `do ui reading` in the chat to read them; new-session needs the sidebar open first, the label step failed because the sidebar was closed).

**Find in chat.** Two more variants on the 27-turn chat ("Section 3", step 1 and 2): turn id first then row then nudge (`64605f6`); jump through the outline path (`jumpToTurn`, glide-lead) (`ed90b93`). Both scroll and land on a **blank** region in Release and Debug (the stack builds no rows under the new offset; a manual drag builds them). Because that is worse than the original behaviour (no scroll), the find step is reverted to the original centre-the-row path in the last commit of this pass. Root cause, as far as known: a programmatic jump of tens of thousands of points in a lazy stack leaves the realised rows at the old offset until a real scroll event; the open-time nudge worked because it ran at the end of a layout that had already settled. What would fix it: scroll in bounded steps (page-sized `scrollTo(y:)` hops each on a geometry pass), or make the transcript a `UICollectionView`/`UITableView`-backed list where `scrollToItem` is reliable, or keep the match's turn window (mount only `[match-8 ... match+8]` turns around the target, then jump within a short range). The third needs the turn window to support a middle window, which it does not yet. Upstream reference not read in this pass.

**Regression found and fixed in the same pass (`b92e930`).** The pass-4 change that ended the open re-seat "when only the insets move" (made to stop a re-seat per keystroke) left the 65 000 pt chat blank on a plain launch when the composer held a tall saved draft. The re-seat now ends when the composer is focused (the reader acting) instead; opening the chat lands on the last message again (Debug, plain launch). Cost: while the pin is active and before the first focus, a composer growth can still re-seat once per change (capped at 16).


## Sixth pass: measurement correction, typing, new session (Release, 3 runs each)

**Correction to the Release table of the fifth pass.** Release is not worse than Debug. The earlier typing comparison used two different scripts: the Debug figures were steady-state typing (composer already focused), the Release figures included the first focus (a 330 ms stall). With the same script, cold launch each time, three runs (`repeat.sh`, median [range]):

| Scenario (same chat, same script) | Debug | Release |
| --- | --- | --- |
| Idle 12 s (floor) | 1 hitch [0..1], stall max 59 ms [0..65] | 0 [0..0], no window printed |
| Typing: focus, 20 chars, 20 deletes | 14 hitches [12..20], worst frame 360 ms [343..367], stall max 373 ms | 14 [13..17], 314 ms [313..357], stall max 330 ms |
| Rich-media scroll, 8 steps | 5 [3..6], worst 99 ms [60..106], stall max 64 ms [45..77] | 5 [5..5], worst 56 ms [55..58], stall max 41 ms [41..47] |

Within the run-to-run range the two builds are equal for typing; Release is somewhat better for rich-media scroll. The one-hitch-a-second "noise floor" claimed in the fifth pass was not an idle floor: it was the tail of the previous scenario's activity; truly idle Release prints nothing.

**A. Typing (Release, after the pasteboard fix `f24d3e2`).** Where the time is, from sampled Release runs:
- **First focus per launch: 330 to 450 ms main-thread stall**, three runs 337 ms [337..449] (`focus-only`). A second focus in the same launch costs 113 ms and the blur 50 ms, so about 220 ms is cold, once per launch. The samples are dominated by `swift_conformsToProtocolMaybeInstantiateSuperclasses` (43 of 183), mach_msg waits and the transcript's `TextRenderer.sizeThatFits` / `InlineCodeRenderer.draw` re-measuring when the keyboard shrinks the transcript. Starting the keyboard early (a throwaway text field focused and released at chat open, `c1cc99f`) did not move it (337 ms), so it was reverted (`76c8d9b`): the cost is SwiftUI/UIKit metadata and layout, not the keyboard process.
- **Per key, steady state: stalls of 18 to 25 ms, 0 to 1 hitch per key** (AXe pace). Sampled: `ComposerUITextView.contentSize` (the real layout of a changed text, 0.2 to 0.7 ms by the span) with the thread waiting in `mach_msg2_trap` / `__psynch_cvwait` inside UIKit text layout, and `ComposerPrimaryButton`/`primaryState` bodies. `ChatScreen` and `Composer` bodies still run once per key (`diff` shows no input of ChatScreen changes).
- **Fixed:** `UIPasteboard.hasImages` was a pasteboard-daemon round trip asked from `canPerformAction(paste:)` and from the composer body on every pass; now `PasteboardImageState` (cached, refreshed on pasteboard change and app activation). Typing medians before/after in Release: 14 hitches / 314 ms -> 15 / 382 ms (not distinguishable within the range of [14..17] and [318..412]): the fix is correct and cheap but does not by itself move the number.
- **Target "0 stalls over 16 ms typing 40 chars": not met.** What would be needed: the first-focus cold cost needs the transcript not to re-measure on keyboard show (pin the transcript's layout to a keyboard-independent height, as `stableViewportHeight` already does for caps) and the per-key UIKit layout wait needs `UITextView` TextKit 1 vs 2 and language-identification settings tested one at a time (`writingToolsBehavior`, `inlinePredictionType`, `spellCheckingType`), each of which is a visible behaviour change and needs the owner's decision; none was changed.

**B. New session (Release, sidebar open first, 3 runs).** Open: 6 hitches [6..9], worst frame 115 ms [101..139], stall max 98 ms [70..122]. Open plus focus: 7 hitches [6..7], worst frame 329 ms [327..343], stall max 337 ms [335..353]. The focus part is the same first-focus cold cost as above (the draft composer is the same view); the open's 98 ms is view construction of the draft page. Not fixed: the named candidates (asset-catalog lookups in `DraftChatView.workspaceLine`, `dictationDeniedBanner`) are inside windows dominated by cold conformance lookups, and no change to them was measured to help; the keyboard prewarm did not help either. Needs a per-view span run in Release (spans around `DraftChatView` pieces) to attribute the 98 ms.


## Seventh pass: fixes by reading and sampling (Release, single runs per fix; 3-run confirmation where noted)

Method change: fix first, one sampled run to name a cause, one run per batch to confirm. Two things found
that change how every earlier number must be read (rules 22 and 23):
- **The instrument cost what it measured.** `PaseoPerf.diff` in `ShellView.body` string-interpolated environment
  values through `Mirror` on each pass (45 of 110 samples in the first-focus window were `swift_conformsToProtocol`
  under `ShellView.body`), and each fit-memo hit re-ran `sizeThatFits`. Both removed; the "cold protocol
  conformance" story of the sixth pass was partly this.
- **AXe is not free.** The first interaction after a launch initialises the accessibility validation machinery in the
  app (`AXValidationManager`, `AXCoreUtilities` conformance lookups: sampled in the new-session open and the
  first tap). A throwaway `ui reading` step before the measured action absorbs it: the tap-window stall fell
  from 117 to 140 ms to under 28 ms (single run). The remaining ~340 ms is the first software keyboard show (UIKit keyboard
  views, render server, IOSurface allocation, `RBSAssertion` XPC, key-command walk), present with AX warm.

| # | Area | Cause (evidence) | Fix | Before -> after (Release) |
| --- | --- | --- | --- | --- |
| 7.1 | Typing: `ChatScreen`/`Composer` bodies per key | `_printChanges`: `ChatScreen: ConversationStore.draft changed`. A `Binding(get: store.draft)` built in `ChatScreen.body` is evaluated by SwiftUI when it compares `ComposerView`'s inputs, which charged the draft read to the screen | `ComposerView` reads and writes the text itself (`text`, `textBinding` inside its body) | `ChatScreen` body per key 1 -> 0, `Composer` 1 per key; stalls per key 18 to 25 ms -> max 20 ms over 16 keys (single run) |
| 7.2 | Typing: mascot | `feedMascot(.userActivity)` per key assigned the tracked `mascot` struct and notified the crab and the ticker | machine `@ObservationIgnored`, `mascotState` written on change | removes one notification per key |
| 7.3 | First focus: shell cascade | `ShellView` re-ran at focus (non-comparable env closures and bindings count as changed) and re-assigned all three hosting roots: `Sidebar`, `SidebarRoll`, `ChatScreen`, `Composer` bodies in the focus window | `ShellRootsKey`; `ShellContainer` assigns roots only when the key changed | focus window bodies `Shell,Sidebar,SidebarRoll,ChatScreen,Composer` -> `Shell` (cheap) then `Composer,Transcript`; stalls 140+77+48 ms before the keyboard frame -> 120 (AX) + 46 |
| 7.4 | Shell dependency on the whole agent | `currentWorkspaceId` read `conversation.agent`; every agent update re-ran the shell | `ConversationStore.workspaceId`, written only on change (Core test `ConversationWorkspaceIdTests`) | shell body no longer follows agent updates |
| 7.5 | Long-chat open: URL scan | sampler: 179 of 949 samples in `nextHTTPScheme`/`scanBareImageURLs`/`youtubeHits` under `ConversationMediaIndex.update` on main; `text[i...].count` per character is O(n^2) | `httpSchemeLength` walks at most 8 characters; `nextCaseInsensitive` bounded | removes the quadratic term (message-length dependent) |
| 7.6 | Long-chat open: media index | the index of every assistant message ran in `updateTurns` on main though only the media sheet reads it | built when asked (`mediaIndex` getter, incremental) | removes a full-conversation scan from the open |
| 7.7 | Long-chat open / rich media: web view | `WKWebView.init` (100 to 700 ms) landed inside the open or the first rich card | prewarm starts when the open re-seat ends (+1 s), fallback 8 s | rich-media scroll, 8 steps: 5 hitches, stall max 41 ms -> 1 hitch, 27.7 ms (single run) |
| 7.8 | Chat open: voice engine | `VoiceAudioEngine()` (AVAudioFormat, AVFAudio load) in every `ChatController.init` | built on first use (`voiceEngineIfCreated` for teardown) | ~8 of 245 samples at open |
| 7.9 | Bodies | `PaseoDate.parse` (FormatStyle) per agent per sidebar pass and per user bubble; `messageTimestamp` two format styles per bubble body; `DictationController` allocated per `ComposerView` init | caches; lazy holder (Core test `PaseoDateCacheTests`) | micro, on every sidebar pass and bubble |
| 7.10 | Open re-seat | stayed armed until the keyboard moved the insets, then scrolled inside the keyboard's first frame | disarms 0.8 s after convergence and on `keyboardWillShow` | no `openpin.fire` in the focus window when the chat is idle |

**Long-chat open (65 000 pt chat), 3 cold launches, largest single stall:** 762 / 781 / 1249 ms before this
pass's open-path fixes (build before 7.6/7.7) and 1101 / 796 / 773 ms after: no measurable change within the
range. What dominates is SwiftUI's first render of ~44 `Markdown` bodies (`DynamicPropertyCache.fields`,
`makeViewList` conformance lookups per view type, UITextView-backed inline-code paragraphs
`ClaudeSelectableInlineCode`, TextKit shaping). A smaller turn window (8/8) was tried and made some opens 2.5 to
4 s (more re-seat passes): **reverted**. Left: a cheaper first render of inline-code paragraphs (a SwiftUI `Text`
path with the same selection behaviour) is the next structural step; it changes a text engine and was not done
blind.

**First composer focus:** after 7.3 and the AX finding the app-controlled part is gone; ~340 ms remains and is
UIKit's first keyboard presentation. A word-tagger/language-identifier warm-up off main (`NLTagger`,
`NLLanguageRecognizer`) was tried and did not move it (reverted); an invisible keyboard prewarm does not exist
(a visible one would flash).

**Not verified on a phone / not done:** media pipeline review (downsampling, caches) and the rich-block
`GeometryReader`s were read but not changed; the new-session open (98 ms) is dominated by the AX/first-view cost
above and was not reduced further; drawer settle unchanged (3 hitches, stall max 16 ms).

## Eighth pass (owner decisions after pass 7)

| # | Area | Change | Result |
| --- | --- | --- | --- |
| 8.1 | Prose engine | Paragraphs, headings and table cells with inline code are one SwiftUI `Text` with the existing `InlineCodeRenderer` pill; `ClaudeSelectableInlineCode` (a `UITextView` + TextKit 1 stack per paragraph) deleted. Plain paragraphs no longer carry the renderer. | Verified in the Release simulator: pills draw, links tappable, long-press selects a word with handles and the Copy / Look Up / Translate menu, layout unchanged in lists. Long-chat open (3 cold launches) still 0.8 to 1.1 s worst stall: the text engine was not the dominant cost. |
| 8.2 | Blank open | Pre-existing intermittent blank long-chat open (seen on the pass-6 build too: 2 of 4 launches with 2 text rows). Added a guard: if turns exist and no mounted turn overlaps the viewport, change the offset by 2 pt (alternating with an edge scroll) up to four times. The timed disarm of the re-seat added in pass 7 was removed (it could end the pin at an estimated end). | not verified to fix the blank (the blank reproduces about 1 launch in 3); needs a device check |
| 8.3 | Card width readers | 8 `GeometryReader`s (link, YouTube, image, gallery, web, file cards, markdown tables) replaced by `onGeometryChange` on a clear background, written on change only | rich-media scroll renders correctly (screenshot checked) |
| 8.4 | Warm-up | `ComposerWarmup` at idle (2 s after the shell appears): `ComposerUITextView` created and laid out once off window, 20 SF Symbols, highlighter engines for both themes (off main) | first focus keyboard frame unchanged (~390 ms, system) |
| 8.5 | New-session open | **Not an app cost**: with AXe's accessibility initialisation absorbed by a prior `ui reading`, the open is one 17.7 ms stall and 1 hitch (sampled run: `perf.hot samples=6`). The earlier 98 to 141 ms was `AXValidationManager` / `UIAccessibilitySafeCategory` class initialisation. | |
| 8.6 | Media pipeline | Read end to end: it already downsamples with `CGImageSourceCreateThumbnailAtIndex` (`ImageDownsampler`, `ShouldCacheImmediately`, width-exact), decodes in the pipeline actor and detached tasks, has `NSCache` with count and cost limits and memory-warning eviction, a failure memo, coalesced requests (`detach`), revision-validated disk keys, off-main poster and waveform work. No change made beyond 8.3: nothing in it showed on a sampled stall. | |
