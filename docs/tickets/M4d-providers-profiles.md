# M4d: providers and agent profiles in Settings

Branch `m4d-providers`. Backend parts follow `docs/tickets/PHASE2-CONVENTIONS.md` (sandbox-only,
scrubbed fixtures, tolerant decoding, observable errors, tests). UI rules: top of
`docs/tickets/M3-workspace-panel.md`. Update the Agents & models rows in `docs/PARITY.md` in the same
commit. You may edit `Chat/PaseoSettingsView.swift`, new files (e.g. `Settings/…`), new
PaseoProtocol/PaseoStore files, `HostSettingsStore.swift` (additive only). Do not edit
`ClaudeChatView.swift` or `Sidebar/*`. Reference: `docs/research/01-app-features.md:296-323`,
`docs/research/04-protocol-agents-permissions-settings.md` §8 (8.1–8.4), upstream
`packages/app/src/screens/settings/` providers + profiles.

1. **Providers page** (Settings → host → Providers): each provider with status (available,
   needs install/login, disabled), an enable/disable switch (store already has it,
   `HostSettingsStore.swift:104-117`), tap → **Provider sheet**: diagnostic text
   (`provider_diagnostic_request`, mono, copyable), discovered models list (from §8.1/8.3) with
   add/remove where the host supports it, **Add custom model** (Model ID field), Refresh
   (`refresh_providers_snapshot_request`). Gate everything on the features §8 names.
2. **Agent profiles** (store reads them already; see PARITY row): list, add, edit (name,
   provider, model, mode, thinking), reorder, delete, persisted the way upstream does (daemon
   config write if that is how upstream stores them; else say so and stop at read-only list).
   If the new-agent flow can take a profile, add a "Profile" picker there only if it lives
   outside `ClaudeChatView.swift`; otherwise list it as a follow-up.

Full PaseoCore `rm -rf .build && swift build --build-tests && swift test`; swiftc -parse every
touched UI file. Commit "M4d: providers and profiles", don't push. Final message: what changed,
test counts, store gaps, unsure-compile spots.
