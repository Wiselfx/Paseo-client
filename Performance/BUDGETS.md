# Budgets and baselines

Budget = what must hold. Baseline = what the last measurement showed (so you can tell a regression from noise). A change that makes a
budgeted scenario worse does not merge. Debug is the simulator's inflated build; **Release is the verdict**. All numbers: single chat, same script, cold launch,
median [min..max] over 3 runs unless marked `1x`. Terms: [GLOSSARY.md](GLOSSARY.md). Raw: [W1-findings](../docs/perf/W1-findings.md).

| Scenario (id in docs/perf/scenarios) | Metric | Budget | Release baseline | Debug baseline | Noise range |
| --- | --- | --- | --- | --- | --- |
| 0 Idle after launch (`idle "wait 12"`) | windows printed, `busy`, `body=` | none printed; busy < 5 %; no `body=` | 0 hitches, no window | 1 hitch [0..1], stall max 59 ms [0..65] | Debug floor is the simulator |
| 1 Chat scroll | hitches > 1 frame; stall | 0; no stall > 8 ms | not signed off on the simulator (one-frame floor) | 4 hitches in 21 s, stall max 21..22 ms | +-1 hitch |
| 2 Streaming 1500-word reply (`stream.sh`) | hitches, worst frame, stall max, busy | `Markdown` bodies <= 1 per changed piece; busy < 35 % | short reply: 2 hitches, worst 82 ms, stall 63 ms (1x) | 33 hitches, worst 110 ms, stall max 84 ms, busy 28 % (was 113 / 766 / 498 / 70 %) | run to run +-30 % |
| 3 Typing (focus, 20 chars, 20 deletes) | hitches, worst, stall max | per key stall <= 20 ms; `ChatScreen` body 0/key | 14 [13..17], 314 ms [313..357], 330 ms | 14 [12..20], 360 ms [343..367], 373 ms | first focus (~340 ms) dominates |
| 3b Typing steady state (composer already focused) | stall per key | <= 20 ms | max 20 ms over 16 keys (1x); was 18..25 | 22 ms max | AXe types 2 to 3 keys/s |
| 4 First composer focus (keyboard) | main-thread stall | system floor | ~340..390 ms (floor F3) | 330..450 ms | 337 [337..449] |
| 5 Drawer open/close (`sidebar`, 3 to 12 motions) | hitches; settle stall; Sidebar/Composer bodies per motion | 0 bodies; settle stall <= 36 ms | 3 hitches, worst 33 ms, stall max 16 ms (3 motions) | 2 hitches in 12 motions; stall 11..30 ms (was 52..156) | +-1 hitch |
| 6 Long-chat open (65 000 pt restore, 16-turn window) | largest stall; markdown bodies; blank | median ~0.7 s, no outlier > 1 s, no blank | 670 / 830 / 670 / 513 / 523 ms (5 launches); bodies 53 / 95 / 53 / 53 / 53 | 1105 ms (pass 2); 806 / 789 / 1998 ms before pass 11 | floor = cold render F2 |
| 7 Rich media first scroll (8 steps over cards) | hitches; stall max | first scroll <= 30 ms; no layout shift | 1 hitch, 27.7 ms (1x, after prewarm); before 5 [5..5], 41 ms [41..47] | 5 [3..6], worst 99 ms [60..106], stall 64 ms [45..77] | +-2 hitches |
| 8 New session open (sidebar open first, AX warm) | hitches; stall | 1 hitch, <= 20 ms | 1 hitch, 17.7 ms; open+focus ~337 ms (system) | n/a | AX absorbs +100..140 ms |
| 9 Dynamic type / appearance (`extra.sh`) | worst frame | no new regression | n/a | ax5 143.8 ms, xs 101.9 ms, m 39.5 ms; light 40.8 ms, dark 39.2 ms (1x) | first text-size change 100..140 ms relayout |
| 10 Media cards scroll | hitches; stall | stall <= 30 ms | n/a | 4 hitches, worst 40.0 ms, stall 23.1 ms (1x) | |
| Any user action | main-thread stall from an action the user did not ask for | none > 8 ms | | | |

Other baselines: tap window after an AX warm-up < 28 ms (was 117..140); `perf.hot samples=6` for the new-session open; code highlight cold 88 ms (Debug) now warmed off main.

## Reading a verdict
`VERDICT windows= frames= hitches= dropped= longest-gap= worst-frame= stalls>8ms= stall-max= busy-avg= scroll-frames=` sums the printed windows.
- `windows=0` on an idle scenario is the good answer. Compare **medians of 3 cold runs** (`repeat.sh`) with the baseline above.
- A difference counts only if it is larger than the run-to-run range of the baseline; inside the range = "no change".
- Worse than baseline by more than the range = regression: fix it. Raising the baseline is BLOCKED; a regression you cannot fix goes to the lead as `ESCALATE:`.
- A hitch is a frame later than 1.5 budgets; a stall is a main-thread wake over 8 ms (`stall8`, `smax`). One-frame budgets are not sign-off-able on the simulator; stalls and counts are.

## The measurement rule (10 lines)
1. A single run is an anecdote; report median and range of at least 3 cold launches. 2. Same script, same chat, same window length, 8 s settle so the app-start window is excluded.
3. Measure the idle floor on the same build (`repeat.sh idle "wait 12"`) and read everything against it. 4. Release is the verdict; Debug is for counts and ratios.
5. Never compare numbers from different scripts (one with the keyboard appearing, one without made Release look 8x worse). 6. Absorb the AXe warm-up with `ui reading` first.
7. Say so when steps are sent faster than the app can take them (AXe types 2 to 3 keys/s). 8. The sampler and probes change timing: they find causes, never take numbers.
9. Fix first, measure to prove: single runs while iterating, 3 runs to confirm. 10. A fix without its before -> after is a guess (`W1: <what> (<before> -> <after>)`).
