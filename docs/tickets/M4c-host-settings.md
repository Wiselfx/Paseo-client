# M4c: host settings pages

Branch `m4c-host-settings`. Shared rules: top of `docs/tickets/M3-workspace-panel.md`. Update the
"Host settings →" rows in `docs/PARITY.md` in the same commit. You may edit
`Chat/PaseoSettingsView.swift`, new PaseoUI files, and (only if a field is missing) add decoding in
new PaseoCore files with tests; keep edits to `HostSettingsStore.swift` minimal (T15 and M2.8 are
in PaseoCore too). Reference: `docs/research/01-app-features.md:295-306`, protocol
`docs/research/04-protocol-agents-permissions-settings.md` (daemon config), upstream
`/home/paseo/dev/paseo-reference/packages/app/src/screens/settings/` for exact copy and grouping.

Add a "Host" section to Settings (ClaudeUI grouped rows, same style as M4a) with pages backed by
`session.hostSettings.config` / `save(_ patch:)`:
1. **Agents**: Enable Paseo tools, browser tools, custom system prompt (multiline editor), orchestration
   skills, restart recovery, release idle agents: whichever the config carries; skip absent ones.
2. **Metadata**: generation model Automatic / Manual (+ provider/model picker reusing the agent
   catalog) for titles, branch names, commit messages, PR drafts.
3. **Workspaces**: archive merged-PR workspaces switch.
4. **Projects**: per-host project list from `WorkspaceDirectory` (name, path, workspace count),
   read-only plus Remove (with confirmation) when `supportsProjectRemove`.
5. **Overview**: host name/version/connection URL read-only (rename/color only if the config has
   them).
Saving: toggles save immediately (optimistic, revert + inline error on failure), text fields on
Done. Feature-gated rows hidden rather than disabled. Desktop-only items (plugins, pair device,
terminal profiles) get no UI; mark them `desktop-only (flag)` or leave `missing` with a reason.

Commit "M4c: host settings pages", don't push. Final message: what changed, config fields found vs
missing, unsure-compile spots.
