# T2: Timeline reducer

Implement `TimelineState` in PaseoStore: the pure value that turns timeline pages and live stream
deltas into the rows the chat shows.

## Files you own

- `Packages/PaseoCore/Sources/PaseoStore/TimelineState.swift` (fill in the three method bodies;
  add private helpers; do not change public declarations or doc comments)
- New test files in `Packages/PaseoCore/Tests/PaseoStoreTests/` if you want more tests

Read but don't change: `Tests/PaseoStoreTests/TimelineStateTests.swift` (the acceptance tests),
`Tests/PaseoStoreTests/Helpers.swift`, `Sources/PaseoProtocol/*`.

Background: upstream `docs/timeline-sync.md` in getpaseo/paseo. The fixtures in
`Tests/PaseoFixtures/Fixtures` are real: `stream/` is one turn of live deltas, and the same turn
appears projected at the end of `fetch_agent_timeline_response.json`.

## Row ids

- tool call: `tool:<callId>`
- pending user message: `local:<clientMessageId>`, and it keeps that id after confirmation
- everything else: `seq:<seqStart>`

## applyPage(page)

- Map each `TimelineEntry` to a row (`seqStart`/`seqEnd`/`turnId`/`timestamp` copied, `isPending: false`).
- If `page.reset`, or our `epoch` is set and differs from `page.epoch`: replace all rows with the page's.
- Otherwise merge by seq. Rows whose range overlaps a page row's range are replaced by the page
  row; the rest are kept. Keep rows sorted by `seqStart`. Pending rows stay at the end.
- `epoch = page.epoch`.
- `direction == .tail` or `.after`: `nextSeq = page.window.nextSeq`.
  `.before`: leave `nextSeq` alone, unless it is nil.
- `direction == .tail` or `.before`: `hasOlder = page.hasOlder`.

## applyStream(payload) -> StreamResult

In this order:
1. Not a `.timeline` event, or no `seq`: `.ignored`.
2. `nextSeq == nil` (no page yet): `.ignored`.
3. `payload.epoch` set and different from ours: `.epochChanged`.
4. `seq < nextSeq`: `.duplicate`. `seq > nextSeq`: `.gap(expected: nextSeq, received: seq)`.
   In all of 1–4, change nothing.
5. `seq == nextSeq`: merge the item (below), `nextSeq += 1`, return `.applied`.

Merge rules for the event's item, with `turnId` from the event:
- **reasoning**: if the last non-pending row is reasoning with the same `turnId`, append the
  text to it and set its `seqEnd = seq`. Otherwise append a new row.
- **assistant_message**: same rule with assistant rows.
- **tool_call**: if a row `tool:<callId>` exists, replace its item with the new one and set
  `seqEnd = seq` (it keeps its position and `seqStart`). Otherwise append a new row.
- **user_message**: if a pending row has `id == "local:<clientMessageId>"`, fill it in
  place: the item from the event, `isPending = false`, `seqStart = seqEnd = seq`, the event's
  `turnId` and timestamp. Keep its id. Otherwise append a new row.
- **anything else**: append a new row.

"Append" means after the last non-pending row, before any pending rows.
The new row's timestamp is the payload's `timestamp`.

## addPendingUserMessage

Append a row with `id: "local:<clientMessageId>"`, item `.userMessage(text:clientMessageId:)`,
`turnId: nil`, `seqStart = seqEnd = nextSeq ?? 0`, `isPending: true`. Always last.

## Done when

- `swift test --filter TimelineStateTests` passes all six tests.
- `swift build --build-tests` has no warnings in your file.
- Keep it O(rows) or better per call. A conversation can have thousands of rows.
