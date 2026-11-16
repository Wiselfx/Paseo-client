# Performance rules (R-8): moved

The rules, budgets and the measurement rule now live in `Performance/` (the performance framework). This file is kept so old links and
`Tools/style-lint` messages still resolve; it does not restate them, so nothing here can contradict the framework.

- Rules PF-1 to PF-41 (ids 1 to 27 are the numbers this file used; 28 to 41 are new): `Performance/RULES.md`
- Budgets, baselines, how to read a verdict, the measurement rule: `Performance/BUDGETS.md`
- How to measure (scripts, environment, traps): `Performance/MEASURE.md`; the instrument manual stays `docs/perf/HOWTO.md`
- Every jank found and its fix: `Performance/CATALOG.md` (raw history: `docs/perf/W1-findings.md`)
- Rejected options and floors: `Performance/DECISIONS.md`
- What to run and tick before you report done: `Performance/FINAL-CHECK.md` and `Performance/scripts/final-check.sh`

`Tools/style-lint/check.sh` (the `perf-*` ratchet against `baseline.txt`) is run by `final-check.sh` as check S0.
