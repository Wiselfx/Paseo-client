# N4: a user message sent while the agent is working must show in the chat

Read `AGENTS.md`, then `docs/tickets/_L-common.md` (upstream-first rules apply in full).

## Evidence (measured on the simulator, 2026-11-15)
With the default send behaviour (steer, upstream's default) the user sends a message while a turn is running.
The daemon accepts it: `paseo logs <agent>` shows `[User] SECOND message while running` in the middle of the turn
(after `[Shell] sleep 45`). Our app clears the composer and never shows the message, not even after the turn ends.

## Cause (read, confirmed in code)
`Packages/PaseoCore/Sources/PaseoStore/Turn.swift` `TurnDraft.add(_:)`: only the FIRST row of a turn becomes
`userMessage`; any later `.userMessage` row falls into the `default:` branch and becomes `Segment.notice(row)`.
`Packages/PaseoUI/Sources/PaseoUI/Conversation/Transcript/ChatTurns.swift` `ClaudeSegmentView` renders
`.notice(let row)` with `ClaudeNoticeRow(item:)` (`Conversation/Turn/ClaudeToolDetail.swift` ~457), whose `default:`
case is `EmptyView()`. So a mid-turn user message renders as nothing.

## Upstream
Upstream shows a user message as a normal row of the stream wherever it falls: `packages/app/src/agent-stream/layout.ts`
(~lines 165, 330-331: `user_message` rows, grouping of consecutive user rows). Copy that behaviour: the message
appears as a user bubble at its position inside the turn, between the work/prose segments. Cite
`Upstream: packages/app/src/agent-stream/layout.ts:330-331` in the commit.

## Owns (touch only these)
- `Packages/PaseoUI/Sources/PaseoUI/Conversation/Transcript/ChatTurns.swift` (only `ClaudeSegmentView` and what it needs)
- new test files only. Never edit an existing test.
Do NOT change `Turn.swift` or any Core file: the model keeps the row as a `.notice` segment; only the rendering changes.
If you believe Core must change, stop and say why.

## Steps
1. In `ClaudeSegmentView.body`, case `.notice(let row)`: add a branch before the existing call:
   `if case .userMessage(let message) = row.item { <a user bubble> } else { ClaudeNoticeRow(item: row.item) }`
   (use `@ViewBuilder` structure so both branches type-check; the `switch` is already inside `body`).
2. The bubble is `ClaudeUserBubble` exactly as the turn's first message uses it (see `fullTurn` in the same file,
   ~lines 183-200): same `text`, `isPending: row.isPending`, `clientMessageId: message.clientMessageId`. Read
   `ClaudeUserBubble`'s initializer (`Conversation/Turn/ClaudeChatComponents.swift`) and pass every required
   argument. Rewind: pass no rewind choices and `onRewind: nil` (a steered message is not a rewind point here).
   `attributed:` is computed by a method of the enclosing turn view (`bubbleAttributed`); if the segment view
   cannot reach it, pass the plain-text value the initializer accepts (read how `attributed` is typed and what
   `bubbleAttributed` does; do not duplicate its logic: if the segment view needs it, pass a closure or the
   already-built value from the call site where `ClaudeSegmentView` is created; list what you chose).
3. Add `.id("row:\(row.seqEnd)")` like the first bubble so find/scroll jumps keep working.
4. Show the "sent by" line if the first-message code does (`sentByLine(sender)`), only if it is reachable without
   copying a large block; otherwise omit it and say so.
5. Check the other places that switch over segments and might hide this row: `ClaudeStatusLine.swift` lines ~58 and ~113,
   `ChatTurns.swift` lines ~85 and ~510, `ChatTranscript.swift` ~1078. They only compute counts/ids; confirm they
   do not need a change and say so.

## Proof
`swiftc -parse` the edited file. `Tools/style-lint/style-lint.sh` on it: no new hits. Core is untouched, so
`swift test` is not needed; confirm no existing Core test asserts how a mid-turn user row renders (grep
`Packages/PaseoCore/Tests` for `notice` and `userMessage`). Commit as `N4: show a user message sent mid-turn`.

## Final message
What you did per step, how you handled `attributed:`, every Apple API or initializer you were unsure of, and
"Found, not fixed".
