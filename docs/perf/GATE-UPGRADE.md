# Gate upgrade request (recommended, not blocking)

W1 Phase 0 decided the v3 gate is enough to find and fix the structural jank: the app carries its own
instrument (`-paseo-perf`: display-link frame pacing, run-loop stall watcher, signposts, body and event
counters, an optional sampling profiler) and prints one aggregated line per second through `os.Logger`,
which `applog` returns (windows for a five-minute scenario fit in the 300-line tail). Everything in
`W1-findings.md` was found and verified that way. Three things the gate cannot give, in order of value:

## 1. A Release simulator install (the one that matters)

`install <ref>` builds Debug. Debug SwiftUI is several times slower (no specialisation, no inlining), so
absolute stalls and hitches in the findings are inflated and a "zero hitches" budget cannot be signed off on
them. Counts and ratios are valid; the verdict on a phone is not.

Proposed verb: `install <ref> release`, the same checkout and the same `PaseoClient` scheme with
`-configuration Release` (`SWIFT_COMPILATION_MODE=wholemodule`, signing off), installed on the test
simulator. Argument pattern: the second word is exactly `release` or absent. No other change to the
forced-command model. (`ipa` already builds Release for devices, so the build settings exist.)

## 2. `xctrace` on the app process (optional)

`PerfSampler` (`-paseo-perf-sample`) attributes stalls to frames, but `dladdr` cannot name the app's private
Swift functions, so the "own code" frames are approximate. Proposed verb:
`profile <template> <seconds>` with `template` in `time-profiler`, `animation-hitches`, `swiftui` and
`seconds` 1 to 30: `xcrun xctrace record --template <name> --attach Paseo --time-limit <n>s --output
~/sim-artifacts/<run>/<name>.trace`, then `xctrace export --toc` and a table export of the hot stacks to a text
artifact fetched with `get`. The attach pid is the simulator app's own (`status` already knows it).

## 3. Smaller

- `swipe <x1> <y1> <x2> <y2> [duration-ms 50-2000]`: AXe's `swipe --duration` is not reachable, so flings are
  whatever `gesture scroll-*` does. A hard-fling scenario needs a duration.
- `applog <minutes> [lines]`: lines up to 2000 (default 300) for long scenarios.
