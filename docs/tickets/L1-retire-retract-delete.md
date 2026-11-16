# L1 — Retire "Retract" and "Delete turn"; make sure Rewind matches upstream

Read `_L-common.md` first. Branch: `l1-rewind`. Commit messages start with `L1:`.
Findings: `/home/paseo/dev/docs-audit/findings/LEDGER.md` D-012; `REVIEW.md`.

## Decision (from the product owner, final)
- **Remove** "Retract this message" and "Delete this turn". Upstream has neither; both secretly fork a new
  agent (new id, new provider session, the old agent keeps running).
- **Keep** Fork exactly as it is (upstream's Fork is also a new agent, by design).
- **Keep and make complete** Rewind (upstream: in place, same agent). The owner needs it.

## You own (edit only these)
- `Packages/PaseoUI/Sources/PaseoUI/Conversation/Transcript/ChatTurns.swift`
- `Packages/PaseoUI/Sources/PaseoUI/Conversation/Screen/ChatController.swift` (only the functions named below)
- `Packages/PaseoUI/Sources/PaseoUI/Conversation/Turn/*.swift` (only the lines that mention retract/delete)
- `Packages/PaseoUI/Sources/PaseoUI/Conversation/Screen/RewindActions.swift` (find it with `find Packages -name RewindActions.swift`), and the rewind sheet/menu view files you find with `grep -rln "rewindChoices" Packages/PaseoUI`
- New test files only under `Packages/PaseoCore/Tests/` (for Core logic you touch).
Do NOT edit `docs/` (another worker owns docs) or `HostSession.swift`.

## Part A — remove Retract and Delete turn (do these steps in order)
1. Run: `grep -rn "retract\|deleteTurn\|onRetract\|onDeleteTurn\|canRetract\|cutRow" Packages App --include=*.swift` and write the list in your scratch notes.
2. In `ChatTurns.swift`: delete the properties `onDeleteTurn`, `onRetract`, `canRetract` (about lines 40-50) and the two arguments `onDeleteTurn:` and `onRetract:`/`canRetract:` passed in `TurnRow.body` (about lines 540-542). Keep `onFork`, `onForkInFlight`, `canForkWorkspace`.
3. In `ChatController.swift`: delete `actions.deleteTurn = …` and `actions.retract = …` (about lines 314-319) and the functions `retractMessage(userRow:)` and `deleteTurn(userRow:)` (about lines 913-930). Delete `actions.cutRow` ONLY if step 1 shows nothing else uses it; `fork` uses `row.seqEnd`, not `cutRow`.
4. Wherever the `ChatActions` struct is declared (`grep -rn "struct ChatActions" Packages`), delete the `deleteTurn` and `retract` members. If the declaring file is not in your Owns list, STOP and report instead of editing it (the lead will assign it).
5. In the turn footer/menu view (find it: `grep -rn "Delete this turn\|Retract this message" Packages`), delete the two menu items and any now-unused `@State`/helper. The menu must still show Fork and Rewind.
6. Check availability: `grep -rn "canForkAtBoundary" Packages`. Keep it (Fork uses it).
7. Run the step-1 grep again: zero hits for `retract|deleteTurn|onRetract|onDeleteTurn|canRetract` in `*.swift`. If hits remain in a file you do not own, list them.

## Part B — Rewind must match upstream (compare, then fix differences in your files)
Upstream rewind lives in `/home/paseo/dev/paseo-upstream-ref/packages/app/src/components/rewind/`:
`rewind-menu.tsx`, `use-rewind-capabilities.ts`, `rewind-mode.ts`, `use-rewind-agent-mutation.ts`,
`composer-restore.tsx`, and its use in `components/message.tsx` (grep `rewind`, ~line 427-540).
Open each file and answer these questions in your final message (one line each, with our `file:line`
and upstream `file:line`):
1. **Modes**: upstream offers `conversation`, `files`, `both`. Which does our menu offer?
   Gating: `use-rewind-capabilities.ts` shows each mode only when the agent's capability flag allows it.
   Ours: find `rewindChoices` and what produces it.
2. **Labels and warning text**: upstream uses i18n keys `rewind.tooltip`, `rewind.warning`,
   `rewind.actions.conversation|files|both` in `packages/app/src/i18n/resources/en.ts` (grep `rewind:`).
   Copy: our strings must be those exact English strings. List any difference and fix it.
3. **Where it shows**: upstream shows the rewind control on a user message (`message.tsx` ~line 533).
   Ours: which rows offer it? Same rule (user messages only, not while a rewind is pending)?
4. **Composer restore**: after rewind, upstream puts the rewound message text back into the composer
   (`composer-restore.tsx`, `composer-restore.test.ts`). Ours: look at `PendingMessageAction`/`.edit` in
   `ChatController.swift` (~line 870) and `store.rewind(toMessageId:scope:)`. Does the text land in the draft
   for modes that rewind the conversation? Match upstream's rule exactly (read the test file for the cases).
5. **Request**: upstream sends `RewindAgentRequest` (see `packages/protocol/src/messages.ts`, grep
   `agent.rewind` / `RewindAgent`) through `use-rewind-agent-mutation.ts`: note the fields and the error
   handling/toast. Compare with `Packages/PaseoCore/Sources/PaseoStore/RewindActions.swift` (the store side;
   do not edit it, report differences).
6. **While pending**: upstream locks the menu while a rewind is in flight and shows a pending state; ours
   has `rewindInFlight`. Same?
Fix every difference that lives in a file you own. For differences in files you do not own, list them under
"Found, not fixed" with `file:line` and the exact change.

## Proof
`swiftc -parse` every PaseoUI file you edited. After your edits, `grep` that every symbol you removed has
no remaining use. List Apple APIs you were unsure of (expected: none; this ticket removes code).
