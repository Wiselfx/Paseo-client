# R18: pairing UI (scan, paste, confirm) + saved-host identity

Branch `r18-pairing-ui`. Read `AGENTS.md`, `ARCHITECTURE.md`, `docs/research/11-relay-pairing.md`
(§3 offer, §8.2–8.3 UI, §9 security, §10 item 3) and the "What R18 must know" list below (from R17).
Shared UI rules: top of `docs/tickets/M3-workspace-panel.md`. Wording: port upstream `en.ts`
verbatim (cite lines); never invent copy. Update PARITY rows (add-host methods, Scan QR, Paste
pairing link, Host confirmation sheet, Relay transport) and recount.

iPhone is the target. Keep it calm and native: one sheet, few steps.

## Hard safety rules

- Never read, print or copy this host's keypair or any real offer/pairing link into the repo, tests,
  logs or your messages. Tests use generated keys only (see `RelayResponderFake.swift`).
- No live relay connection, no relay enable, no daemon config change.
- The user's existing saved host must survive the `SavedHosts` migration untouched (same id,
  URL, password in Keychain). Write a migration test for an old-format JSON blob.
- Passwords live only in Keychain, never in UserDefaults/JSON, never logged.

## What R17 gives you (use it, don't rebuild it)

1. `try offer.makeEndpoint(secrets:pins:)` builds a relay `DaemonEndpoint`; never hand-build one.
   `DaemonConnection`'s default factory already wraps relay sockets.
2. `SavedHosts` must key relay hosts on `serverID` (+ daemon key), not URL, or re-pairing
   duplicates the host and loses the password.
3. Back `RelayPinStore` with UserDefaults (one JSON array); back `RelaySecretStore` with the
   existing `Keychain` enum via a tiny adapter struct.
4. After a successful connect: `pins.record(offer)`. `.daemonKeyChanged(previousB64:)` → show the
   changed-link confirmation **before** overwriting.
5. `.failed(.closed(4002/4003, _))` is terminal (say so plainly); 4001 is a normal reconnect.
6. Relay caps a plaintext frame at ~25 MB (32 MiB wire). Make the file-upload path cap its chunk
   size when `endpoint.relay != nil` so large uploads don't die with `frameTooLarge`. This one is in
   PaseoCore and needs a test.

## UI

1. **Add host** (welcome screen + the existing add-host entry): methods Direct (exists) / Scan QR
   code / Paste pairing link, the relay ones labelled with upstream's "Encrypted relay connection."
   No Remote SSH (iOS has no SSH tunnel; mark that PARITY part n/a with a reason).
2. **Scan**: `VisionKit.DataScannerViewController` QR only, wrapped in a small
   `UIViewControllerRepresentable`; one attempt at a time (stop recognizing until it ends);
   unsupported device / denied camera → plain message + offer Paste instead. Add
   `NSCameraUsageDescription` with upstream's wording to the App's Info settings (xcodegen
   `project.yml`).
3. **Paste**: `PasteButton` (no pasteboard prompt) or a text field; same parser as scan.
4. **Password prompt** only when the probe fails with password required/incorrect (doc 11 §8.3).
5. **Confirmation sheet** "Connect to this host?" with the three rows (Host = serverId, Key
   fingerprint in upstream's exact format, Relay = endpoint), the new vs changed-link body text,
   exact-match link asks nothing. Port wording and the fingerprint rule verbatim (doc 11 §8.3).
6. Connected relay hosts show the existing host badge/Connections row like direct ones; the
   Connections page shows "Encrypted relay" for them (upstream wording if it exists).

## Done

PaseoCore `rm -rf .build && swift build --build-tests && swift test` green with new tests
(SavedHosts migration/identity logic must live where it can be tested; move pure logic into
PaseoKit/PaseoStore if `App/` can't be tested), `swiftc -parse` every touched UI/App file,
`Tools/api-audit` no new real findings. No background tasks or subagents; don't end your turn while
waiting. Commit "R18: pairing UI", don't push. Final message: what changed, migration behavior,
upstream wording sources (path:line), unsure-compile spots. A DeepSeek reviewer will check this
branch before merge, so be precise about what you verified and what you didn't.
