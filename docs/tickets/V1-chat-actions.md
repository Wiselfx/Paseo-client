# V1: chat actions (fork targets, Retract, Delete turn, compaction marker)

Worker: DeepSeek. Read `AGENTS.md`, `_U-common.md`, `docs/UX-SPEC.md` §0 first. Upstream checkout:
`/home/paseo/dev/paseo-reference/packages`. DSH: `/home/paseo/dev/dsh-claude-style-reference/packages/client/src/features/message-actions/`.
Sweep that found these: `/tmp/reviews/parity-sweep-2026-11-09.md` B3–B6.

Copy is verbatim from the cited sources. No invented strings.

## 1. Fork target menu (upstream `app/src/components/assistant-fork-menu.tsx:100-121`)
The answer footer's fork button (`Conversation/ChatTurns.swift` ~line 214, `arrow.branch`) becomes a `Menu`
with two items, upstream labels from `message.actions.forkInNewTab` / `forkInNewWorkspace` in the upstream
en locale (find the exact English strings; cite them in your final message):
- **new tab** = today's behaviour: `ForkActions.forkConversation(fromBoundarySeq:)` in the same workspace, open the new agent.
- **new workspace** = create a workspace first (the existing workspace-create path the sidebar's "New workspace"
  uses), then fork into it. Read upstream's handler for the exact order and what it passes; port it.
While a fork is pending, that item shows a spinner and both items are disabled (upstream `pendingTarget`).
Errors go to the existing `backgroundError` banner.

## 2. Fork an in-flight turn (upstream `app/src/agent-stream/turn-footer.tsx:133` `onForkInFlightTurn`)
Read how upstream picks the boundary for a running turn. If it needs nothing new on the wire, show the fork
menu on the running turn's footer too. If it needs a protocol field we don't have, skip and say so.

## 3. DSH Retract and Delete turn (DSH `message-actions.ts:195-260`, `message-cut.ts`, copy `message-actions.copy.json`)
Both fork; the original agent is never touched (DSH: the host has no in-place cut).
- **Retract this message** (user bubble context menu, next to the existing Edit/Rerun): fork at the event
  *before* the user message, open the new agent, put the message text into its composer draft. Toast
  "The message is back in the composer". Not offered for messages with attachments, nor while the turn runs.
- **Delete this turn** (answer footer, same menu as fork, or the bubble menu; pick the one that reads cleaner
  and explain): fork at the boundary before the turn's user message, open the new agent. Toast "The turn is
  absent from the new session".
- Use the existing toast/notice mechanism. Use our existing fork plumbing; no new RPC.
- Keep our existing in-place Edit/Rerun (upstream rewind) as they are.

## 4. Compaction marker (upstream `app/src/components/message.tsx:1426`, `message-compaction-label.ts`)
Wire: `messages.ts:774-777` compaction item has optional `trigger` (auto|manual) and `preTokens`.
- Decode both in `PaseoProtocol/Timeline.swift` (`.compaction` case gains optional fields; keep old payloads
  decoding). Add tests with and without the fields.
- `Chat/ClaudeToolDetail.swift` ~254: port upstream's label logic exactly (loading / auto / manual / with token count,
  count via `PaseoFormat.compact` or whatever matches upstream's formatting). Loading state shows a small spinner.

## Done
PaseoCore green (`rm -rf .build && swift build --build-tests && swift test`), touched UI files pass
`swiftc -parse`, commit `V1: chat actions` on branch `v1-chat-actions`. Final message: labels with source
file:line, what you skipped and why.
