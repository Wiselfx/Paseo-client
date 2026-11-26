---
name: sim-harness
description: Measure app behaviour in an iOS simulator on CI instead of guessing. Use for scroll jank, jumps, layout drift, animation hitches, layout under Dynamic Type, rotation or the keyboard, slow screens, or to check that a fix works before the user tests it on device. Covers building a harness test, running it on CI (no local toolchain) and comparing reports.
---

# Simulator harness flow

There is no local Swift toolchain. The CI macOS runner is the simulator. A harness is a package
test that hosts real production views, drives them step by step, and writes numbers to a report.
It never fails on the bug, only when the harness itself breaks. The user judges the result on
device; the harness tells you what to fix and proves the fix before they look.

Reference implementation (copy it): `Packages/PaseoUI/Tests/PaseoUITests/TranscriptHarnessTests.swift`
plus `Harness/*.swift`. It found the chat scroll jank (cells taking their safe area) in one run,
after three guessed fixes had failed.

## 1. Build the harness

- **Real code, composed like the app.** Host the production view in a `UIHostingController` in a
  393x852 `UIWindow` (`UIWindow(windowScene:)` when a scene is connected, else `frame:`). Wrap it the
  way the real screen does: e.g. `HarnessChatScreen` adds the bars as SwiftUI `safeAreaInset`s like
  `ChatScreen`. Never emulate with a mechanism production doesn't use (UIKit
  `additionalSafeAreaInsets` gave misleading numbers).
- **Data through production code.** A fake `DaemonClient` (`SyntheticDaemonClient`) answers the
  request with a page decoded by the production response type; the real stores build the model.
  Seed content with `SplitMix64` so every run is identical. No network content: CI has none.
- **Drive in small steps.** Change one thing per step (a scroll offset, a size, a trait), then
  `try await Task.sleep(for: .milliseconds(16))` so SwiftUI, Task hops and layout run. Call the same
  delegate methods UIKit would (begin/end dragging). State plainly what you can't simulate
  (isTracking, real velocity, touches).
- **Measure what the user sees.** Screen-space positions of drawn content (the layer tree; `drawHierarchy`
  draws nothing for SwiftUI in the test host), gaps between neighbours, motion not explained by the
  commanded change. Frames alone can look perfect while content moves inside them.
- **Inert hooks for causes.** Production may emit events through a static optional sink that is nil
  in production (`TranscriptProbe`), with an autoclosure so nothing is evaluated. Log every
  invalidation and geometry write with its cause.
- **Report.** Write `report.md` (totals per scenario, top 20 worst events with context) and
  `report.json` (raw) to `ProcessInfo.processInfo.environment["HARNESS_OUT"]`.
- Test target deps live in `Packages/PaseoUI/Package.swift` (PaseoStore, PaseoKit, PaseoProtocol already added).

## 2. Run on CI

- Work on a `harness/<slug>` branch; a push runs `.github/workflows/transcript-harness.yml`.
  For a class other than the default: `gh workflow run transcript-harness.yml --ref <branch> -f only_testing=PaseoUITests/<Class>`.
- About 20 minutes per run. Watch in the background: `gh run watch <id> --exit-status`. On failure:
  `gh run view <id> --log-failed`, or the job's "List errors" step.
- Get results: `gh run download <id> -n transcript-harness -D <scratchpad dir>` → `harness/report.md`,
  `harness/report.json`, the xcresult and the xcodebuild log. The report is also the job summary.

## 3. Baseline, fix, compare

- First get a baseline from unchanged production code, then have a skeptic check the harness:
  does it drive real code, can a metric be vacuous, does a number double count? Fix High gaps first.
- Push the baseline branch and a `harness/<slug>-fix` branch together: both run at once.
  Compare metric by metric; explain every residual event (e.g. mermaid doesn't render in CI and
  shrinks off-screen) before calling it done.
- Merge only the fix to main (the harness can come along; its hooks are inert), then rerun on main
  (`gh workflow run ... --ref main`) and the unsigned IPA build, and tell the user what to test on device.
- The saved workflow `measure-then-fix` (`.claude/workflows/measure-then-fix.js`) runs audits, harness,
  skeptic and an optional fix as one orchestration.

## Gotchas

- Simulator system safe area without a scene is about 62 top / 12 bottom, not the device's 59/34.
- xcodebuild passes `TEST_RUNNER_<NAME>` to the test process as `<NAME>`.
- WebKit content (mermaid, html cards) and remote media don't render or load in CI.
- Sampling every 16 ms hides transients shorter than a step; say so in the report.

## Other uses

Layout across Dynamic Type sizes or rotation (step the trait, measure frames and clipping), keyboard
appear/dismiss (step the bottom inset), streaming a long answer (append text per step, measure
anchor drift), screen open time and body counts (timestamps and counters through the probe), and
regression checks before shipping a risky UI change.
