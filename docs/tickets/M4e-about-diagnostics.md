# M4e: About, Diagnostics, terminal and sidebar settings

Branch `m4e-about`. Rules: top of `docs/tickets/M3-workspace-panel.md`. Update the Settings rows
in `docs/PARITY.md` in the same commit. You may edit `Chat/PaseoSettingsView.swift`, `Settings/*`,
`Sidebar/PaseoSidebar.swift` (header rows only), `Workspace/PaseoTerminalView.swift` (scrollback
read only), new files. Reference: `docs/research/01-app-features.md:270-300`; doc 04 §12.9
(`diagnostics.request`).

1. **About**: app version/build (Bundle), connected host + daemon version (`serverInfo`),
   "What's new" only if the daemon/app exposes a changelog (else omit), links (GitHub repo of the
   upstream project). No update checking (App Store/TestFlight handles it).
2. **Diagnostics**: a copyable app report (app version, iOS version, device model, connection
   state, host daemon version, enabled features list, recent connection errors; never tokens,
   passwords or full hostnames: show the host as `host-…` label only) and the host diagnostics
   via `diagnostics.request` where supported (mono, copy).
3. **Terminal scrollback** setting (1k / 2k / 5k / 10k, default 2k) read by the terminal view.
4. **Sidebar settings**: visibility switches for the History / Schedules header rows and the usage
   row (move M8e's usage toggle here if it reads better), applied live.

swiftc -parse every touched file; PaseoCore rebuild+tests if touched. Commit "M4e: about and
diagnostics", don't push. Final message: what changed, gaps, unsure-compile spots.
