# N5: a stopped turn must not say "Completed"; compaction stays visible; "Sent by" shows the agent's title

Read `AGENTS.md`, then `docs/tickets/_L-common.md` (upstream-first rules and proof apply in full), then
`docs/tickets/N4-midturn-user-message.md` (it shows how the always-visible rows work in `ChatTurns.swift`).

## A. A stopped turn shows no "Completed in X" text
**User decision:** upstream has no wording for a stopped turn, so we say nothing either: a turn the user stopped
must NOT read "Completed in 10s". It simply shows no completion text (keep the row's chevron/fold control).
**Evidence:** after Stop, the turn row reads `Completed in 10s`. The protocol already carries the event:
`Packages/PaseoCore/Sources/PaseoProtocol/AgentTimeline.swift` line ~111 `case turnCanceled(turnId: String?, reason: String)`
(decoded at ~135). Nothing in the store records it (`grep -rn turnCanceled Packages/PaseoCore/Sources`: only
`VoiceModeSession.swift:339`). Upstream tracks `turn_canceled` as a terminal turn event
(`packages/app/src/timeline/session-stream-reducers.ts:1820`, `packages/app/src/contexts/session-context.tsx:365`).
**Do (small, no change to `Turn.Phase` or the turn builders):**
1. In `Packages/PaseoCore/Sources/PaseoStore`, find where stream events are applied to a conversation
   (`HostSession.swift` ~line 960 handles `.turnCompleted(let turnId, let usage)`; follow it to the
   `ConversationStore`). Add `public private(set) var canceledTurnIds: Set<String> = []` to `ConversationStore`
   and insert `turnId` when a `.turnCanceled(turnId: let id, ...)` event arrives (ignore nil). Keep it O(1).
2. Add a new Core test file `Packages/PaseoCore/Tests/PaseoStoreTests/CanceledTurnTests.swift` (Swift Testing) that
   applies a canceled event to a store and expects `canceledTurnIds` to contain the id (follow the closest existing
   test that feeds events to a store; copy its helpers). Run `swift build --build-tests` and `swift test`.
3. In `Conversation/Transcript/ChatTurns.swift` (`ClaudeTurnView`, the `.completed` case ~line 317 where
   `Text(turn.duration.map(DurationText.completed) ?? "Completed")` and the clock icon are drawn): when the
   turn's `turnId` is in `store.canceledTurnIds`, draw neither the clock icon nor the text (the row keeps its
   `Spacer` and chevron). Pass the flag in from where `ClaudeTurnView` is created (a plain `Bool` parameter with
   default `false`, so previews still compile); do not read the store from inside the row.

## B. Compaction markers stay visible, outside the folded work
**User report:** a compaction marker shows up under "Completed in X" (inside the folded/expanded work). It must
stay in the chat as its own visible row. **Upstream:** `packages/app/src/agent-stream/turn-collapse/model.ts:102`
`staysVisibleWhenCollapsed(item) = isTurnTrigger(item) || item.kind === "compaction"`.
N4 already keeps mid-turn user messages visible: `ClaudeTurnView.midTurnRows` (computed from `turn.segments`),
rendered by `ClaudeMidTurnBubble` in `collapsedTurn` and in `fullTurn`'s `else` branch, and in place by
`ClaudeSegmentView`. Extend the same mechanism to compaction: rename `midTurnRows` to `visibleRows` (rows whose
item is `.userMessage` or `.compaction`), and make the always-visible list draw a compaction row with the same
marker `ClaudeNoticeRow` uses (`ClaudeCompactionMarker`, `Conversation/Turn/ClaudeToolDetail.swift`), never in both
places (the expanded body keeps drawing it in place via `ClaudeSegmentView`). Keep ids/find-highlight like the bubble.

## C. "Sent by" shows the sending agent's title, like upstream
`ChatTurns.swift` `sentByLine(_:)` passes `agentTitle: nil` to `TurnSummary.senderName(agentTitle:senderTitle:senderID:)`.
Upstream (`packages/app/src/components/user-message/index.tsx:95`) prints `agent?.title ?? sender.title ?? sender.id`,
where `agent` is the agent whose id is the sender's id, looked up among the daemon's known agents. Do the same:
look the title up from the host session's agent directory (find how the chat looks up other agents, for example
`session.agents`/`AgentDirectory` in the stores; grep `title` + `agentId` in `Packages/PaseoStore`), pass it as
`agentTitle`, keep the fallback to `sender.title`, then `sender.id`. Show the line on mid-turn bubbles too (N4 left it
out): move the lookup into a small helper both places use. If the lookup is not reachable from `ClaudeTurnView`
without a large change, pass a `(String) -> String?` closure from the call site and say what you chose.

## Owns (touch only these)
`Packages/PaseoCore/Sources/PaseoStore/ConversationStore*.swift` and `HostSession.swift` (only the event hook),
new Core test file(s), `Packages/PaseoUI/Sources/PaseoUI/Conversation/Transcript/ChatTurns.swift`,
`Conversation/Turn/ClaudeToolDetail.swift` (only if the compaction marker needs it). Never edit an existing test.

## Proof
Core: `. ~/.local/share/swiftly/env.sh; cd Packages/PaseoCore; swift build --build-tests && swift test` (paste the summary
counts). UI: `swiftc -parse` each edited file, grep every symbol, `Tools/style-lint/style-lint.sh` on the files. Commit as
`N5: stopped turn says nothing, compaction stays visible, Sent by uses the agent title`, body listing upstream citations.

## Final message
Per item A to C: what changed (file:line), tests added and the run summary, every API you were unsure of, "Found, not fixed".
