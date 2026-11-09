# P4: incremental turn building

Branch: `p4-incremental-turns` (from `foundation`). PaseoCore only: builds and tests on Linux.

## Problem

`HostSession.updateTurns()` (`Packages/PaseoCore/Sources/PaseoStore/HostSession.swift`, search
`private func updateTurns`) calls `TurnBuilder.turns(from: timeline.rows, activeTurnId:)` on every
change: every streamed token. That walks every row of the transcript and rebuilds every `Turn`
(2 date parses each), so a long chat costs O(rows) per token. Almost always only the **last** turn
changed.

## Goal

Same output, but only rebuild the turns that can have changed.

## Contract

- `TurnBuilder.turns(from:activeTurnId:)` keeps its signature and behaviour. It stays the reference
  implementation (`docs/tickets/T3-turn-builder.md`, `TurnBuilderTests`): do not change its
  semantics, do not edit existing tests.
- Add an incremental path, e.g. an `internal`/`public` `final class` or struct
  `IncrementalTurnBuilder` in `Sources/PaseoStore/Turn.swift` (or a new file next to it) that
  keeps what it last built and, given the new rows + `activeTurnId`, returns `[Turn]` that is
  **exactly equal** (`==`) to `TurnBuilder.turns(from:activeTurnId:)` for the same input.
- Design it yourself. One sound approach: remember, per built turn, the range of rows it came from;
  on update, find the first row index where the new rows differ from the old (compare row ids and
  values, newest end first is usually enough: appends and in-place updates of the tail are the
  common case), keep every turn that ends strictly before that index, and rebuild from the start
  of the turn containing it. Anything else (prepend of an older page, epoch reset, removal of a
  pending row, `activeTurnId` change) may fall back to rebuilding affected turns or everything:
  correctness first, the fast path only has to cover streaming at the tail.
  - `activeTurnId` changes affect only the phase/endedAt of the turns whose turnId is the old or
    new active id: handle that without a full rebuild if easy, otherwise full rebuild is fine (it
    is rare).
- Wire it into `HostSession.updateTurns()` (only that function and a stored property; reset the
  builder wherever the timeline is replaced, or just let the "rows differ at index 0" case
  cover it).
- Cost on the streaming fast path must not be O(total rows) in Turn construction. A comparison
  step that touches rows of the last turn only is fine; comparing the whole array element by
  element every token is not (that is as costly as what we remove).

## Tests (new file `Tests/PaseoStoreTests/IncrementalTurnBuilderTests.swift`)

1. **Equivalence property test**: generate many random row sequences (mix of user messages
   with/without turnId, reasoning, tool calls running/finished, assistant messages, todos, errors,
   notices, pending rows) and random edit scripts (append rows, update the last row's text, update a
   tool call status in the middle of the last turn, prepend an older page, remove a pending row,
   replace everything, change `activeTurnId`). After every step assert
   `incremental == TurnBuilder.turns(from: rows, activeTurnId:)`. Use a seeded deterministic RNG
   (write a tiny SplitMix64; no new dependencies). At least a few thousand steps total.
2. Targeted cases for each edit kind above.
3. **Reuse check**: on a tail append/update, prove earlier turns were not rebuilt (e.g. a debug
   counter of turns built in the last update, `internal` and read via `@testable import`).
4. **Timing**: a test with a ~5,000-row / ~500-turn transcript that streams 200 tail updates and
   prints the time for the full builder vs the incremental one. Don't assert on absolute times
   (CI noise); assert only that the incremental path built ≤ 2 turns per update.

Existing suites must stay green: `swift build --build-tests` with no warnings in your files, then
`swift test` (all suites).

## Rules

Follow `AGENTS.md`. Touch only: `Turn.swift` (or one new source file beside it),
`HostSession.swift` (`updateTurns` + one stored property + resets), your new test file. No
`#if os`, no force unwraps, Swift 6 strict concurrency clean. No background tasks, no subagents,
don't end your turn while waiting. Commit on the branch as `P4: incremental turn building`; do not
push or merge. Final message: the approach in a few lines, the timing numbers, test summary,
anything you were unsure about.
