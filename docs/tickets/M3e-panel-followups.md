# M3e: panel follow-ups

Branch `m3e-panel-followups`. Shared rules: top of `docs/tickets/M3-workspace-panel.md`.
You may edit `WorkspacePanel.swift`, `WorkspaceFilesView.swift`, `WorkspaceFileViewer.swift`,
`PaseoShellView.swift`, and the composer section of `Chat/ClaudeChatView.swift`.

1. **Mention in chat** (from M3b): publish the open conversation's draft to the panel (an
   internal `EnvironmentKey` or a closure passed through `WorkspacePanel`; your call, keep it
   small). Long press a file → "Mention in chat" inserts `@relative/path ` at the end of the
   draft (space-separated from existing text), closes the panel, focuses the composer, light
   haptic. Same action in the file viewer's top row.
2. **Live file updates** (from M3b): pass what's needed (`session.gitExtras`) to the files page
   and the viewer; while a file is open, subscribe with T11's `watchFile` (see
   `PaseoStore/GitExtras.swift`) and re-read on change, keeping the scroll position; unsubscribe
   on close. Directory pages stay refresh-on-appear unless the store has a directory watch.
3. **Panel ↔ chat continuity**: when the panel's Agents page creates or switches an agent, the
   chat scrolls to its bottom and the composer keeps any unsent draft per agent (the store's
   `draft` is per `ConversationStore`; verify the shell doesn't recreate stores on switch).

Commit "M3e: panel follow-ups", don't push. Final message: what changed, unsure-compile spots.
