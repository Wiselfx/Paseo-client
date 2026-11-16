# Gate upgrade request (recommended, not blocking)

W1 Phase 0 decided the v3 gate is enough to find and fix the structural jank: the app carries its own
instrument (`-paseo-perf`: display-link frame pacing, run-loop stall watcher, signposts, body and event
counters, an optional sampling profiler) and prints one aggregated line per second through `os.Logger`,
which `applog` returns (windows for a five-minute scenario fit in the 300-line tail). Everything in
`W1-findings.md` was found and verified that way. Three things the gate cannot give, in order of value:

## 1. A Release simulator install (written: `install-release`, needs deploying)

`install <ref>` builds Debug. Debug SwiftUI is several times slower (no specialisation, no inlining), so
absolute stalls and hitches in the findings are inflated and a "zero hitches" budget cannot be signed off on
them. Counts and ratios are valid; the verdict on a phone is not.

`Tools/build-gate/build-gate` on this branch now has `install-release <ref>`: the same checkout, scheme and
simulator as `install`, with `-configuration Release` (so `SWIFT_COMPILATION_MODE=wholemodule`, `-O`), signing
off, its own derived-data folder `~/build-derived-data-release` (`clean` removes it too), installed on the test
simulator. One argument, the same pattern as `install`; `GATE_VERSION` is 4. Nothing else in the forced-command
model changed.

**What the owner must do on the Mac** (the script on the Mac is a copy, not the repo file):

1. On the Mac, as the admin account, from a clone of this repo at `foundation` (or this branch):
   `git pull` then copy the script over the forced command's target. Find it with
   `grep -n command= /Users/claude/.ssh/authorized_keys` (the `command="..."` path is the installed script);
   then `sudo cp Tools/build-gate/build-gate <that path> && sudo chown claude:staff <that path> && sudo chmod 755 <that path>`
   (keep the owner and mode the old file had: `ls -l` it first).
2. Check: `ssh -i <key> claude@host.orb.internal ping` prints `gate v4`.
3. First use: `install-release foundation` (a cold Release build is slower than the Debug one; the cap is 1500 s).
   Then `launch -paseo-perf` and run the scenarios exactly as for Debug; compare the `VERDICT` lines.

The Release build is not stripped of `-paseo-perf`: the instrument is compiled in every configuration and off
by default.

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
