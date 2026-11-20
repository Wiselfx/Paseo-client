## What and why

## Checklist (UI and store changes)

- [ ] `Tools/style-lint/check.sh` passes (R-4 tokens). A new exception needs a reason here and an updated `Tools/style-lint/baseline.txt`.
- [ ] Core logic has tests (`swift test` in `Packages/PaseoCore`); a store write path has a write-on-change test; a cache has a bound test.
- [ ] No behaviour, copy or look changed unless this PR says so.
