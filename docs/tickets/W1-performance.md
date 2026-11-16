# W1 — Performance: find every jank, fix it, write the rules

Read `AGENTS.md`, `ARCHITECTURE.md`, `docs/perf/overall-perf.md`, `docs/tickets/_V-common.md` first.

## The bar (the owner's words)
This is mission critical. The app must be **smoother than butter**. Not one millisecond of jank,
jitter or uneven frame pacing is acceptable, on a phone, in a long chat, on first use and on the
hundredth. You are not asked to "look at performance". You are asked to **account for every jank**,
fix each one the moment you find it, prove it with numbers, and leave rules behind so it never
comes back. Perceived smoothness counts as much as measured smoothness: a card that pops in late, a
layout that settles after a frame, a sheet that opens a beat after the tap are all jank.

## Phase 0 — can you do the job? (do this first, then decide)
Work out what instruments you need and whether the Mac gate gives them. What the gate has today
(see the header of `Tools/build-gate/build-gate`): `build`, `install`, `launch <args|->`,
`terminate`, `do` (AXe steps: `ui`, `tap`, `tapxy`, `swipe`, `scroll`, `edge`, `type`, `wait`, `shot`),
`shot`, `get`, `applog [minutes]` (the app's os.Logger output, subsystem `com.wiselfx.paseoclient`,
**newest 300 lines only**, 1 to 60 minutes), `crashes`, `status`, `textsize`, `appearance`,
`statusbar`, `openurl`, `test`, `analyze`. There is **no Instruments / `xctrace` verb** and no
device. Access: `ssh -i /home/paseo/.ssh/paseo_build_ed25519 -o BatchMode=yes claude@<mac-host> "<verb> ..."`.

Decide honestly. If what you need is missing (for example an `xctrace` Time Profiler / Animation
Hitches capture, a longer log tail, a metrics export verb, a ProMotion-like display rate), then
**stop here**: write `docs/perf/GATE-UPGRADE.md` with exactly what you need, why, the proposed verb
and its arguments (the gate is a forced command with strict argument patterns, keep that model), commit
it on your branch, and end your turn with the request. Do not proceed to Phase 1 on a gate you
cannot trust. If the gate is enough (counters printed through `applog` are enough for many
things), say so in one line and continue.

Know the limits of the simulator: it runs on the Mac's GPU/CPU, so absolute FPS is not a phone's.
Trust **relative** numbers and **main-thread time**: hitch counts against a 16.7 ms budget, main-thread
stalls over 8 ms, layout/`body` counts per scroll, allocations per frame, work done off-screen. A thing
that is wasteful on the simulator is jank on a phone. Never tune to the simulator's headroom.

## Phase 1 — instrument (build once, keep it)
Add a small, permanent, **off-by-default** instrument (launch argument, for example `-paseo-perf`),
compiled in all configurations but costing nothing when off:
- A frame-pacing monitor on `CADisplayLink`: frame interval histogram, hitches (>1 frame late),
  worst frame, dropped-frame runs, per scenario window; prints one **aggregated** summary line per
  window through `os.Logger` (never one line per frame: `applog` keeps 300 lines).
- A main-thread stall watcher (a heartbeat; report stalls over 8 ms with the nearest signpost).
- `os_signpost` intervals around the hot paths you care about (turn row body, markdown parse,
  code highlight, rich card mount, image decode, sheet/sidebar open, session create).
- Counters for `body` evaluations and decodes of a named view while a scenario runs.
Put it under `Packages/PaseoUI/Sources/PaseoUI/DesignSystem/Perf/` (or similar). Tokens only, R-1 to R-7
apply to it too. It must never run in a normal launch.

## Phase 2 — scenarios (script them so a number can be re-measured)
Use the gate's `do` steps (`swipe x1 y1 x2 y2` for repeatable flings; `scroll`; `edge`). Write the
scenarios as files under `docs/perf/scenarios/` so anyone can re-run them. Cover at least:
1. **Chat scroll**: a long conversation (generate one on the test daemon with a pi agent, many turns of
   prose, headings, lists, tables, code blocks of several lengths and languages, think blocks,
   tool calls, images, diagrams) — slow drag, hard fling, reverse fling, jump to top / "Back to the end".
2. **Streaming**: a reply streaming in while you scroll and while you do nothing (text growth, code
   block growth, think block growth, follow-the-bottom).
3. **Text and prose rendering**: first appearance of a long message, markdown tables, inline code,
   links, dynamic type extremes (`textsize ax5`, `xs`), dark/light.
4. **Code blocks**: highlighting of long blocks, horizontal scroll, copy, collapse/expand.
5. **Think blocks**: expand/collapse, streaming into them, many in one turn.
6. **Left sidebar and right panel**: open/close by tap, by edge drag, mid-drag cancel, with long
   lists and with the keyboard up; first open and the tenth.
7. **Rich media**: images (single, gallery), video, audio, mermaid diagrams, SVG/HTML artifact
   cards, link previews: arriving while scrolling, scrolling back over them, first vs second visit,
   no layout shift, no flash, no pop. The rich-media test chat is agent `9972fe65` on the test daemon
   (`/home/paseo/dev/feedback/rich-media-findings.md` lists what was already found).
8. **New session and new agent creation**: opening the new-session page, typing (keyboard, composer
   growth), pickers (provider, model, mode, thinking), attach, send; the transition into the new
   chat; creating an agent from a workspace; cold start and relaunch-restore.
9. Anything else you find while looking. **Check everywhere**: the launch path, the composer,
   sheets, settings pages, files panel, terminals, usage footer, notifications.

Test daemon: port 6768, home `~/paseo-test-home`, password `<test-daemon-password>`, only the `pi` provider.
`export PASEO_PASSWORD=<test-daemon-password>; unset PASEO_WORKSPACE_ID; paseo --host localhost:6768 ...`
(`run --workspace wks_67fb23e75d3f0f13 --provider pi/opencode-go/beam-free`, `send`, `logs`, `ls`).
Never message, prompt or probe a claude-provider agent through that daemon or any other.

## Phase 3 — fix everything you find, immediately
For each jank: record before (numbers), find the cause, fix it at the cause (no band-aids that hide
the symptom, no `drawingGroup` everywhere, no fixed delays), record after, commit it (one commit per
fix, message `W1: <what> (<before> -> <after>)`). Typical culprits to check first, from this
codebase's own history: work in `body`; observation that is too wide (R-1); closures in rows (R-2);
layout that settles after first paint; measuring through `GeometryReader` per row; `onChange` on a
computed value; synchronous decode, parse or highlight on the main actor; images drawn at full size;
`AttributedString` rebuilt per pass; `LazyVStack` rows whose height changes after appearing; state
published when it did not change; animations on large trees; web views started on scroll; sheets
that build their content before they are visible; `withAnimation` on layout that is not finger-driven;
finger-tracked motion that is not in UIKit (R-3). Fix what you find even if it is outside the files
you first looked at: this ticket's scope is the whole app. If a fix is a behaviour change, keep it
the same behaviour, only smoother; if it would change what the user sees, note it in the final message.

Do not trade correctness for speed: Core tests must still pass (`swift build --build-tests && swift test`
in `Packages/PaseoCore`; Linux). UI is compiled only by the gate: build every few fixes
(`build <branch>`; the gate fetches from GitHub, so **push your own branch `w1-performance`** — never
`foundation` or `main`) and `install` + drive it before you claim a fix. UI cannot be compiled here;
`swiftc -parse` is your local check.

## Phase 4 — rules (the lasting part)
Write what you learned as rules and make them enforceable:
- `docs/perf/PERFORMANCE-RULES.md`: short, numbered, each rule with the reason, the number that
  motivated it, and the right pattern in this codebase. Add a pointer from `AGENTS.md` UI rules (R-8
  onwards) so every future agent and reviewer reads it.
- Enforcement, not hope: extend `Tools/style-lint/style-lint.sh` with greps for the patterns you
  proved harmful (it already guards R-4); add Core tests for anything testable on Linux (parsers,
  caches, key stability); and keep the scenario scripts + the `-paseo-perf` summary so a regression is
  a number someone can diff. Put the **budgets** in the rules (for example: zero hitches over 1 frame
  in scenarios 1, 6, 7; main-thread stall under 8 ms; N body evaluations per row per scroll).
- `docs/perf/W1-findings.md`: every jank found: where, how it was measured, cause, fix commit,
  before/after. This is the accounting the owner asked for. Include what you could not fix and why.

## Done means
Every scenario re-run after your fixes shows no hitch over one frame and no stall over 8 ms, or the
exception is written down with its cause and the reason it stays. The gate build succeeds, Core tests
pass, the app installed from your branch runs the scenarios cleanly. Final message: the table of
findings (short), the numbers, what you could not verify, and what the owner should feel on a real phone.

## Rules of engagement
- Taste is part of the job: do not change the look, copy or behaviour; polish timing, not design.
- Upstream first (R-7): if behaviour needs a reference, use `/home/paseo/dev/paseo-upstream-ref`.
- The owner may be watching the simulator: do not leave it in a odd state; finish scenarios by
  returning the app to a normal screen. Screenshots: only when you need one; half-size JPEG.
- Public repo: no secrets, hostnames, tokens or real agent titles in anything you commit.
- Do not push `foundation` or `main`. Commit trailer: `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`.
