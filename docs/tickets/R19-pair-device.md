# R19: Host settings → Pair device

Branch `r19-pair-device`. Read `AGENTS.md`, `ARCHITECTURE.md`, `docs/research/11-relay-pairing.md`
§7 (what upstream's page does), §8.4, §9, and the shared UI rules at the top of
`docs/tickets/M3-workspace-panel.md`. Port upstream wording verbatim from `en.ts` and the upstream
pair-device page (cite path:line); never invent copy. Update PARITY rows ("Pair a device",
"Host settings → Pair device page") and recount.

## Hard safety rules

- Never call `daemon.get_pairing_offer` or `set_daemon_config_request` against the real daemon, and
  never read this host's keypair/config. Tests use fixtures you write by hand from the schema
  (`messages.ts`), with fake keys and `srv_FIXTURE`-style ids.
- The offer URL is a credential: never log it, persist it, put it in error strings or analytics.
  Keep it in view state only; clear it when the page closes.

## Work

1. **PaseoProtocol:** `daemon.get_pairing_offer` request/response types exactly per `messages.ts`
   (cite lines), gated on `features.daemonStatusRpc`. Wire tests (encode + decode, error shape).
2. **PaseoStore:** a small store (or a `HostSettingsStore` method, whichever matches the existing
   pattern) to fetch the offer on demand; phase idle/loading/loaded/failed; no caching across
   page visits. Tests with the fake client.
3. **UI** (Settings → host → "Pair device", only when the daemon supports it): the QR rendered
   locally with Core Image (`CIFilter.qrCodeGenerator`, crisp: `interpolation(.none)`, scaled), the
   link with a Copy button (`UIPasteboard`, mark it `.localOnly` + short expiration if available),
   upstream's "Treat this pairing link like a password…" warning verbatim. Reveal-on-tap for the QR
   is fine if upstream does something similar; otherwise show it directly.
4. **Relay disabled:** if the offer response says relay is off, show upstream's "Enable relay?"
   copy and a button that sends `set_daemon_config_request {relay:{enabled:true}}` behind
   `features.relayConfig`, with a confirmation dialog. Unit-test the request it builds; do not run it.

iPhone first: one calm page, the QR big and centered, nothing else competing.

Done = `swiftc -parse` touched UI files, PaseoCore `rm -rf .build && swift build --build-tests &&
swift test` green, `Tools/api-audit` no new real findings. No background tasks or subagents; don't
end your turn while waiting. Commit "R19: pair device", don't push. Final message: what changed,
wording sources, unsure-compile spots (be careful with exact Apple API signatures:
`swiftc -parse` does not catch wrong labels; a reviewer checks them).
