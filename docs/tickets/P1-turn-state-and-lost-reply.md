# P1: turn state from events, lost replies, honest permission answers

Read `AGENTS.md`, then `docs/tickets/_P-common.md`, then this file.

## Items (audit: /home/paseo/dev/docs-audit/findings/)
- **X-001** (LEDGER-EXTRA): any agent snapshot resets the running turn. Upstream (`public-docs/sdk/events.md:103`): never infer
  turn completion from an `agent_update` status change; turn start/end come from `turn_started` / `turn_completed` /
  `turn_failed` / `turn_canceled` stream events. Make the running turn follow those events and stop the snapshot from
  resetting it. Look at `ConversationStore.setActiveTurn` and where the snapshot writes `activeTurnId`.
- **X-006** (LEDGER-EXTRA): a mutation whose response is lost must read as "outcome unknown", not as a clean failure
  (`public-docs/sdk/reference.md:259-262`: inspect before retrying a mutation). `ConnectionError.outcomeUnknown` already exists
  (L3, `Packages/PaseoCore/Sources/PaseoKit/DaemonClient.swift`). Use it on the send-message path: a send that was sent but whose
  answer was lost must not offer a blind retry that duplicates the message; it must show the state and let the timeline decide
  (the sent message arrives through the timeline). Reuse the existing pending/optimistic user-message row.
- **D-036** (LEDGER): `HostSession.respond(...)` → `AgentControlStore.sendExpectingEvent` is `Task { _ = try? await send(...) }`
  with no error surface. Permission answers must surface a failure (use the existing `actionError` path) instead of being
  swallowed. Check upstream's permission response handling first and mirror it.

## Owns
`Packages/PaseoCore/Sources/PaseoStore/HostSession.swift`, `AgentControlStore.swift`, `Turn.swift` if needed, and the
smallest UI change that shows the outcome-unknown state on the pending user bubble (reuse the existing pending-row styling in
`Packages/PaseoUI/Sources/PaseoUI/Conversation/Turn/` or `Transcript/ChatTurns.swift`). No other files.
Commit: `P1: turn state from events, outcome-unknown send, honest permission answers`.
