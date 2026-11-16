# FINAL-CHECK: the mandatory last step for any change in Packages/PaseoUI, Packages/PaseoCore or App/

`final-check.sh` is a small, reliable test, not an oracle. It **guarantees** only block 1 (AUTO-VERIFIED: exact patterns
on your changed lines, plus the style-lint ratchet). It **never claims** anything about timing or semantics: blocks 3 and 4
are yours. Check ids, rules and the heuristic table: [CHECKS.md](CHECKS.md).

## Read this, in this order (the script prints the same list for your diff as block 0)
1. This file: the procedure, ESCALATE/BLOCKED and the three verdicts (1 minute).
2. [MUST.md](MUST.md) section B, **only the lines block 0 names**. Keep section A open while you code.
3. The one to three [PATTERNS](PATTERNS/) files block 0 names (chosen from the paths in your diff).
Everything else is reference, open only when a check fires: [CHECKS.md](CHECKS.md), [MANUAL.md](MANUAL.md),
[RULES.md](RULES.md), [DECISIONS.md](DECISIONS.md), [CATALOG.md](CATALOG.md), [BUDGETS.md](BUDGETS.md), [GLOSSARY.md](GLOSSARY.md).

## Steps
0. Commit or stage, then `Performance/scripts/final-check.sh [base-ref]`. The base is the branch's upstream, else
   `origin/main`, else `foundation`; the script prints the ref and the merge-base it used. On a branch with no upstream,
   pass the branch you forked from.
1. **Block 2 (AUTO-FAILED) must be empty.** Fix each hit with the PATTERNS file it names. No waivers.
2. **Blocks 3 and 4 (MANUAL)**: answer every `[ ]` from your diff. "No" or "unsure" -> do the item's "if no or unsure" line.
   Every item that applies to the changed paths or features is printed, or named on a `NOT SHOWN for this diff: Mxx
   (relevant to <path>)` line; nothing is silently omitted. An added test file counts as a test change (H28 stays quiet)
   and never makes `measure: REQUIRED`.
3. **Evidence**: if the last line says `measure: REQUIRED`, follow [MEASURE.md](MEASURE.md). If you cannot measure, record
   `unmeasured, handed to manager` with a complexity argument, a bound and a test; M40 accepts that state.
4. Tick block 4, save it, and get the verdict:
   `Performance/scripts/final-check.sh [base-ref] --signoff <file>`.

## ESCALATE and BLOCKED (one rule, every doc)
- **ESCALATE** = a decision that is not yours. Write every part a pattern covers; leave the part that needs the decision in
  its safest form, or unwritten; add one line to the sign-off:
  `ESCALATE: <what needs deciding> — <why> — <what you did>`. You do not wait for an answer: the lead answers in review.
- **BLOCKED** = you may not write it at all. Report `BLOCKED: <what> — <why>` and stop that part of the work.
- Escalate, do not block: a MANUAL "no" you cannot fix with its stated action; a new bounded cache/store (state its count
  AND cost bound); transcript/composer/shell code changed through a listed pattern; a `perf-ok:` waiver on an AUTO check.
- Block, do not escalate: changing `windowSize`/`windowStep`, the open re-seat's end condition, the roots assignment,
  keyboard behaviour or the hosting container; an unbounded structure; deleting or weakening a check or a test; raising a
  baseline, budget or bound; a visible look/copy/token change you were not asked for.

## Verdicts (exact strings; the script prints one of them)
- `VERDICT: DONE` — block 2 empty; every sign-off line ticked with a one-clause reason; no escalations; measure satisfied
  (numbers, or `unmeasured, handed to manager` per MEASURE.md).
- `VERDICT: DONE WITH ESCALATIONS (<k>)` — the same, with k `ESCALATE:` lines for the lead. Merge waits on those answers.
- `VERDICT: NOT DONE (<reason>)` — block 2 not empty, a line neither ticked nor escalated, or no sign-off supplied.

`--signoff <file>` parses the pasted block and prints exactly one of these. Without a sign-off the script prints NOT DONE,
because DONE is only claimable from a complete sign-off.

## What you may decide alone / what needs the lead
| You may decide alone | ESCALATE (write + flag) | BLOCKED (do not write) |
| --- | --- | --- |
| Fix an AUTO hit with the named pattern | A MANUAL "no" you cannot fix with its action | Any visible behaviour, copy or look change |
| Answer a MANUAL "yes" with a reason from your diff | A new cache/stream/store, with its count AND cost bound | An unbounded structure or an unstated bound |
| Add an `Equatable` row, a `static let`, a compare-before-write, a test | Transcript/composer/shell/keyboard code beyond a pattern | Removing or weakening a check, a test, a rule |
| Remove a probe, a `print`, a force unwrap | A `perf-ok:` waiver on an AUTO check | Any baseline/budget/bound increase |
| Pick a documented option from [DECISION-TREES.md](DECISION-TREES.md) | Retrying a [DECISIONS.md](DECISIONS.md) item with new evidence | Changing windowSize/windowStep, the re-seat end, the roots, keyboard or hosting |

## Modes
`final-check.sh [base]` (check the diff) · `--read` (only block 0: what to read for this diff) ·
`--signoff <file>` (verdict from a ticked block 4) · `--files F...` (whole files, no git diff) ·
`--self-test` (every check on its fixtures; CI runs it).
