# M8a: slash commands, presence, message polish

Branch `m8a-composer`. Shared rules: top of `docs/tickets/M3-workspace-panel.md`. Update the
matching rows in `docs/PARITY.md` in the same commit. You may edit the **composer section** of
`Chat/ClaudeChatView.swift`, `Chat/ClaudeChatComponents.swift`, `Chat/PaseoShellView.swift`, `App/Sources/*`
and new files. Do **not** edit the chat header or transcript sections (M7 owns them right now).

1. **Slash commands** (T10: `session.hostSettings.loadCommands(for:)` / `commands(for:)`): typing
   `/` at the start of the draft opens a menu above the composer card listing the agent's commands
   (name in Mono, description secondary, filtered as you type, max ~6 visible rows, scrolls).
   Tap inserts `/name ` and closes it. Loaded once per agent, cached; spinner row while loading;
   hidden if none. Selection haptic on highlight change. Then set the in-conversation placeholder
   to DSH's "Type / for commands" (doc 08 §4.1) when the agent has commands.
2. **Presence** (T10 `startPresence` / `updatePresence(focusedAgentId:appVisible:)` /
   `stopPresence`): start after connecting, report the open agent as focus and app visibility from
   `scenePhase` (active = visible), stop on disconnect. Wire it in the shell / app root.
3. **Per-message copy**: long-press a user bubble → context menu Copy (and Copy as Markdown for
   assistant prose if there isn't one already; keep the existing copy button under replies).
   Light haptic on copy.
4. **Bubble enter**: a sent user message grows into place (DSH chat-send "grow in place": scale
   from ~0.96 + fade, 200 ms ease-settle `cubic-bezier(0.22, 1, 0.36, 1)`); Reduce Motion: fade.
   Only for messages sent in this session, not on history load.

Commit "M8a: slash commands, presence, message polish", don't push. Final message: what changed,
store gaps, unsure-compile spots.
