# T18: close four known store gaps

Branch `t18-store-gaps`. Read `AGENTS.md`, `ARCHITECTURE.md`, `docs/tickets/PHASE3-BACKEND.md`, and
the shared UI rules at the top of `docs/tickets/M3-workspace-panel.md` (for the small UI parts).
Upstream reference: `/home/paseo/dev/paseo-reference/packages` (server `messages.ts`, app `src`).
Cite path:line for every wire claim in your final message. Update the matching `docs/PARITY.md`
rows in the same commit.

1. **Slash-command cache invalidation** (`PaseoStore/HostSettingsStore.swift`, `commandsByAgent`):
   today it is only dropped when a conversation closes. Find when upstream refetches an agent's
   commands (model/provider/mode change, agent restart/reload, reconnect, any push) and do the
   same. Tests.
2. **Host diagnostics** (`PaseoProtocol/Diagnostics.swift` has the wire types only): add a store
   slot (gated on `features.daemonDiagnostics`; ungated daemons get a quiet "not supported"
   state, no error spam), then a "Host diagnostics" section with a Run button on the existing
   Settings → Diagnostics page (`PaseoUI/Settings/DiagnosticsPage.swift`) showing the result in
   the page's existing style. Anything copied/shared must stay scrubbed like the page's current
   report (no tokens, hostnames, paths outside the workspace). Tests for the store.
3. **GitHub search star count**: check whether the daemon's GitHub repository search response
   carries stars (or similar). If yes, decode it and show it in the clone results row (find the
   Add project / Clone sheet in PaseoUI). If no, say so in PARITY and stop.
4. **Terminal font follows Code size**: `PaseoUI/Workspace/PaseoTerminalView.swift` builds its
   font at a fixed size; make it follow the Settings → General → Code size setting (see how
   `ClaudeTypography` / the M4f code-size key scales mono text), applied to already open
   terminals without losing scrollback.

Live checks only against the sandbox (`/tmp/fixture-sandbox`, agent
`1c51ee58-765c-4f8d-bf27-7009338b361e`); never touch other agents. Captured fixtures must be
scrubbed (no real ids, titles, server ids, hostnames, paths outside /tmp). Done =
`rm -rf .build && swift build --build-tests && swift test` fully green in Packages/PaseoCore,
`swiftc -parse` on every touched UI file, and `Tools/api-audit` (README) shows no new real
findings. No background tasks or subagents; don't end your turn while waiting. Commit
"T18: store gaps", don't push. Final message: what changed per item, wire citations, test totals,
unsure-compile spots.
