# P5-D: workspace panel unmount when closed

Branch: `p5-d` from `foundation`. Read `docs/perf/overall-perf.md` (Batch D in section 4 and the findings it lists) first.

## Goal
Implement the fixes for Batch D exactly as the report describes, touching only the files that batch lists. Gate on progress > 0, unmount page content when closed, detach terminals/diff subscriptions, load checkout lazily.

## Rules
Follow `AGENTS.md`. Preserve behaviour and upstream wording; no visual changes. Keep every existing test green; add tests for new logic (PaseoCore). PaseoUI cannot compile here: be conservative with Apple API use, re-read your code for labels and types. Commit on the branch as `P5-D: workspace panel unmount when closed`; do not push or merge. No background tasks or subagents. Final message: what changed per finding, tests summary, anything skipped or unsure.
