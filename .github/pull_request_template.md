## What and why

## Checklist (UI and store changes)

- [ ] `Performance/scripts/final-check.sh` run: AUTO-FAILED is empty and the SIGN-OFF block (every MANUAL line ticked with a reason, or `ESCALATE:`) is pasted below. `Performance/MUST.md` was open while coding.
- [ ] `Tools/style-lint/check.sh` passes (R-4 tokens, `perf-*` rules; final-check runs it as S0). A new exception needs a reason here and an updated `Tools/style-lint/baseline.txt`, and is an escalation.
- [ ] Hot paths (transcript, composer, shell, sidebar, media, stores, launch): measured per `Performance/MEASURE.md` (Release, 3 cold runs, median and range), before and after below; or `final-check` printed `measure: not required`.
- [ ] Core logic has tests (`swift test` in `Packages/PaseoCore`); a store write path has a write-on-change test; a cache has a bound test.
- [ ] No behaviour, copy or look changed unless this PR says so. No rejected option retried (`Performance/DECISIONS.md`).

## Performance evidence (Performance/TEMPLATES/evidence-block.md)
