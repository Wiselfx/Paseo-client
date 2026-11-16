# M3h: files and diff polish in the workspace panel

Branch `m3h-files-diff`. Shared rules: top of `docs/tickets/M3-workspace-panel.md`. Update the
Files and Git & changes rows in `docs/PARITY.md` in the same commit. You may edit
`Workspace/*.swift` (not the terminal files you just did, unless a fix is needed) and new files.
Do not edit `Chat/*` (other tickets own it). Reference: `docs/research/01-app-features.md:155-178,
200-213`, upstream `packages/app/src/components/file-explorer-pane.tsx`, `packages/app/src/git/`.

1. **Sort** the file list: Name / Modified / Size in a quiet menu on the Files page header,
   folders first always, persisted per device (`@AppStorage`).
2. **File row menu** additions: **Add to chat** (same as the existing Mention in chat path, keep one
   action, named like upstream), **Share/Download** (read the bytes through the existing store
   read, write to a temp file, `ShareLink`/share sheet; inline progress for large files, error
   inline), **Copy path** if missing.
3. **Preview**: Markdown files render (the app's existing Markdown renderer) with a
   Preview/Source toggle; images (png/jpg/gif/webp/heic) show as a zoomable image; everything
   else keeps the M3f text floor. Binary non-image: "Can't preview this file" + Share.
4. **Diff options** on the Changes page "…" menu: hide whitespace changes (client-side filter if
   the store has no flag; say which), wrap vs scroll long lines, collapse/expand all files.
   Persisted per device. A small **jump-to-file** button (floating, bottom trailing) when the
   diff lists 3+ files: menu of files, scrolls to that file's header.

Calm states, Reduce Motion respected, light haptics only on discrete actions. Commit "M3h: files
and diff polish", don't push. Final message: what changed, store gaps, unsure-compile spots.
