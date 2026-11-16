# Worker scorecard

Terse verdicts per worker, grouped by harness + model. A "lead catch" is a defect the lead found in
review that the worker's own report didn't flag. Add a row per ticket; compare harnesses by the
averages.

## OMP · `opencode-go/deepseek-v4.1-flash` (mode full, thinking high)

| Ticket | Grade | Root causes | Lead catches | Rounds | Notes |
|---|---|---|---|---|---|
| E1 composer + voice | A− | Correct: dead `@FocusState`, a Canvas not tied to the tick, missing AEC | 0 | 1 (+1 lead-decided tweak in E1b) | A thorough upstream trace. Over-engineered the focus bridge (`pendingEcho`), but correct. Honest about what it couldn't verify. |
| E2 look + launch | B | Correct: scrim, `EmptyMain` hugging, the `List` height, the inset double-count | 2 (the back-to-end button over the subagent pill; a `UIColor !=` per update in the terminal) | 2 + lead fixes | Wide scope, handled well; good shadow path. Its report answered a "§13 focus mode" that was never asked (the brief stopped at §12). On the merits it was correct and harmless: focus mode is desktop-only (`PARITY.md:445`), no code exists for it, and it changed nothing. Not a defect, just a phantom line in the report. 2 other issues were the lead's own ticket mistakes, not counted. |
| E3 subagents + rich media | B− | Excellent: a live probe found the `projected_subagent_timeline` root cause; a per-provider capability table | 4 (isolation warnings; a per-card viewport reader → uncapped first frame; yield+`scrollTo` flash; caps resizing with the keyboard) | 3 | Best diagnostician, weakest layout-stability instincts. **Incident:** its probe sent a message into the user's Claude session (led to the "never touch Claude agents" rule). |

**Harness average:** B. Strong at diagnosis and following tickets. Misses layout-stability and
per-frame cost unless the ticket spells them out. Needs a strict reviewer.

## Claude Code subagent · Opus (general-purpose, Agent tool)

| Ticket | Grade | Notes |
|---|---|---|
| UX research (doc 14) | B+ | A good, opinionated plan with real sources. Overran the length cap. Blocked twice by a safety classifier and couldn't recover, so the lead wrote §8–15; the user rescued its draft. |

## Pi · `opencode-go/deepseek-v4.1-flash` (H-round)

| Ticket | Grade | Root causes | Lead catches | Rounds | Notes |
|---|---|---|---|---|---|
| H1 voice | A | Excellent: `int16ChannelData` pointer array sent as audio; level path; tap lifecycle | 3 (probe could prompt any agent → claude guard; display link at 120 Hz; 2 init compile errors fixed by lead) | 2 + lead fix | Live wire proof end to end. Its refusal test pointed the probe at the lead's Claude agent (read-only lookup, nothing sent) — still a rule breach in spirit. |
| H2 transcript + header | A | Correct, three runway causes + exact back-to-end sequence | 0 | 1 | Best design work this round: pure state machine in Core, constant-height bar, honest "Unsure" list. |
| H3 composer | B+ | Correct | 2 (O(n) char-estimate scan per keystroke; `layoutManager` access forces TextKit 1 — lead fixed) | 2 + lead fix | Good extraction and off-main file reads. Weak instinct for keystroke cost and TextKit. |
| H4 splash/usage/appearance | B+ | Correct (window trait); splash cause plausible, unproven | 3 (sidebar R-1, forced refresh on drawer open, project file missing → gate fail) | 3 | Solid; launch-colour catch was proactive. |
| H5 images | A− | Excellent corpus with live curl | 3 (failure-height jump, longest-side downsample blur, Double/CGFloat gate error) | 3 | Best diagnosis; fixed its found items well. |
| HB bug hunt (Muse Spark 1.3, pi, high) | B | 6 small real fixes, all verified | 0 | 1 | Real but modest; good systemic notes (error channel per store, poll without change check, optimistic UI). |
| G Phase A (Muse Spark 1.3, pi, high) | B | Good architecture (one pipeline, pure policy + 30 table tests, UIKit pager); thorough reports | 3 gate rounds (~40 compile errors, deleted a used function, isolation) + 11 review bugs (per-byte AsyncBytes hops, relay rule on web images, cap after transfer, disk key mismatch, singleton/unregister race, dismiss pan stole paging, zoom relayout) | 3 + 2 lead fixes | Strong design, weak compile discipline; review catches were real. |
| G Phase B1 G4+G5 (Muse Spark) | B | Verified pinned runtime; real CSP/rule-list hardening once pointed at it | 3 gate rounds + review: full-doc HTML artifacts were online, stale timeout resolved wrong render, 3.5 MB JS rebuilt per diagram on main, extra offscreen web view + window, never-resumed continuation (would hang), author CSP opt-out | 1 + 2 lead fixes | Same pattern: good design, weak API/isolation accuracy. |
| G Phase B2 G6–G12 (Muse Spark) | B | Big, mostly sound stretch with good Core parsers + tests; fixed 2 review batches thoroughly | 4 gate rounds (nested type, isolation, missing return) + review: streaming-turn index gap, per-token diff parse, cache-in-.task remount jumps, 64 MB writes on main, §12 bypasses, openDiff scope, dead GitHub lookup, gallery a11y, scrub stealing scrolls | 2 + 3 lead fixes | Consistent: strong design, weak compile accuracy. |
| G13 charts (Muse Spark) | B− | Followed the plan; good provider table once pointed at upstream | assumed per-turn usage on turn_completed (empty charts for pi/opencode), AX descriptor API invented, per-step delta bug | 1 + 2 lead fixes | Data semantics need explicit verification instructions. |
| G Phase C (Muse Spark) | B | Five solid items, good provider tables, honest C2 reasoning | 3 gate rounds (ambiguous init, isolation of file helpers, missing public init) + review: streaming cells never remeasured, cold-launch image pop, late subagents never tappable, D8 read in big view | 1 + 1 lead fix | Compile accuracy still the weak spot. |
| G Phase D (Muse Spark) | C+ | Right architecture (one router, one notification system, no entitlements); good background-send redesign once told | 6 gate rounds, mostly invented/mis-scoped API (missing brace, static var intents, EntityStringQuery label, double-escaped interpolation, internal type from App, non-Sendable response across hop, missing switch case) + review: background Allow/Deny never sent, lines on the wrong store, multi-host directory wipe | 1 + 7 lead fixes | App-target code needs far more care; lead did most of the compile work. |
| G Phase E (Muse Spark) | B | Clean D1 compliance (extension built, not embedded, verified in pbxproj); clear turn-on list | 1 gate round (undefined serverID, optional unwrap) | 1 lead fix | Lessons from D applied; best compile pass of the round. |

**Harness average:** A−. Pi workers were stronger than OMP on diagnosis and design; still miss Apple-specific traps (TextKit, project files, numeric bridging) that only the gate or the lead catch.

## J-round (device feedback 4, 2026-11-12)

| Ticket | Worker | Grade | Notes |
|---|---|---|---|
| J1 prose faces + Mermaid | DeepSeek v4.1 flash (pi, minimal) | B | Root causes right; first cut changed the body face app-wide (claimed byte-identical), missing helper, nonexistent `Font.Weight.extraLight`; 1 review round + 1 lead isolation fix + lead fix for inline-code paragraphs |
| J3 composer + back-to-end | DeepSeek v4.1 flash (pi, minimal) | C+ | Root causes for tile + hit-testing right; item 3 "fix" used the same inset formula (no-op, and would re-decide per keyboard frame), undefined `previous` var, forced 56 pt frame on file pills, dropped the decode tile; lead fixed all four |
| J2 rich blocks + links | DeepSeek v4.1 flash (pi, minimal) | B+ | All five items with Core tests (37 new), careful reveal-length reasoning, caught its own image-URL regression; missed per-render memoization of the new unit scans and list+player lengths (lead fixed); 3 small out-of-Owns wiring edits, declared |
