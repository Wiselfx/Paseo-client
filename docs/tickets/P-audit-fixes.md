# P: audit fixes (one worker, sequential, one commit per item)

Read `AGENTS.md`, then `docs/tickets/_P-common.md`, then this file. One worker does all items below in this order, in one
worktree. Commit after each item (message names the item id). Run the Core build and tests after each Core change. If an item
turns out wrong, already fixed, or needs a product decision, skip it, say so in your final message, and continue. Files may
overlap between items: that is fine because you do them one after another.

## Item 1: turn state from events, lost replies, honest permission answers

### Audit entries in /home/paseo/dev/docs-audit/findings/
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

### Files
`Packages/PaseoCore/Sources/PaseoStore/HostSession.swift`, `AgentControlStore.swift`, `Turn.swift` if needed, and the
smallest UI change that shows the outcome-unknown state on the pending user bubble (reuse the existing pending-row styling in
`Packages/PaseoUI/Sources/PaseoUI/Conversation/Turn/` or `Transcript/ChatTurns.swift`). No other files.
Commit: `P1: turn state from events, outcome-unknown send, honest permission answers`.

## Item 2: report the focused terminal in the heartbeat

### Entry
**D-022** (LEDGER): upstream's presence heartbeat carries the focused terminal id (`docs/terminal-activity.md`), so terminal
`needs_input`/`finished` attention clears. Our wire type has `focusedTerminalId` (`HostSettings.swift`) and L3 added focused-terminal
heartbeat state in the store, but nothing in the UI sets it (`WorkspaceTerminalsView.swift` → the store's `updateTerminalFocus`).
Wire the existing store method from the terminal view (focus when a terminal is shown and the app is active, clear when it
goes away). Also check the audit's second half: terminal unread must come from the daemon's `attentionReason`, not a local
`lastViewed`; fix only if upstream's panel does it a specific way and our change is small.

### Files
`Packages/PaseoUI/Sources/PaseoUI/Workspace/WorkspaceTerminalsView.swift` (and the terminal view files it directly uses),
`Packages/PaseoCore/Sources/PaseoStore/TerminalsStore.swift` only if the hookup needs a tiny change.
Commit: `P2: focused terminal in the heartbeat`.

## Item 3: Restart daemon and restart-required feedback

### Entries
- **X-002** (LEDGER-EXTRA): upstream's Settings → host → Overview has "Restart daemon" (`public-docs/configuration.md`,
  `troubleshooting.md`). Port it with upstream's exact copy from `en.ts` (search `restart` near lines 3076-3115: hint,
  confirmation, offline message, failure messages, unable-to-reconnect). Use the existing restart RPC if the wire type exists
  in `Packages/PaseoCore/Sources/PaseoProtocol`; if it does not, find the upstream request (`packages/protocol/src/messages.ts`)
  and add the minimal request/response type next to the host-settings types.
- **X-003** (LEDGER-EXTRA): config saves must report `restartRequiredPaths` / what needs a restart so a saved but inactive setting
  does not look applied. Show it where the setting is saved, with upstream's wording, and offer the same Restart action.
Ignore the plugin pages (not in scope).

### Files
`Packages/PaseoCore/Sources/PaseoStore/HostSettingsStore.swift`, the matching wire file in `PaseoProtocol` (only to add the restart
request if missing), `Packages/PaseoUI/Sources/PaseoUI/Settings/OverviewPage.swift` and the settings page that saves config.
Commit: `P3: restart daemon and restart-required feedback`.

## Item 4: archive cascade warning and open-agent-tab label

### Entries
- **X-005** (LEDGER-EXTRA): "Archiving a parent cascade-archives its children. Call detach() first"
  (`public-docs/sdk/agents.md:106`). Our archive confirmation only mentions "still running". Add upstream's cascade warning
  to the existing archive confirmation (find the upstream copy in `en.ts`: search `archive` + `subagent`/`children`), and offer
  detach first if upstream does. Reuse the existing detach RPC (`ChatSubagents.swift` `managedRow`).
- **D-001** (LEDGER): upstream writes the label `paseo.open-agent-tab.<client-id>` when the user opens a managed subagent so the
  parent's archive does not cascade onto an agent the user is viewing (`docs/agent-lifecycle.md:133`). Write and clear that label
  with the existing `UpdateAgentRequest.labels` (`AgentControl.swift`), through `AgentLifecycleStore`. Use the client id we
  already send in the hello (do not mint a new id). Match upstream's timing: set on open, clear on close/background.

### Files
`Packages/PaseoCore/Sources/PaseoStore/AgentLifecycleStore.swift`, `Packages/PaseoUI/Sources/PaseoUI/Conversation/Screen/ChatHeader.swift`
(archive confirmation only), `ChatSubagents.swift`, and the screen that opens a subagent. Do NOT touch `HostSession.swift`
(another worker owns it); if you need a change there, list it.
Commit: `P4: archive cascade warning and open-agent-tab label`.

## Item 5: create agents through the modern path, with an idempotency key
**D-014** (LEDGER): upstream creates agents with `agent.create.request` carrying `idempotencyKey`
(`packages/protocol/src/messages.ts:1865`), gated by `features.creationLifecycle` / `agentRequestReceipts` (`:3901-3905`). We send the legacy
`create_agent_request` with a fresh request id each time, so a retry after a lost ack double-creates. L3 added the idempotency
fields to the wire types but nothing uses them. Use the modern request when the daemon advertises the feature, with one key per
user action, reused on retry; keep the legacy request only as upstream's fallback for daemons without the feature. Advertise the
two capabilities in the hello only once the path works (a pinned test `OwnedSubscriptionsCapabilityTests` lists the advertised
set: do not edit it, list the needed change in your final message).
Files: `PaseoProtocol/AgentControl.swift`, `PaseoStore/AgentControlStore.swift`, the create caller.
Commit `P5: create via agent.create.request with idempotency key`.

## Item 6: catch-up retry and the missed-events signal
**D-026** and **X-008** (LEDGER / LEDGER-EXTRA): `HostSession.catchUp()` swallows failures with no retry; we advertise
`owned_subscriptions` but drop `agent.timeline.subscription_restored`. Follow upstream (`public-docs/sdk/events.md`,
`packages/client`): retry with upstream's backoff and handle `subscription_restored` by catching up.
Files: `PaseoStore/HostSession.swift`. Commit `P6: catch-up retry and subscription_restored`.

## Item 7: foreground notifications
**D-018** (LEDGER): upstream `docs/notifications.md:53`: foreground notifications stay in Notification Center without banner or sound.
Ours returns `[.banner, .list, .sound]` (`App/Sources/NotificationCoordinator.swift:310-313`). Match upstream.
Files: `App/Sources/NotificationCoordinator.swift`. Commit `P7: foreground notifications without banner or sound`.

## Final message
Per item: done / skipped (why), files changed, upstream citations, build and test results, anything unsure, the list of existing tests
that need to change (do not change them).
