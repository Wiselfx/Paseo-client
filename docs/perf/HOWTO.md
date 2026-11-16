# Performance HOWTO (the `-paseo-perf` mechanism)

For the next engineer or agent. Rules and budgets: `PERFORMANCE-RULES.md`. Every jank found so far and
how: `W1-findings.md`. Gate details: `GATE-UPGRADE.md`. This file is the manual.

## 1. The switches and the window line

Both are launch arguments, off by default, compiled into every configuration (Debug and Release).

- `-paseo-perf`: starts `PerfMonitor` (`Packages/PaseoUI/Sources/PaseoUI/DesignSystem/Perf/`). A
  `CADisplayLink` measures frame pacing; two run-loop observers measure how long the main thread is busy
  per wake (layout and the Core Animation commit are inside it); counters and spans are drained once a
  second. Output: `os.Logger`, subsystem `com.wiselfx.paseoclient`, category `perf`, read with the gate's
  `applog`.
- `-paseo-perf-sample`: also starts `PerfSampler`, a thread that suspends the main thread every ms while it
  has been busy over 4 ms and records the stack. Prints a second line `perf.hot` per window. It changes
  layout timing (a long chat once opened blank only with it running), so use it to find a cause, **never
  to take a number**.

Launch (via the gate): `launch -paseo-perf` or `launch -paseo-perf,-paseo-perf-sample` (comma separated, no
spaces).

A window is one second of frames. Only "interesting" windows print (scrolling, a mark, a hitch or a
stall), so an idle app prints nothing. Example:

```
perf t=15.2 fr=41 hit=1 drop=19 gap=19 hms=310.2 worst=326.9 p50=16.7 p95=16.7 p99=16.7 scroll=0
     busy=41% stall8=2 smax=334.0 stalls=334.0[rich.pieces 2.0];12.1 body=Composer:2 n=fit.hit:15 sp=fit.layout:3x0.9/max0.4
```

| Field | Meaning | Normal | Bad |
| --- | --- | --- | --- |
| `t` | seconds since launch | | |
| `fr` | frames in the window | 60 (sim, 60 Hz) | far below 60: the main thread was blocked |
| `hit` | frames later than 1.5 budgets | 0 | any |
| `drop` | frames missed in total | 0 | tens |
| `gap` | longest run of missed frames in one gap | 0 | > 3 is visible |
| `hms` | milliseconds lost to hitches | 0 | hundreds |
| `worst` | longest frame, ms | 16.7 | 100+ |
| `p50/p95/p99` | frame interval percentiles | all 16.7 | p95 or p99 above 33 |
| `scroll` | frames spent in scroll tracking mode | 60 while a scroll runs | |
| `busy` | main-thread busy share of the window | under 15% scrolling | 50%+ with nothing happening |
| `stall8` | wakes where the main thread worked over 8 ms | 0 | |
| `smax` | longest single wake, ms | under 8 | 20+ |
| `stalls` | the first four stalls, each with the signpost spans that overlapped it | | names the culprit |
| `body=` | `body` evaluations per named view (`PaseoPerf.body`), top 8 | 0 at idle | a view running tens of times a second |
| `n=` | event counters (`count`, `countNamed`, `diff`, probes), top 16 | | |
| `sp=` | spans: `name:count x total_ms / max max_ms`, top 6 | | |

A **normal scroll line**: `fr=60 hit=0 drop=0 worst=16.7 scroll=57 busy=10% stall8=1 smax=11`. A **bad line**:
`fr=9 hit=9 drop=53 worst=300 busy=100%` with `body=Shell:150`: something is re-rendering in a loop (that was
the first finding). `perf.hot` lines: `own=` is the innermost three app frames, `leaf=` the hottest innermost
frames. If `leaf` is mostly `mach_msg2_trap` / `__psynch_cvwait` the thread is waiting, not computing.

## 2. In-code tools (all free when `-paseo-perf` is off)

All are `PaseoPerf` statics (`DesignSystem/Perf/PaseoPerf.swift`, `PerfProbe.swift`):

| Call | Use |
| --- | --- |
| `let _ = PaseoPerf.body("Name")` | first line of a `body`: counts evaluations (`body=`) |
| `PaseoPerf.measure("name") { ... }` | times a block; shows in `sp=` and in stall attribution; also an `os_signpost` interval |
| `let s = PaseoPerf.begin("name"); defer { PaseoPerf.end(s) }` | the same when a closure does not fit |
| `PaseoPerf.count("name")` | counts an event (`n=`) |
| `PaseoPerf.countNamed("x.\(value)")` | the same with a run-time name; wrap in `if PaseoPerf.enabled` (the string is built by the caller) |
| `PaseoPerf.mark("name")` | forces the window to print and names it (`mark=`); use for "a sheet opened" |
| `let _ = PaseoPerf.diff("view", [("input", "\(value)"), ...])` | which input of a body changed: counts `diff.<view>.<input>`; `diff.<view>.none` means the body ran with no input changed, i.e. an observed store or an unlisted input |
| `PerfProbe("name", value)` | in a `.background`, under `if PaseoPerf.enabled`, with the value read in a *separate* view struct (see `ShellPerfProbes` in `ShellView.swift`); counts `probe.<name>.read` (observation fired) and `.changed` (value really changed) |

Instrument a new view, minimal:

```swift
var body: some View {
    let _ = PaseoPerf.body("MyRow")                       // 1. who re-runs, and how often
    let _ = PaseoPerf.diff("myrow", [("text", text)])     // 2. only if the count is surprising
    PaseoPerf.measure("myrow.parse") { parse(text) }      // 3. only around work you suspect
    ...
}
```

Keep `body("X")` and `measure` on hot paths (a lock and a dictionary write only when enabled). Remove `diff`,
`PerfProbe`, `countNamed` and any one-off probe once the cause is found (the first pass left `md.*` and
`geom.*` probes that were removed afterwards). Signposts are visible in Instruments but the gate has no
Instruments; the window line is the readable channel.

## 3. Scripts (`docs/perf/scenarios/`)

Required environment:

```sh
export GATE_HOST=claude@<gate-host>          # the gate login (required; no default, never commit it)
export GATE_KEY=/path/to/gate_ed25519        # optional, default is a path on the lead's machine
export PASEO_PASSWORD=simtest-pass; unset PASEO_WORKSPACE_ID   # only stream.sh (talks to the test daemon)
```

The app must be installed from your pushed branch first (the gate fetches from GitHub):
`ssh -i $GATE_KEY -o BatchMode=yes $GATE_HOST "install <branch>"` (Debug, about 1 to 3 min) or
`"install-release <branch>"` (Release, about 3 min). Release is the verdict; Debug is for counts.

| Script | Invocation | Takes | Does |
| --- | --- | --- | --- |
| `perf-run.sh` | `./perf-run.sh [--keep] <name> "<do steps>"` | steps + ~14 s | relaunches with `-paseo-perf` (unless `--keep`), waits 8 s, stamps the Mac's clock, runs the `do` steps, waits 2 s, prints the windows after the stamp and a `VERDICT` line |
| `repeat.sh` | `./repeat.sh <name> "<steps>" [runs=3]` | runs x above | N cold-launch runs; prints median [min..max] of hitches, dropped, worst-frame, stalls>8ms, stall-max, busy-avg |
| `stream.sh` | `AGENT=<agent id> ./stream.sh ["<steps>"]` | ~45 s | asks the test agent for a ~1500-word markdown reply (inline code, table, five fences) while the chat is open, prints windows |
| `extra.sh` | `./extra.sh` | ~5 min | dynamic type ax5/xs/m, light/dark, code blocks, work group, media cards on the rich-media chat. Labels in its steps are chat-specific: check them (below) |
| `summarize.py` | called by `perf-run.sh`; stdin = `applog`, `--after "YYYYMMDD HHMMSS"` | | filters window lines and computes the verdict |

`VERDICT windows= frames= hitches= dropped= longest-gap= worst-frame= stalls>8ms= stall-max= busy-avg=
scroll-frames=`: sums over the printed windows. `windows=0` means nothing printed, which for an idle
scenario is the good answer. Budgets are in `PERFORMANCE-RULES.md` (zero hitches over one frame, no stall
over 8 ms); the simulator cannot sign off one-frame hitches, so read stalls and counts.

Idle floor: `./repeat.sh idle "wait 12" 3`. Typing: `./repeat.sh typing "tapid composer.draft | wait 2 |
type abcdefghijklmnopqrst | wait 1 | <20 x delete steps> | wait 2" 3`. Drawer: `edge left | wait 2 |
tapxy 420 500 | wait 2` repeated.

## 4. The workflow (checklist)

1. Baseline on the unchanged build: `install-release <branch>`, idle floor, then the scenario, 3 cold runs
   each (`repeat.sh`). Write the median and range down before touching code.
2. Read the window line: which `body=` is high? which `stalls=` span overlaps? `busy` with no user input =
   a loop.
3. If the cause is not obvious: relaunch with `-paseo-perf,-paseo-perf-sample`, repeat once, read the
   `perf.hot` lines (`own=` first, then `leaf=`). Waiting leaves mean IPC/locks, not compute.
4. Narrow with counters: `body`, `count`, `diff` (which input), `PerfProbe` (which store). The question to
   answer is "why did this run" before "why is it slow".
5. Fix at the cause (see the rules). One commit per fix, subject
   `W1: <what> (<before> -> <after>)`. Push the branch.
6. Re-install the same configuration and re-measure with the same script, 3 cold runs. Only a difference
   larger than the run-to-run range counts.
7. Confirm in Release (`install-release`). Remove one-off probes. Add the rule and the number to
   `PERFORMANCE-RULES.md` / `W1-findings.md`. Leave the simulator on a normal connected screen.

## 5. Tips, tricks, traps

What lies:
- **Debug numbers**: inflated and shaped differently (protocol-conformance lookups dominate); under the
  repeated method Release and Debug were equal for typing and close for scrolling. Counts and ratios carry
  over; milliseconds do not.
- **The tail of the previous scenario**: a window printed right after another scenario contains its
  activity. `perf-run.sh` relaunches and settles 8 s for that reason; with `--keep` you must wait.
- **Mixed scripts**: comparing a script that includes the first keyboard focus (a 330 ms cold stall) with one
  that does not looked like "Release is 8x worse". Same script, same chat, always.
- **The app-start window** (first 2 s after launch) holds the cold costs; exclude it, or measure it
  deliberately and say so.
- **The sampler lies a little**: names come from `dladdr`, which cannot name private Swift functions (it
  reports the nearest exported symbol), so `own=` chains are approximate; trust leaf frames and module names.
- **The simulator** is not a phone: 60 Hz only, shared GPU. One-frame hitches cannot be signed off on it.

Practical limits:
- `applog` returns the newest 300 lines, 1 to 60 minutes. A window line per second of activity fits about
  five minutes; read it right after the scenario, and do not leave a chatty scenario running before it.
  Lines over 1 KB are truncated by `os_log`, which is why `perf.hot` is a second line.
- **AXe**: `swipe`/`scroll` have fixed speeds (no hard fling); typing is about 2 to 3 keys a second so each
  key is its own window; `tap <label>` needs the exact accessibility label and labels differ per chat and per
  state: read them with `ssh ... "do ui reading"` (or `ui full`) first. Labels containing characters outside
  `A-Za-z0-9 _.,:'!?@#%+=/-` are refused by the gate (use `tapid` or `tapxy`). `do` steps are one call of at
  most 800 characters; `wait` is 1 to 15 s. The outline rail appears only while scrolling and is not
  targetable by AXe.
- **Long chat for testing**: on the test daemon (port 6768, only the `pi` provider, never a claude provider)
  `paseo --host localhost:6768 run --workspace <wks> --provider pi/opencode-go/beam-free --title "Perf long"
  "<prompt asking it to reply with exactly this markdown ...>"`, then `send` the same kind of prompt 40+ times
  (prose, a table, 20 to 300 line fences, mermaid, images by local path). Keep scroll/stream chats under
  ~10 000 pt; a 60 000 pt chat is for the open-a-long-chat case.
- **New-session page**: open the sidebar first (`edge left | wait 2`), then `tap New session`. The composer is
  `tapid composer.draft`. Open a chat: `tap Open sidebar | tap Search | type <title> | tapxy 220 262`.
- **Draft text persists** across launches; it changes the composer's height and so later measurements. Clear it
  (many `delete` steps) before a typing run.

Traps found the hard way:
- **Blank long chat**: opening a very long chat in a lazy stack can leave no rows under the final offset until
  a real scroll event; the open re-seat plus a 2 pt nudge in `ChatTranscript` fixes the open, and a long
  programmatic jump (find-in-chat) still lands blank. It reproduced in normal launches, not only under the
  instrument.
- **Keyboard prewarm** (focus and release a throwaway text field at chat open) did not reduce the 330 ms
  first-focus stall: the cost is SwiftUI/UIKit metadata and the transcript re-measuring when the keyboard
  shrinks it, not the keyboard process. Reverted.
- **Observation traps**: `State(initialValue: Controller())` runs on every parent pass; reading an
  environment value in a big body re-runs it when the system rebuilds that value; `.id(changingValue)` on
  content destroys the subtree. See the rules.
- **Simulator "Connecting…" forever** (both Debug and Release): the simulator lost its route to the test
  daemon (host address / IP changed or the tunnel is down), not an app bug. Check the daemon from Linux
  (`paseo --host localhost:6768 ls`), then ask the owner to check or re-pair the host on the simulator
  (`simreset` wipes the app data). Do not leave the simulator disconnected.
- Never message, prompt or probe a claude-provider agent. Test chats use `pi/opencode-go/beam-free` only.

## 6. Where things live

- Budgets, the measurement rule and numbered rules: `docs/perf/PERFORMANCE-RULES.md`.
- Every finding with cause, fix commit and before/after, plus what is open and why: `docs/perf/W1-findings.md`.
- Lint for the patterns proven harmful: `Tools/style-lint/style-lint.sh` (`perf-*` rules; reports, never fails).
- Core tests that pin behaviour: `StreamingIdentityTests` (row and segment ids stable while text streams).
- Instrument source: `Packages/PaseoUI/Sources/PaseoUI/DesignSystem/Perf/`; started from
  `App/Sources/PaseoClientApp.swift`.

Adding a rule when you learn one: (1) measure the cause with the checklist, (2) add a numbered rule to
`PERFORMANCE-RULES.md` with the reason, the number that motivated it and the right pattern in this codebase,
(3) if it is greppable add a `perf-*` line to the `rules=(...)` array in `style-lint.sh` (pattern, then an
optional exclusion pattern), (4) add the finding row to `W1-findings.md`, (5) if the invariant is testable on
Linux add a Core test in a new file. A fix without its before/after number is a guess.
