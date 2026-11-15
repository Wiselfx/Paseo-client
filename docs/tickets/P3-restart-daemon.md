# P3: Restart daemon and "restart required" after config edits

Read `AGENTS.md`, then `docs/tickets/_P-common.md`, then this file.

## Items
- **X-002** (LEDGER-EXTRA): upstream's Settings → host → Overview has "Restart daemon" (`public-docs/configuration.md`,
  `troubleshooting.md`). Port it with upstream's exact copy from `en.ts` (search `restart` near lines 3076-3115: hint,
  confirmation, offline message, failure messages, unable-to-reconnect). Use the existing restart RPC if the wire type exists
  in `Packages/PaseoCore/Sources/PaseoProtocol`; if it does not, find the upstream request (`packages/protocol/src/messages.ts`)
  and add the minimal request/response type next to the host-settings types.
- **X-003** (LEDGER-EXTRA): config saves must report `restartRequiredPaths` / what needs a restart so a saved but inactive setting
  does not look applied. Show it where the setting is saved, with upstream's wording, and offer the same Restart action.
Ignore the plugin pages (not in scope).

## Owns
`Packages/PaseoCore/Sources/PaseoStore/HostSettingsStore.swift`, the matching wire file in `PaseoProtocol` (only to add the restart
request if missing), `Packages/PaseoUI/Sources/PaseoUI/Settings/OverviewPage.swift` and the settings page that saves config.
Commit: `P3: restart daemon and restart-required feedback`.
