# M10: attention notifications

Branch `m10-notifications`. Read `AGENTS.md`, `ARCHITECTURE.md`, shared UI rules at the top of
`docs/tickets/M3-workspace-panel.md`. Update the Notifications rows in `docs/PARITY.md` in the
same commit. Reference: doc 01 lines ~335-345, upstream app notification code (search
`attention`, `notification`, `Notifications.` in `/home/paseo/dev/paseo-reference/packages/app/src`)
and its i18n wording; this client decodes `attention_required` (`PaseoProtocol/AgentTimeline.swift`)
and `terminal_attention_required` (`PaseoStore/TerminalsStore.swift`).

1. **Research first** (short, in `docs/research/10-notifications.md`, cite path:line): what upstream
   notifies on (agent finished / needs input / permission / error; terminal attention), what it
   suppresses (viewing that agent, pure errors), dedupe and routing; and what iOS allows us without
   a relay or our own push server: local notifications while the app is foreground/recently
   backgrounded over the live socket, background task limits. State plainly what can't work
   (true remote push) and why. No invented features.
2. **Store**: an `AttentionCenter` (PaseoStore, Foundation only) that turns agent + terminal
   attention events into deduped notification intents (agent/workspace ids, title, body), with
   suppression for the agent currently on screen. Tests in new files.
3. **App**: request permission at a sensible moment (not at launch: first time an agent needs
   you, or a Settings toggle), post local notifications via `UNUserNotificationCenter` for the
   intents, tap routes to that agent/workspace (wire into the existing selection path), a
   Settings → General → Notifications toggle. Keep the Apple-only code tiny and listed.

Live checks only against the sandbox (`/tmp/fixture-sandbox`, agent
`1c51ee58-765c-4f8d-bf27-7009338b361e`); never touch other agents. swiftc -parse every UI/App file;
PaseoCore clean build + tests green. Run `Tools/api-audit` (README) before committing. No
background tasks or subagents; don't end your turn while waiting. Commit "M10: notifications",
don't push. Final message: what's possible on iOS, what changed, gaps, unsure-compile spots.
