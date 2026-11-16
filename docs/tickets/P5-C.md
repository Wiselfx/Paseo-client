# P5-C: sidebar derivation and laziness

Branch: `p5-c` from `foundation`. Read `docs/perf/overall-perf.md` (Batch C in section 4 and the findings it lists) first.

## Goal
Implement the fixes for Batch C exactly as the report describes, touching only the files that batch lists. Precompute workspace->agents and activity dates once, LazyVStack, skip collapsed content.

## Rules
Follow `AGENTS.md`. Preserve behaviour and upstream wording; no visual changes. Keep every existing test green; add tests for new logic (PaseoCore). PaseoUI cannot compile here: be conservative with Apple API use, re-read your code for labels and types. Commit on the branch as `P5-C: sidebar derivation and laziness`; do not push or merge. No background tasks or subagents. Final message: what changed per finding, tests summary, anything skipped or unsure.
