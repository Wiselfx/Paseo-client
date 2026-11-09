# M7i: turn navigator, effort ladder, hero pickers

Branch `m7i-turn-nav-effort`. Rules: top of `docs/tickets/M3-workspace-panel.md`. Update rows in
`docs/PARITY.md` (Conversation & turns, Composer, DSH folder inventory) in the same commit, and
re-check every row of those sections against the code (several are stale: e.g. message-actions,
dictation, assistant-file links, chat settings; fix the ones you can prove). You may edit
`Conversation/*`, `Chat/*` composer/new-agent files, and new files. Reference: DSH folders
`turn-nav`, `effort`, `hero-menu` (paths in PARITY), doc 06/08 for DSH behavior.

1. **Turn navigator** (DSH `turn-nav`): a slim numbered rail of your messages at the transcript's
   trailing edge, shown while scrolling / on demand (not always-on clutter on a phone); tap jumps
   to that turn (reuse M7d's anchoring/scroll helpers), current turn highlighted. Hidden for
   short chats. Reduce Motion respected.
2. **Effort ladder** (DSH `effort`): the thinking/effort picker becomes a compact Faster ↔ Smarter
   ladder with the accent tint on the composer chip when not default; same store calls as today.
   Keep the plain list when a provider's options aren't ordered levels.
3. **Hero pickers** (DSH `hero-menu`): on the new-conversation hero, a workspace (directory) chip
   and the agent preset/profile seat (reuse M8f's profile picker), so a chat can start without
   opening the full new-agent sheet.

swiftc -parse every touched file; rg any symbol you rename. Commit "M7i: turn nav, effort,
hero pickers", don't push. Final message: what changed, gaps, unsure-compile spots.
