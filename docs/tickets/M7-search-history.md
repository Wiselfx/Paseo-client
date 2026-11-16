# M7: search and history

Branch `m7-search-history`. Shared rules: top of `docs/tickets/M3-workspace-panel.md`. Rows in
`docs/PARITY.md` "Search & history" are the checklist; update their status lines in PARITY.md in
the same commit. You may edit `Chat/ClaudeChatView.swift` (header and transcript only, not the
composer section, which another ticket owns), `Chat/PaseoSidebar.swift` (nav rows only), and new
files of your own.

1. **Agent menu from the title.** Tapping the centered chat title opens a small ClaudeUI-style
   sheet (or menu) for the open agent: Search in conversation, Rename, Copy agent ID, Archive
   (confirmation). The header itself stays as it is.
2. **Search in conversation** on T12's `ConversationSearch` (`PaseoStore/ConversationSearch.swift`):
   a search bar slides in under the header (Reduce Motion: fade), live results count "3 of 12",
   up/down chevrons, matches scrolled to and briefly highlighted in the transcript (inside
   collapsed work groups too: expand the group that holds the match). Esc/Cancel restores the
   previous scroll position. Selection haptic per step.
3. **History**: a sidebar nav row "History" (under Scheduled) opening a screen that lists agents
   across all workspaces, newest first, grouped by day ("Today", "Yesterday", "Earlier"), with a
   search field filtering by title. Include archived agents if the store/protocol can fetch them
   (check doc 04 and `HostSession`; if it needs a store addition, say exactly what and show active
   agents only). Tap opens the agent (unarchive first if needed and supported).

Commit "M7: search and history", don't push. Final message: what changed, store gaps, unsure-compile spots.
