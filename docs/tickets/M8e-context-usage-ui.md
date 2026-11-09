# M8e: context meter and usage UI

Branch `m8e-context-usage`. Shared rules: top of `docs/tickets/M3-workspace-panel.md`. Update the
matching `docs/PARITY.md` rows (Context window meter, context-stats, Footer Usage row, pinned-window
meters) in the same commit. You may edit the **composer section** of `Chat/ClaudeChatView.swift`,
`Chat/ClaudeCodeContextSheet.swift` (or wherever the unwired ClaudeUI context sheet lives),
`Sidebar/PaseoSidebar.swift` footer only, `Settings`/`PaseoSettingsView.swift` (one row), and new
files. Do **not** edit the transcript or header (M7d owns them). Store: your T16 work
(`ConversationStore.contextUsage`, `session.hostUsage`). Reference: DSH `context-stats`
(`meter-ring.ts`, `session-cost.ts`; see `docs/research/08-dsh-live*` / the DSH folder cited in
PARITY), upstream `context-window-meter.tsx`.

1. **Context meter** in the composer toolbar (trailing, quiet): a small ring (DSH meter-ring:
   ramps green → amber → red by percent; 1.5 pt stroke, ~16 pt), hidden when the agent reports no
   window. Tap → the existing ClaudeUI context sheet, wired: "{{percentage}}% used", used/max
   tokens, input/output, cache hit rates, session cost (only when reported), cost by model rows.
   Animate ring changes (Reduce Motion: no animation). No placeholder numbers ever.
2. **Usage footer row** in the sidebar (gate `hostUsage.isSupported && usageEnabled`), hidden by
   default with a Settings → General toggle "Show usage in sidebar" (upstream hides it by default):
   one line per provider report with its pinned window as a thin bar + "62% · resets 3h". Tap →
   a sheet listing all reports/windows/balances, pull to refresh (`load(forceRefresh: true)`).
   Problems (unauthenticated, unavailable) as calm secondary text.

swiftc -parse every touched file; if PaseoCore changes, full `rm -rf .build && swift build
--build-tests && swift test`. Any new fixture: sandbox agent only, scrub ids/titles/paths.
Commit "M8e: context meter and usage", don't push. Final message: what changed, store gaps,
unsure-compile spots.
