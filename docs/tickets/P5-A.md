# P5-A: streaming pipeline coalescing

Branch: `p5-a` from `foundation`. Read `docs/perf/overall-perf.md` (Batch A in section 4 and the findings it lists) first.

## Goal
Implement the fixes for Batch A exactly as the report describes, touching only the files that batch lists. Coalesce agent_stream commits to one per display frame (keep full text in the store), bufferingNewest on the connection stream, avoid whole-array memcmp and prefix copy in IncrementalTurnBuilder, cache latestPromptSeq. Linux-testable.

## Rules
Follow `AGENTS.md`. Preserve behaviour and upstream wording; no visual changes. Keep every existing test green; add tests for new logic (PaseoCore). PaseoUI cannot compile here: be conservative with Apple API use, re-read your code for labels and types. Commit on the branch as `P5-A: streaming pipeline coalescing`; do not push or merge. No background tasks or subagents. Final message: what changed per finding, tests summary, anything skipped or unsure.
