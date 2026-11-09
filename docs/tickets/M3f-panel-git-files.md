# M3f: git actions and file operations in the workspace panel

Branch `m3f-panel-git-files`. Shared rules: top of `docs/tickets/M3-workspace-panel.md`. Update the
Files and Git & changes rows in `docs/PARITY.md` in the same commit. You may edit
`Workspace/*.swift` and new files. Store: T15 (`PaseoStore/GitActions.swift` via
`session.gitExtras.gitActions(for:)`, `PaseoStore/FileEntries.swift` on `WorkspaceFiles`).
Reference copy: `docs/research/01-app-features.md:155-178,200-213`, upstream
`packages/app/src/git/` and `components/file-explorer-pane.tsx`.

1. **Changes page toolbar**: one quiet primary action that adapts (Commit when dirty → Push when
   ahead → Create PR when pushed and no PR → View PR when open), plus a "…" menu with Pull,
   Update from <base>, Merge PR (squash/merge/rebase submenu, confirmation), Auto-merge toggle when
   supported. Disabled items say why (one short line). Merge conflicts show an inline banner
   ("Merge conflict in N files: ask the agent to resolve" with a button that mentions it in chat via
   the existing mention path). Create PR: small sheet with title/body prefilled from branch name
   and last commit subject; opens the URL in Safari after.
2. **Commits section** (gate commitsList): under the file list, "Commits ahead of <base>" rows
   (subject, short sha in Mono, relative age); tap → that commit's files → per-file diff reusing
   `WorkspaceChangesDiffView`.
3. **Files page**: context menu on rows: Rename…, Duplicate, Delete (confirmation, destructive),
   New file / New folder (on folders and from a "+" in the page header), Mention in chat (keep),
   Copy path. Show/hide hidden files toggle in the header menu (persisted).
4. **Text editing** (gate workspaceFileEditing): in the file viewer, an Edit button for text files
   under ~512 KB switches to a plain monospaced `TextEditor`; Save writes with
   `expectedModifiedAt`; on conflict an alert "Changed on disk" with Reload / Overwrite.

Commit "M3f: panel git actions and file operations", don't push. Final message: what changed,
unsure-compile spots.
