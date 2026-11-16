# Decisions: calls made, options rejected, floors, open follow-ups

Do not retry a rejected option without new evidence, escalated to the lead (check C44 guards the greppable ones). Raw: [W1-findings](../docs/perf/W1-findings.md).

## Rejected (measured, reverted or not shipped)
| Id | Option | Result and reason |
| --- | --- | --- |
| D01 | Turn window 8/8 instead of 16/12 (`39377c2`, reverted `b1887fe`) | some opens 2.5 to 4 s: more re-seat passes. |
| D02 | Mount the sidebar 2 s after the shell (`dc859fc`, reverted `92f59cc`) | first window cheaper (452/514 vs 548..812 ms) but a 200 ms to 1 s stall moved to 2..4 s after launch, onto the first tap. A cost moved to a random later moment is not a fix. |
| D03 | Throwaway text field focused at chat open to prewarm the keyboard (`c1cc99f`, reverted `76c8d9b`) | first focus unchanged (337 ms): the cost is SwiftUI/UIKit metadata and layout, not the keyboard process. |
| D04 | `NLTagger`/`NLLanguageRecognizer` warm-up off main (`e175ca9`, reverted `702f162`) | no effect on the first keyboard. |
| D05 | `shouldRasterize` on the sliding drawer | visual risk; never shipped. |
| D06 | `scrollTo(edge: .bottom)` for the open re-seat | targets the estimated bottom: dozens of rows realised (content 33k..48k pt); use `scrollTo(id: "bottom")`. |
| D07 | Programmatic jump of tens of thousands of points in a lazy stack (find step `64605f6`, outline glide `ed90b93`) | lands blank until a real scroll event; reverted to the original path. Needs a window around the target. |
| D08 | `.id` on streaming content | whole subtree rebuilt per token (J02). |
| D09 | `GeometryReader` per row/card | replaced by `onGeometryChange` (J24). |
| D10 | `Binding(get: store.x)` built in a parent body | makes the parent depend on x (J14). |
| D11 | Sampler or per-hit instrument checks for numbers | `-paseo-perf-sample` suspends main ~1000x/s and shifted layout; use it to find a cause, never to time. |
| D12 | Ending the open re-seat on "only the insets moved" (`ec862cb`) or on a timer (`5590b73` removed) | blank long chat with a tall draft (J12); ended at an estimated end. |
| D13 | Swapping the text engine for the open cost (pass 8.1) | shipped for layout reasons, but open stayed 0.8..1.1 s: not the dominant cost. |
| D14 | Memoising text size without a way to check it (pass 4) | shipped only with a real-layout re-check in perf mode (`fit.MISMATCH` = 0). |

## Calls made (the reasons)
- Release is the verdict; Debug counts and ratios carry over, milliseconds do not (typing and scroll medians were equal within range).
- Fix first, measure to prove: read the hot path source end to end, one sampled run to name a cause, then one run per fix; 3 cold runs to confirm.
- `-paseo-perf-sample` names stalls (`perf.hot`, `perf.stack`); `-paseo-perf-changes` (`_printChanges`) names invalidations. Neither gives numbers.
- Keep `PaseoPerf.body`/`measure` on hot paths (free when off); remove `diff`/probes when the cause is found.
- Same chat, same script, app-start window excluded, idle floor on the same build; compare only inside one script.

## Floors we cannot beat (recognise them, do not chase them)
| Id | Floor | How to recognise it |
| --- | --- | --- |
| F1 | Simulator noise: 60 Hz only, shared GPU; one-frame hitches cannot be signed off | idle Release prints nothing, but a window right after another scenario shows its tail; read stalls and counts |
| F2 | Cold SwiftUI type reflection: ~550..800 ms at app start (shell, sidebar, composer, chat created cold); first ~50 markdown bodies ~560 ms | `swift_conformsToProtocol...` under `DynamicPropertyCache.fields` / `makeViewList`; fewer distinct view types and fewer wrappers per row is the only lever |
| F3 | First system keyboard show ~340..390 ms (Release sim): UIKit keyboard views, render server, IOSurface, `RBSAssertion` XPC, key-command walk | present with AX warm; no invisible prewarm exists |
| F4 | First AXe interaction +100..140 ms (`AXValidationManager`, `AXCoreUtilities`) | gone after a throwaway `ui reading`; a phone with VoiceOver off pays none |

## Open follow-ups (found, not done)
1. Pre-size rows from remembered turn heights (per turn id, width, Dynamic Type, text hash; persisted) so the first content estimate is right and the re-seat converges in one pass.
2. Flatten markdown views (hoist `sheet`/`onGeometryChange`/`openURL` per message, not per piece) and the sidebar's view types: needs before/after screenshots at several Dynamic Type sizes.
3. Both daemon event streams are `.unbounded`; `outlineItems`, `ChatFind` scans per query; `TimelineView(.animation)` for a sleeping crab; masked text sweeps; `.repeatForever` dots.
4. Find-in-chat to an off-screen row (needs a middle window around the match); the blank open reproduces ~1 launch in 3 on the simulator (device check).
5. Typing: per-key UIKit text layout and language identification; behaviour switches are an owner decision (visible change).
6. Release numbers for the W3 sweep (code-read only); per-view spans for the new-session open once AX is warm.
