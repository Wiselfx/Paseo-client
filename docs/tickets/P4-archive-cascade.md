# P4: archive cascade warning and open-agent-tab label

Read `AGENTS.md`, then `docs/tickets/_P-common.md`, then this file.

## Items
- **X-005** (LEDGER-EXTRA): "Archiving a parent cascade-archives its children. Call detach() first"
  (`public-docs/sdk/agents.md:106`). Our archive confirmation only mentions "still running". Add upstream's cascade warning
  to the existing archive confirmation (find the upstream copy in `en.ts`: search `archive` + `subagent`/`children`), and offer
  detach first if upstream does. Reuse the existing detach RPC (`ChatSubagents.swift` `managedRow`).
- **D-001** (LEDGER): upstream writes the label `paseo.open-agent-tab.<client-id>` when the user opens a managed subagent so the
  parent's archive does not cascade onto an agent the user is viewing (`docs/agent-lifecycle.md:133`). Write and clear that label
  with the existing `UpdateAgentRequest.labels` (`AgentControl.swift`), through `AgentLifecycleStore`. Use the client id we
  already send in the hello (do not mint a new id). Match upstream's timing: set on open, clear on close/background.

## Owns
`Packages/PaseoCore/Sources/PaseoStore/AgentLifecycleStore.swift`, `Packages/PaseoUI/Sources/PaseoUI/Conversation/Screen/ChatHeader.swift`
(archive confirmation only), `ChatSubagents.swift`, and the screen that opens a subagent. Do NOT touch `HostSession.swift`
(another worker owns it); if you need a change there, list it.
Commit: `P4: archive cascade warning and open-agent-tab label`.
