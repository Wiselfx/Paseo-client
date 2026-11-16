# AGENT-PROMPT: paste this block into any task prompt for a small agent

```text
PERFORMANCE REQUIREMENT (applies to every change in Packages/PaseoUI, Packages/PaseoCore or App/)
Intent: the app must feel instant. Idle is silent, scrolling and typing never hitch, and the main thread never finishes a
frame later than its commit deadline (8.3 ms at 120 Hz, 16.7 ms at 60 Hz).
Before your first edit: run `Performance/scripts/final-check.sh --read`. It prints the 3 files that matter for the paths you
are touching (FINAL-CHECK.md, the MUST lines, one or two PATTERNS). Keep Performance/MUST.md section A and B open while you
write. Do not guess: if DECISION-TREES.md has an entry for what you are adding, follow it step by step.
Before you report done, in this order:
1. Commit or stage your work, then run: Performance/scripts/final-check.sh [base]
   (no base = the branch's upstream, else origin/main; the script prints which ref and merge-base it used).
2. Block 2 (AUTO-FAILED) must be empty. Fix each hit with the PATTERNS file it names. No waivers.
3. Blocks 3 and 4 (MANUAL) list every item that applies to your paths. Answer each [ ] line with one clause from your diff;
   on "no" or "unsure" do what the item says.
4. If the last line says "measure: REQUIRED", follow Performance/MEASURE.md and paste the evidence block
   (Performance/TEMPLATES/evidence-block.md). No gate? Record `unmeasured, handed to manager` with the complexity argument,
   the bound and the test (MEASURE.md); never invent numbers.
5. Re-read MUST.md section A and D. ESCALATE = write the parts a pattern covers, flag the decision, keep going:
   `ESCALATE: <what> — <why> — <what you did>`. BLOCKED = do not write it at all (windowSize/windowStep, the re-seat end,
   the roots, keyboard/hosting, an unbounded cache, deleting a test, raising a baseline, a visible look/copy change).
Paste into your final message: the SIGN-OFF block with every line ticked [x] plus one clause why (or ESCALATE: why), then
`Performance/scripts/final-check.sh [base] --signoff <file>`, which prints exactly one of
`VERDICT: DONE`, `VERDICT: DONE WITH ESCALATIONS (k)`, `VERDICT: NOT DONE (reason)`. Do not claim a check passed unless you ran it.
```
Procedure, ESCALATE/BLOCKED and the verdicts: [FINAL-CHECK.md](FINAL-CHECK.md). Check ids: [CHECKS.md](CHECKS.md).
