# P6-F: chat view, transcript, rail motion

Branch `p6-f` from `foundation`. Read `docs/perf/overall-perf.md` (Batch F, findings #11, #13, #15, #18, #23, #24; plus the P5-B note: `localImageLoader` closure identity, finding #13, must become a stable value per (session, workspaceId)) and `docs/perf/dsh-delta.md` (section 1 and the action list, items 2 and 3).

## Goal
1. Batch F perf findings as the report describes, touching only that batch's files.
2. Prompt jump motion (`ChatTranscript.jumpToTurn`): glide-lead. When the target is far, jump instantly to ~480 pt before it, then glide the rest with a smooth ease (~0.3 s); short distances just glide; Reduce Motion jumps without animation. Add a landing line: 2 pt line in `ClaudePalette.ink` (not orange) over the landed turn's first row, fading in/out over ~1.4 s (omit animation under Reduce Motion). Keep `ChatTurnRail.swift` behaviour as is except what you need to expose.
3. Per-frame cost in `onScrollGeometryChange`: O(1) reading-position report (only write `promptOutline.reportReadingPosition` when the anchor changes), and don't create a new Task per frame in `revealTurnRail()` (reuse a timestamp / debounce).

## Rules
Follow `AGENTS.md`. No visual changes beyond item 2. PaseoUI cannot compile here: re-read types and labels carefully, avoid recursive opaque types, run `swiftc -parse` on changed files. Add PaseoCore tests for any Core logic. Commit as `P6-F: ...`; do not push. No background tasks or subagents. Final message: per-finding summary, tests, what you skipped or are unsure about.
