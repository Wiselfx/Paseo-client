# M14: usage overview and connection states

Branch `m14-usage-home`. Read `AGENTS.md`, `ARCHITECTURE.md`, shared UI rules at the top of
`docs/tickets/M3-workspace-panel.md`. Update `docs/PARITY.md` rows and recount.

1. **Usage overview** (DSH `home`, folder path in PARITY: `home-figures.ts`, `overview.ts`): a
   calm usage overview built on M8e's store data (`contextUsage`, `session.hostUsage`, the usage
   reports sheet). Use Swift Charts (system framework, no new dependency): token activity over
   days (heat or bars), peak hour, per-model split, with DSH's figure wording; the "animal farm"
   comparisons only if DSH's copy file has them (port the wording, don't invent). Where it lives:
   extend the existing usage reports sheet (sidebar usage row) rather than cluttering the
   new-chat hero, which stays a greeting. Empty/loading states; Reduce Motion; VoiceOver chart
   descriptions (`accessibilityChartDescriptor` or plain labels).
2. **Connection states** (doc 01 ~:415): the app's connect path (App/ + ConnectView) shows a
   proper connecting state, a clear failure state with the daemon's error in plain words and
   **Retry**, and an offline/reconnecting banner while `DaemonConnection` reconnects (reuse what
   exists; don't add a second spinner system). Managed-daemon (desktop) parts are n/a: flag them.

No PaseoCore changes expected beyond small read-only helpers (tests if you add any). Done =
`swiftc -parse` on every touched UI/App file, `Tools/api-audit` no new real findings, PaseoCore
tests still green. No background tasks or subagents; don't end your turn while waiting. Commit
"M14: usage overview, connection states", don't push. Final message: what changed, gaps,
unsure-compile spots.
