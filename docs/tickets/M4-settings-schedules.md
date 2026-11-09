# M4: Settings and Schedules screens

Shared rules: as in `docs/tickets/M3-workspace-panel.md` (top section): ClaudeUI look, tokens
from `Chat/ClaudeStyle.swift`, Reduce Motion, haptics helper, `swiftc -parse` every touched file,
list unsure-compile spots, no PaseoCore edits (read only; report missing store support), no
background tasks/subagents, commit "M4x: …", don't push.

ClaudeUI already has polished screens to adapt, still in the package and unused:
`ClaudeSettingsView.swift` (+ `SettingsState.swift`, `ClaudeNotificationSettingsView.swift`,
`ClaudeUsageSettingsView.swift`) and `ClaudeRoutinesView.swift` (+ `RoutineState.swift`). Reuse their
layout, rows, sheet chrome and motion; replace their demo state with the real stores. Delete
the Claude-only parts you don't use (rg every deleted symbol; their tests in
`Packages/PaseoUI/Tests` too if they only cover deleted code).

## M4a: Settings (branch `m4a-settings`)

Replace the small settings sheet that M2.5b/M2.6a put in `Chat/PaseoSidebar.swift`
(`ClaudeSidebarSettingsSheet` or similar; keep its Appearance, Your name and Host sections) with a
full Settings screen built from `ClaudeSettingsView`'s structure, opened from the sidebar avatar.
Sections, by Paseo's app (`docs/research/01-app-features.md` "Settings"):
- **General**: Appearance (System/Light/Dark), Your name, haptics on/off.
- **Host**: connection state, server id, daemon version (from `serverInfo`), Disconnect
  (destructive, confirmation). Daemon config from `session.hostSettings` (`HostSettingsStore`):
  show what's readable; allow edits only for fields the store can patch (respect revision).
- **Providers**: every provider from `session.agentControl` with status (ready/loading/error/
  disabled), model count; enable/disable only if the store supports it.
- **About**: app version, links to the repos.
Each section a pushed page in ClaudeUI's settings style. Settings rows use `@AppStorage` keys
that already exist (don't rename keys the app already reads; `rg` for them).

## M4b: Schedules (branch `m4b-schedules`)

The sidebar's "Scheduled" row opens a Schedules screen built from `ClaudeRoutinesView` on
`session.schedules` (`SchedulesStore`, see `docs/tickets/PHASE3-BACKEND.md` T9 and doc 04):
list (name, cadence in words like "Every day at 9:00", next run, paused state), detail (prompt,
target workspace, provider/model, run history/logs), create/edit (name, prompt, cadence picker
with presets + custom cron, timezone, max runs, provider/model/mode/thinking via the existing
pickers in `AgentControlStore`, target workspace), pause/resume, run now, delete (confirmation).
Replace the "Coming soon" sheet for Scheduled. Write a small cron → words formatter with unit
tests in `Packages/PaseoUI/Tests/PaseoUITests` (pure Swift, it can't run here but must parse) or,
better, put the formatter in a pure file you can also test by copying into a scratch SwiftPM
package under /tmp and running it with `swift test` there; say which.
