# R17: relay transport, reconnect, pinning

Branch `r17-relay-transport`. Spec: `docs/research/11-relay-pairing.md` §10 item 2 and the sections
it references; builds on your R16 (`PaseoKit/Relay`). Also patch doc 11 for the three points you
raised in R16 (§4.2 trailing-bytes reachability, relay:// userinfo rejection, swift-crypto
`SymmetricKey` not Sendable).

Build `RelayWebSocketTransport` under `DaemonConnection` exactly as §10.2 says: hello with
byte-identical retry every 1 s, pending-send queue, 32 MiB bound, close codes (1008/1011 daemon,
4002/4003 client) mapped to clear `DaemonConnection` states (no silent reconnect loops, no stuck
"connecting"), the `server_info.relayProtectedSecurity` downgrade check, `DaemonEndpoint` relay
shape, the minimum-security floor and its persistence (no secrets in UserDefaults: key material
and passwords go through the existing Keychain path the app uses for saved hosts, via a protocol
PaseoKit can test with a fake). Owned subscriptions (T17) must work unchanged over the relay.

Tests with a scripted fake transport; put the NK responder in the test target only. A live relay
connection is NOT allowed in this ticket (it would need this host's offer material). Done = `rm
-rf .build && swift build --build-tests && swift test` green, no warnings. No background tasks or
subagents; don't end your turn while waiting. Commit "R17: relay transport", don't push. Final
message: state machine summary, close-code mapping table, test totals, what R18 must know.
