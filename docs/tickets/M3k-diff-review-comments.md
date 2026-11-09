# M3k: review comments in the diff

Branch `m3k-review-comments`. Rules: top of `docs/tickets/M3-workspace-panel.md`. Update the
matching rows in `docs/PARITY.md` (Changes & diffs) in the same commit, and re-check every row of
that section against the code (fix stale `missing`/`done` statuses you can prove). You may edit
`Workspace/*` diff/changes files and new files. Reference: doc 01 lines ~184-185, upstream
`/home/paseo/dev/paseo-reference/packages/app/src` (search "Leave a comment", "Send feedback",
i18n `en.ts`) — reuse its wording.

1. **Leave a comment**: long-press (and a context-menu item) on a diff line or a selected line
   range in the Changes view adds a draft comment anchored to file + line(s); drafts render inline
   under the line as quiet cards (edit/delete). Drafts live per workspace and per diff mode
   (as upstream), in memory (survive panel close, not relaunch) unless upstream persists them.
2. **Send feedback (N)**: a bar/button in the Changes header when drafts exist; picks the target
   agent (the open chat's agent by default, else the workspace's agents) and sends one prompt
   built the way upstream formats it (file:line, quoted snippet, comment). Clears drafts on
   success; errors inline.
3. Works in unified and side-by-side diff; Reduce Motion respected; VoiceOver labels.

No PaseoCore changes expected (sending reuses the existing send path); if one is needed, stop
and say so. swiftc -parse every touched file. Commit "M3k: diff review comments", don't push.
Final message: what changed, gaps, unsure-compile spots.
