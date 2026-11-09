# R15: relay + pairing research (no app code)

Branch `r15-relay-research`. Output: `docs/research/11-relay-pairing.md` only. Cite path:line for
every claim (`/home/paseo/dev/paseo-reference/packages`: server relay/pairing code, the relay
service if present, protocol `messages.ts`, app `pairing`/`add-host`/`welcome` flows, i18n).

Answer, precisely enough that a later ticket can be built from it:
1. How Paseo's relay works end to end: who hosts the relay, how the daemon registers, the
   pairing offer format (`#offer=` links, QR payload, protected offers + password), key exchange
   and the E2E encryption scheme (algorithms, key sizes, nonces, framing), how the client then
   speaks the normal daemon protocol through the relay, reconnect behaviour.
2. What the daemon config must have (`relay.enabled`, `requireProtectedSecurity`, …) and what
   the host settings Pair device page does (generate offer/QR). Is it on for daemon 0.15.2?
   Read-only check of this host's daemon config/server_info is fine; do NOT enable anything,
   generate pairing offers, or change config.
3. What it takes in this client: which crypto primitives, and whether Apple CryptoKit covers them
   (it does not build on Linux: say how we'd test the crypto here; `swift-crypto` would be a new
   dependency, which needs the lead's approval: weigh it). Where it fits (PaseoKit transport
   under `DaemonConnection`), QR scanning on iOS (VisionKit/AVFoundation), pasteboard link flow,
   host confirmation sheet with fingerprint rows (upstream wording).
4. Security notes: what a mistake would expose, test vectors you can extract from upstream tests.
5. A proposed ticket split (backend crypto + transport, pairing UI, host settings Pair device),
   with risks.

No app code, no config changes, no background tasks or subagents; don't end your turn while
waiting. Commit "R15: relay research", don't push. Final message: a one-screen summary + the
dependency recommendation.
