# T3: Turn builder

Implement `TurnBuilder.turns(from:activeTurnId:)` in PaseoStore. It groups timeline rows into
turns, the unit the chat draws.

## Files you own

- `Packages/PaseoCore/Sources/PaseoStore/Turn.swift`: only the body of `TurnBuilder.turns`.
  You may add `private` helpers in the same file. Do not change anything else in the file.

Read but don't change: `Tests/PaseoStoreTests/TurnBuilderTests.swift` (the acceptance tests),
`Tests/PaseoStoreTests/Helpers.swift`, `Sources/PaseoStore/TimelineState.swift` (for `TimelineRow`).

## Rules

Walk `rows` in order, once.

1. **Which turn a row belongs to.** A run of rows with the same `turnId` is one turn. A row whose
   `turnId` is nil joins the current turn, except a `.userMessage` with a nil `turnId` (just
   sent, not confirmed), which always starts a new turn. If a `turnId` shows up again after a
   different turn, start a new `Turn` anyway (keep order; don't move rows).
   `turn.id` is the first row's id; `turn.turnId` is the daemon's id (nil if none).
2. **userMessage.** If the first row of a turn is a `.userMessage`, it becomes `turn.userMessage`
   and is not added to `segments`. A later user message in the same turn is a `.notice` segment.
3. **segments.** Consecutive `.reasoning` and `.toolCall` rows form one `.work(WorkGroup)`.
   Anything else ends the current group:
   - `.assistantMessage` → `.prose(row)`
   - `.todo` → `.todo(row)`
   - everything else (error, notification, compaction, unknown, a later user message) → `.notice(row)`
4. **phase.** If `turn.turnId` is set and equals `activeTurnId`: `.running`. Otherwise, if the turn has an `.error`
   row: `.failed(message of the first error)`. Otherwise `.completed`.
5. **times.** `startedAt` = `PaseoDate.parse` of the first row's timestamp (including the
   user message). `endedAt` = parse of the last row's timestamp, or nil when `.running`.

## Done when

- `swift test --filter TurnBuilderTests` passes all five tests.
- `swift build --build-tests` has no warnings in your file.
- One pass over rows, no quadratic work.

> Revised after the first implementation: turn identity moved from the daemon's turn id to the
> first row's id, so a pending message's turn keeps its identity when confirmed.
