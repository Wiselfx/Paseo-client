# M9: search / command center

Branch `m9-command-center`. Rules: top of `docs/tickets/M3-workspace-panel.md`. Update the Search &
history / Sidebar rows in `docs/PARITY.md` in the same commit. You may edit `Sidebar/*`,
`Chat/PaseoShellView.swift` (presentation only), new files. Not `Conversation/*`, `Settings/*`.
Reference: doc 01:25 and the Command center row (upstream `packages/app/src/` command center:
find and cite), DSH `search` folder (`…/features/search/`) for the look.

1. A **Search** row in the sidebar header (with History/Schedules) opening a full-height search
   sheet in the DSH palette style: one field, grouped results — **Agents** (title, workspace,
   status; live + archived via M7e's history store), **Workspaces**, **Projects**, **Files** in
   the open workspace (reuse M8d's MentionIndex via a scratch WorkspaceFiles), **Actions** (New
   agent, New workspace, Open settings, Toggle panel, Switch host…). Keyboard: return opens the
   first result; arrow keys on hardware keyboards. Recents when the field is empty.
2. Results open the thing (agent → chat, workspace → its newest agent or empty state, file →
   viewer, action → runs it). Haptic on open. Reduce Motion respected.

swiftc -parse every touched file. Commit "M9: command center", don't push. Final message: what
changed, gaps, unsure-compile spots.
