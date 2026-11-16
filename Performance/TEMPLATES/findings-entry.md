# Findings entry (append to docs/perf/W1-findings.md and add a row to Performance/CATALOG.md)

```text
| <id> | <Where> | <How found: scenario + the window line / counter that showed it> | <Cause, one sentence, with the evidence: sampled stack, _printChanges key path, body counts> | <Fix commit> <what> | <before -> after, Release median [range], 3 cold runs> |
```
Also: add the numbered rule to Performance/RULES.md (requirement, WHY with the number, CHECK, FIX) and a MUST.md line if it is a new imperative; if it is greppable add a check to
`scripts/fc_checks.py` with a bad and a good fixture line (the self-test requires both); if it is testable on Linux add a Core test in a new file.
If you tried something that did not work, record it in DECISIONS.md with the number and the reason (so nobody retries it).
