# P2: report the focused terminal in the heartbeat

Read `AGENTS.md`, then `docs/tickets/_P-common.md`, then this file.

## Item
**D-022** (LEDGER): upstream's presence heartbeat carries the focused terminal id (`docs/terminal-activity.md`), so terminal
`needs_input`/`finished` attention clears. Our wire type has `focusedTerminalId` (`HostSettings.swift`) and L3 added focused-terminal
heartbeat state in the store, but nothing in the UI sets it (`WorkspaceTerminalsView.swift` → the store's `updateTerminalFocus`).
Wire the existing store method from the terminal view (focus when a terminal is shown and the app is active, clear when it
goes away). Also check the audit's second half: terminal unread must come from the daemon's `attentionReason`, not a local
`lastViewed`; fix only if upstream's panel does it a specific way and our change is small.

## Owns
`Packages/PaseoUI/Sources/PaseoUI/Workspace/WorkspaceTerminalsView.swift` (and the terminal view files it directly uses),
`Packages/PaseoCore/Sources/PaseoStore/TerminalsStore.swift` only if the hookup needs a tiny change.
Commit: `P2: focused terminal in the heartbeat`.
