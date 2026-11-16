# MEASURE: the cheapest path to evidence

Needs the gate (a Mac with the simulator, reached over ssh). Never commit its host. If you do not have it, say so in the report and escalate; do not invent numbers.

## Environment
```sh
export GATE_HOST=claude@<gate-host>      # required; never committed
export GATE_KEY=/path/to/gate_ed25519    # optional
export PASEO_PASSWORD=simtest-pass; unset PASEO_WORKSPACE_ID   # stream.sh only (test daemon, pi provider only; never a claude-provider agent)
```
Push your branch first (the gate builds from GitHub).

## The 5 commands
1. `ssh -i $GATE_KEY -o BatchMode=yes $GATE_HOST "install-release <branch>"` (about 3 min; `install` = Debug, 1 to 3 min, for counts only).
2. `ssh ... "do ui reading | wait 3"` once after each launch (AX warm-up).
3. `docs/perf/scenarios/perf-run.sh [--keep] <name> "<do steps>"` for one run (relaunches with `-paseo-perf`, waits 8 s, prints windows and `VERDICT`).
4. `docs/perf/scenarios/repeat.sh <name> "<do steps>" 3` for median [range] of 3 cold runs; first `repeat.sh idle "wait 12" 3` for the floor.
5. `AGENT=<id> docs/perf/scenarios/stream.sh` for streaming. Cause hunting: `PERF_ARGS="-paseo-perf,-paseo-perf-sample"` (stalls: `perf.hot`, `perf.stack`) or `-paseo-perf-changes` (`perf.why`).

## Scenarios (steps are gate `do` syntax; details: docs/perf/scenarios/README.md)
| Scenario | Steps |
| --- | --- |
| idle | `wait 12` |
| chat scroll | `--keep chat-scroll "scroll up \| scroll up \| scroll up \| wait 1 \| scroll down \| scroll down \| scroll down"` |
| typing | `ui reading \| wait 3 \| tapid composer.draft \| wait 2 \| type abcdefghijklmnopqrst \| wait 1 \| <20 x delete> \| wait 2` (clear a saved draft first) |
| drawer | `edge left \| wait 2 \| tapxy 420 500 \| wait 2` repeated; panel `edge right`, close `tapxy 40 500` |
| new session | open sidebar, `tap New session`, `tapid composer.draft` |
| open long chat | relaunch; read the first windows after the 8 s settle (restore of the long chat) |
| rich media | open the rich-media chat, then the scroll steps over image/diagram/card turns |
| streaming | `stream.sh` |

## Reading the window line
`perf t= fr= hit= drop= gap= hms= worst= p50/p95/p99= scroll= busy= stall8= smax= stalls= body= n= sp=`: normal scroll `fr=60 hit=0 worst=16.7 busy~10% stall8<=1 smax<11`;
a loop `fr=9 hit=9 busy=100% body=Shell:150`. `stalls=334.0[rich.pieces 2.0]` names the span that overlapped the stall; `body=` counts bodies per view; `n=` counters; `sp=` spans.
`perf.hot` leaf `mach_msg2_trap`/`__psynch_cvwait` = the thread is waiting (IPC, lock), not computing. Full field table: docs/perf/HOWTO.md section 1.

## Traps
- AXe: first interaction after a launch costs +100..140 ms (`ui reading` first). Labels differ per chat: read them with `do ui reading`. `do` is 800 chars max; `wait` 1..15 s.
- Simulator floor: 60 Hz only; one-frame hitches cannot be signed off. Mixed scripts and the app-start window (first 2 s) lie. `applog` keeps 300 lines: read right after the scenario.
- Draft text persists across launches and changes composer height; clear it before typing runs. Simulator stuck on "Connecting..." = lost route to the test daemon, not an app bug.
- Instrument costs: `diff` with `Mirror`, per-hit re-layout checks. If a stack's caller is `PaseoPerf`, remove the probe first.

## When you may skip measuring
Skip only if EVERY changed file is in this list; `final-check.sh` prints `measure: not required` exactly then:
docs and comments; tests; `Settings/`, `Onboarding/`, `Pairing/`, `Notifications/`, `History/`, `Schedules/` screens that add no list over unbounded data and no timer; token files in `DesignSystem/` (values only);
a pure rename; a Core change that touches no store write path and no `Turn`/`Timeline` code. Anything in `Transcript`, `Turn`, `Prose`, `Composer`, `Shell`, `Sidebar`, `Rich`/`Media`, `PaseoStore`, `App/`: **measure**.
Minimal evidence when skipping: the `final-check.sh` output (blocks 1 to 4, ticked). Minimal evidence when measuring: the [evidence block](TEMPLATES/evidence-block.md) with baseline and after, 3 runs each.
