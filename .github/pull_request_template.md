## What and why

## Checklist (UI and store changes)

- [ ] `Tools/style-lint/check.sh` passes (R-4 tokens, R-8 performance rules). A new exception needs a reason here and an updated `Tools/style-lint/baseline.txt`.
- [ ] I read `docs/perf/PERFORMANCE-RULES.md` and nothing I touched breaks a numbered rule (no work in `body`, narrow observation, equatable rows, stable identity, no main-thread IO/decode, bounded caches).
- [ ] New or changed hot paths (scroll, streaming, typing, open, drawer, media) were run with `-paseo-perf` using `docs/perf/HOWTO.md`; before/after numbers are below, or this change cannot affect them.
- [ ] Core logic has tests (`swift test` in `Packages/PaseoCore`).
- [ ] No behaviour, copy or look changed unless this PR says so.

## Performance evidence (if applicable)
