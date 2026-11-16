# P7-OCU: Open Claude UI style pass (experimental branch)

Branch `ocu-ui` from `foundation`. Never merged without the user's per-group approval. Source: `docs/perf/ocu-spec.md` (read §0 confidence key, §12 ranked changes, §13 UNTRUSTED first). Our UX truth: `docs/UX-SPEC.md` (read §0 and any section you touch); where the two conflict on structure or behaviour, UX-SPEC wins.

## Goal
Apply the ocu-spec §12 items as **separate commits, one per group**, in this order, each independently revertible (no commit depends on a later one):
1. `OCU 1/4 spec conflicts`: SheetHeader close circle to 30 pt (UX-SPEC §0.3); StatusLine spring to the critically damped rule (§0.4); leave the user bubble at 14 pt (undecided: list it in your final message).
2. `OCU 2/4 motion`: items 17-23, 27-30, 40 of §12 that map to SwiftUI (duration/easing tokens, message enter fade-up without scale, status enter/exit, copy decay 2.5 s, skeleton/progress only if an existing view needs it). Skip items needing new screens.
3. `OCU 3/4 shape`: items 7-16, 31-32, 35-37 (radii 12/18, bubble padding, control row 44 pt, code radius 12, tabular numbers). Do NOT change the composer radius if it conflicts with the V5 composer spec in UX-SPEC §4.1: report instead.
4. `OCU 4/4 palette`: items 1-6 (text, surfaces, borders; accent/brand pair only if used). Put the new values behind the existing `ClaudePalette` tokens so a revert of this single commit restores the old look.

Never adopt anything listed under UNTRUSTED (§13), never use orange for state (UX-SPEC §0.1), no desktop/web-only items (§14), no invented copy.

## Rules
Follow `AGENTS.md`. PaseoUI cannot compile here: re-read types and labels, avoid recursive opaque types (use `AnyView` at recursion points), `swiftc -parse` changed files. Commit each group as named above; do not push. No background tasks or subagents. Final message: per group, which §12 items you applied, which you skipped and why, and the before/after values.
