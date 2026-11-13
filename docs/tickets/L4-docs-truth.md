# L4 — Make our own docs tell the truth

Read `_L-common.md` first. Branch: `l4-docs`. Commit messages start with `L4:`. Docs only: no Swift file.

Findings: `/home/paseo/dev/docs-audit/findings/` — `LEDGER.md` D-033, D-034, D-035, `REVIEW.md`; and
`/home/paseo/dev/bighelp-study/findings/review-SUMMARY.md` item 12.

## You own
`docs/PARITY.md`, `ARCHITECTURE.md`, `Packages/PaseoUI/docs/TESTING.md`, `docs/UX-SPEC.md`,
`docs/perf/overall-perf.md`. Nothing else.

## Steps (verify each claim in code BEFORE editing; cite the code in your commit body)
1. `docs/PARITY.md` line ~303: says the branch switcher is "store only (no UI)". The UI exists:
   `WorkspaceBranchSwitcherSheet` is wired at `Packages/PaseoUI/Sources/PaseoUI/Workspace/WorkspaceChangesView.swift:172`
   (grep it to confirm). Change the status to `done` and point at the file.
2. PARITY.md lines ~158 and ~505 call "Retract this message" and "Delete this turn" `missing`. The product
   decision (this round) is **retired, upstream has neither** (`/home/paseo/dev/paseo-upstream-ref` has no such
   gesture: confirm with `grep -rni "retract" packages/app/src --include=*.ts --include=*.tsx | head`). Rewrite
   those rows as `not applicable (upstream has no equivalent; removed)`. Rewind: one row, status `done`,
   "in place, `agent.rewind`" with the upstream reference `packages/app/src/components/rewind/rewind-menu.tsx`.
3. PARITY.md line ~51 says "done" for host switching while the same row says "no All hosts filter":
   split into two rows so the counts don't overstate. Then re-count the `## Counts` section at the bottom
   by actually counting `Status:` values with grep; replace the numbers (show your grep in the commit body).
4. Add a PARITY.md row: **"One host per daemon: relay + direct connections merged"** status `in flight (L2)`;
   **"Background push notifications"** status `blocked: daemon push is Expo-token only
   (packages/server/src/server/push/push-service.ts)`.
5. `ARCHITECTURE.md`: the "no version map" statement is at ~line 173 not 156-165 (the reviewer's note); read
   D-034 in the ledger and fix every stale statement it lists, each verified against code. Also add a short
   section **"Upstream first"** pointing to `AGENTS.md` R-7 and `docs/tickets/_L-common.md`.
6. `Packages/PaseoUI/docs/TESTING.md` line 3 claims four suites and CI checks that do not exist (the old UI
   suite was removed in M1). Rewrite it to say what exists today: PaseoCore `swift test` (run in CI by
   `.github/workflows/ci.yml`), the Mac build gate (`Tools/build-gate/build-gate`), and the planned
   `PaseoUITests` target (not yet created). Verify the CI claim by reading `ci.yml`.
7. `docs/UX-SPEC.md` line ~21 names `ClaudePalette`, which no longer exists (grep to confirm; the token is
   `Palette`). Fix the name wherever it appears in that file.
8. `docs/perf/overall-perf.md`: findings #18 and #27 describe code that has since been fixed; #1 is half fixed
   (the 16 ms commit coalescer exists at `Packages/PaseoCore/Sources/PaseoStore/HostSession.swift:1211-1221`; the
   `.unbounded` streams at `Packages/PaseoCore/Sources/PaseoKit/DaemonConnection.swift:76,81` remain). Open
   each, verify against current code, and mark each finding `fixed (commit/file)` or `open`. Check #2–#5 and
   #8 the same way (the reviewer suspected they are stale too).

## Proof
For every changed line, the commit body lists the code location you verified it against. `git diff --stat`
shows only the five files. No Swift file touched.
