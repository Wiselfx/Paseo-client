# Worker scorecard

Terse verdicts per worker, grouped by harness + model. A "lead catch" is a defect the lead found in
review that the worker's own report didn't flag. Add a row per ticket; compare harnesses by the
averages.

## OMP · `opencode-go/deepseek-v4.1-flash` (mode full, thinking high)

| Ticket | Grade | Root causes | Lead catches | Rounds | Notes |
|---|---|---|---|---|---|
| E1 composer + voice | A− | Correct: dead `@FocusState`, a Canvas not tied to the tick, missing AEC | 0 | 1 (+1 lead-decided tweak in E1b) | A thorough upstream trace. Over-engineered the focus bridge (`pendingEcho`), but correct. Honest about what it couldn't verify. |
| E2 look + launch | B | Correct: scrim, `EmptyMain` hugging, the `List` height, the inset double-count | 2 (the back-to-end button over the subagent pill; a `UIColor !=` per update in the terminal) | 2 + lead fixes | Wide scope, handled well; good shadow path. Its report answered a "§13 focus mode" that was never asked (the brief stopped at §12). On the merits it was correct and harmless: focus mode is desktop-only (`PARITY.md:445`), no code exists for it, and it changed nothing. Not a defect, just a phantom line in the report. 2 other issues were the lead's own ticket mistakes, not counted. |
| E3 subagents + rich media | B− | Excellent: a live probe found the `projected_subagent_timeline` root cause; a per-provider capability table | 4 (isolation warnings; a per-card viewport reader → uncapped first frame; yield+`scrollTo` flash; caps resizing with the keyboard) | 3 | Best diagnostician, weakest layout-stability instincts. **Incident:** its probe sent a message into the user's Claude session (led to the "never touch Claude agents" rule). |

**Harness average:** B. Strong at diagnosis and following tickets. Misses layout-stability and
per-frame cost unless the ticket spells them out. Needs a strict reviewer.

## Claude Code subagent · Opus (general-purpose, Agent tool)

| Ticket | Grade | Notes |
|---|---|---|
| UX research (doc 14) | B+ | A good, opinionated plan with real sources. Overran the length cap. Blocked twice by a safety classifier and couldn't recover, so the lead wrote §8–15; the user rescued its draft. |

## Pi · (next round)

| Ticket | Grade | Root causes | Lead catches | Rounds | Notes |
|---|---|---|---|---|---|
