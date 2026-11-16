# Performance framework

What the performance work taught us, as checks a small agent can run. `scripts/final-check.sh` guarantees only its AUTO-VERIFIED list (exact patterns on the
lines you changed) and never claims anything about timing or semantics; everything it cannot verify is a MANUAL question you answer from your diff.
Raw history stays in [docs/perf/](../docs/perf/) (W1 findings, HOWTO, scenarios). Binding rule: AGENTS.md R-8.

## Modes
| Mode | When | Open |
| --- | --- | --- |
| Before writing | you are about to add or change something | [DECISION-TREES.md](DECISION-TREES.md), [PATTERNS/](PATTERNS/) |
| While writing | all the time | [MUST.md](MUST.md) (one page, numbers + imperatives), [GLOSSARY.md](GLOSSARY.md) |
| After writing | before you report done: REQUIRED | `Performance/scripts/final-check.sh`, then [FINAL-CHECK.md](FINAL-CHECK.md) |
| Something is slow | a symptom, a hitch, a number | [CATALOG.md](CATALOG.md) (symptom -> cause), [MEASURE.md](MEASURE.md), [DECISIONS.md](DECISIONS.md) (do not retry) |

## The one command
```sh
Performance/scripts/final-check.sh [base-ref]     # AUTO-FAILED must be empty; tick every MANUAL line; paste the SIGN-OFF
Performance/scripts/final-check.sh --self-test    # proves each check fires on bad fixtures and stays silent on good ones (CI runs it)
```

## File map
| File | What |
| --- | --- |
| [AGENT-PROMPT.md](AGENT-PROMPT.md) | the block to paste into any small-agent task prompt |
| [MUST.md](MUST.md) / [MANUAL.md](MANUAL.md) | the MUST sheet (tagged AUTO/MANUAL) / the yes-no question and fallback for each MANUAL item |
| [FINAL-CHECK.md](FINAL-CHECK.md) | procedure, who decides what, the check tables |
| [RULES.md](RULES.md) | PF-1 to PF-41 with WHY, check, fix |
| [PATTERNS/](PATTERNS/) | 12 areas, BAD/GOOD from real repo code |
| [DECISION-TREES.md](DECISION-TREES.md) | "I am adding X" -> exact steps |
| [CATALOG.md](CATALOG.md) / [DECISIONS.md](DECISIONS.md) | every jank found / rejected options, floors, follow-ups |
| [BUDGETS.md](BUDGETS.md) / [MEASURE.md](MEASURE.md) | budgets and baselines / the cheapest evidence path |
| [TEMPLATES/](TEMPLATES/) | evidence block, instrumentation, tests, row, representable, cache, task, findings entry |
| `scripts/` | `final-check.sh`, `fc_checks.py` (engine), `fixtures/` (self-test) |
