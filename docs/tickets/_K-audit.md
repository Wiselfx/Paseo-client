# K-round — whole-app defect audit (2026-11-12)

The user's verdict on IPA `2adbc1c`: many areas still do not work, things that should work do not,
and the app lacks polish. Earlier rounds fixed what the user happened to report. This round finds
the rest **by tracing every user flow end to end in the code**, before anyone fixes anything.

You are one of five auditors. **Read-only: you change no Swift file.** Your only output is one
report, `docs/audits/K-<your area>.md`, committed on your branch (`k-audit-<area>`, message
`K-audit <area>: report`). Do not push, merge or rebase.

Read first: `ARCHITECTURE.md`, `AGENTS.md`, `docs/UX-SPEC.md`, the rows of `docs/PARITY.md` for
your area. Upstream reference (the app this client must match in behaviour) is the clean clone at
`/home/paseo/dev/paseo-upstream-ref` (`packages/app/src`, `packages/server`, `packages/protocol`).
Never open any other reference directory. Never send to, prompt or probe a `claude`-provider agent.

## Method (per flow, no shortcuts)

For every user-visible control and flow in your area:

1. Start at the view: what does the tap/gesture call? Follow it through the controller, the store
   (`Packages/PaseoCore/Sources/PaseoStore`), the request in `PaseoProtocol`, to the wire.
2. Compare the request and the handling of the response with upstream (message name, fields,
   optionality, error path, capability gating). Upstream is the truth for wire semantics.
3. Follow the result back: does the store update, does the view observe it, does an error reach
   the user, does a loading state end on every path (success, error, timeout, disconnect)?
4. Look for the classes of defect below. Record only what you **verified by reading the code** —
   cite `file:line` for every link in the chain that proves it. If you only suspect, put it under
   "Unverified suspicions" with what would confirm it. No invented findings; "no findings" for a
   flow is a valid, useful result — list the flows you cleared.

Defect classes:
- **Dead**: a control that does nothing, a callback never wired, an action sent to a store method
  that is a stub, a result nobody observes, a sheet that can't be reached or can't be dismissed.
- **Wrong**: request shape differs from upstream, a response field misread, wrong capability gate,
  state never reset, an error swallowed, a spinner that never ends, stale data after reconnect.
- **Fragile**: hit targets under 44 pt or outside a hit-testable frame (overlays pushed out of
  `safeAreaBar`/`toolbar` hosts), unframed flexible shapes in stacks, layout that jumps when data
  arrives, `.task` work that should be seeded in the first body pass, gesture conflicts.
- **Slow**: more than O(1) per frame/keystroke/stream token, main-actor file reads or decodes,
  observation wider than what the view draws (R-1), rows that are not equatable values (R-2).
- **Unpolished**: missing empty/loading/error states, inconsistent spacing or type against
  `docs/UX-SPEC.md` and sibling screens, missing haptics/motion where siblings have them, a
  non-token literal, missing accessibility label, copy that differs from upstream `en.ts`.
- **Custom faces**: the Anthropic sans and serif files are single static Regular faces, so
  `.weight()`/`.italic()` on them do nothing. Flag places where the design clearly depends on a
  weight that cannot render (a title that must read as a title), not every call site.

## Report format

```
# K-audit <area>
## Flows traced            (table: flow · entry file:line · verdict ok/defect IDs)
## Defects                 (one per heading)
### <area>-NN  <one-line symptom as the user would see it>   [P0 broken | P1 wrong | P2 polish]
Proof: file:line → file:line → … (the chain)
Root cause: one or two sentences.
Fix: exact change (which file, what code), size S/M/L, and any Apple API you are not sure of.
## Unverified suspicions
## Needs a device to judge
```

Order defects by severity. P0 = a feature the user would call "doesn't work". Be exhaustive on P0
and P1; for P2 report patterns once with all sites listed, not one finding per site.

## Areas

| Area | Scope (under `Packages/PaseoUI/Sources/PaseoUI/` + the stores they use) |
|---|---|
| `conversation` | `Conversation/Screen`, `Composer`, `Turn`, `Sheets`, `Transcript`: send/queue/stop, attachments, dictation, slash commands and mentions, model/mode/thinking pickers, permissions and questions, turn actions (copy, rewind, fork, retry), subagents, context sheet, outline, tool-call rows and their detail |
| `workspace` | `Workspace/`: panel, files tree + file viewer, changes + diff + git actions (commit, push, PR, stash, branches), terminals |
| `shell` | `Shell/`, `Sidebar/`, `Draft/`, `History/`, `Schedules/`: drawers, workspace/agent lists, command center, new agent/draft flow, archive/rename/delete, history, schedules CRUD |
| `host` | `Settings/`, `Pairing/`, `Onboarding/`, `Notifications/`, `Voice/`, `App/`, plus `PaseoKit` connection: pair, connect, reconnect/resume after background, relay, host chooser, every settings page, notifications, voice mode |
| `polish` | every screen: tokens, type hierarchy, spacing rhythm, empty/loading/error states, haptics, motion, accessibility, layout stability, against `docs/UX-SPEC.md`; plus `DesignSystem/` components that are duplicated instead of shared (R-5) |
