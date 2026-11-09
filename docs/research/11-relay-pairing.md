# 11 — Relay transport, E2EE and pairing

**What this is.** Everything a later ticket needs to build the relay path: the hosted relay, how the
daemon registers on it, the pairing-offer format, the key exchange and E2EE framing byte for byte,
what the daemon config must contain, what the upstream "Pair device" page does, and what it costs
in this client (crypto primitives, where the code goes, QR/paste UI, host confirmation).

Citations are `path:line` in the daemon reference checkout, so `packages/...` is relative to it
(checked out at the 0.15.3 tree; the daemon installed on this machine is 0.15.2). Our own files
start with `Packages/` or `App/`. No hostnames, keys, server ids or absolute paths appear here.

**Short version.** The relay is a dumb, untrusted byte pipe. The daemon dials out to it and stays
connected; the phone meets the daemon there. Before any daemon protocol frame moves, the two
endpoints run **`Noise_NK_25519_ChaChaPoly_SHA256`** keyed to the daemon's static X25519 key, which
the pairing offer (a QR code / URL fragment) carries out of band. Every later frame is a
counter-nonced ChaCha20-Poly1305 record with authenticated framing. The daemon's password rides in
the ordinary encrypted `hello` afterwards. The old "legacy" mode (NaCl `box`, XSalsa20-Poly1305, no
replay protection) still exists for old peers; **we should not implement it** — the daemon floor we
care about (0.13.0+) always negotiates protected, and refusing legacy is a supported client policy.

---

## 1. Topology: who hosts the relay

- The production relay is a Cloudflare Worker + one Durable Object per session, deployed at the
  hosted endpoint named by `DEFAULT_RELAY_ENDPOINT` (`packages/relay/wrangler.toml:1-15`: custom
  domain route, `RELAY` DO binding, `new_sqlite_classes = ["RelayDurableObject"]`). The Worker can
  also proxy to a second implementation — the vars block points `PASEO_RELAY_UPSTREAM` at a
  separately hosted service (`wrangler.toml:11-12`, proxied by
  `packages/relay/src/cutover-proxy.ts:5-17`). Nothing about the client changes between them: both
  are WebSocket forwarders.
- The relay forwards frames **unmodified** and knows nothing but routing
  (`packages/relay/src/types.ts:1-8`). Everything security-relevant is endpoint-side
  (`packages/relay/src/secure-channel.ts:1-23`).
- Each `(serverId)` gets its own Durable Object. Protocol **v2** uses three socket shapes
  (`packages/relay/src/cloudflare-adapter.ts:120-135`):
  - daemon **control** socket: `role=server`, no `connectionId`, one per serverId;
  - daemon **data** socket: `role=server&connectionId=…`, one per client connection;
  - client socket: `role=client&connectionId=…` (the relay assigns one if omitted).
- The single URL builder both sides use is `buildRelayWebSocketUrl`
  (`packages/protocol/src/daemon-endpoints.ts:235-258`): `wss://<endpoint>/ws?serverId=…&role=…&v=2`
  (`v` defaults to `"2"`, `daemon-endpoints.ts:77-101`). The relay closes a replaced daemon socket
  with `1008 Replaced by new connection` (`cloudflare-adapter.ts:176-188`).

## 2. How the daemon registers

`startRelayTransport` (`packages/server/src/server/relay-transport.ts:107-401`):

- One **control** WebSocket per daemon. The relay answers control traffic with
  `{type:"sync",connectionIds}`, `{type:"connected",connectionId}`, `{type:"disconnected",…}`
  (`relay-transport.ts:41-46`, `:289-327`).
- On `connected` the daemon opens a **data** socket for that `connectionId` and hands it to the
  daemon's normal socket admission with `transport:"relay"`,
  `externalSessionKey: "session:<connectionId>"` (`relay-transport.ts:342-396`, metadata at
  `:374-380`). That key is what makes reconnects resume instead of creating a new session.
- Keepalive: WebSocket protocol pings every 10 s; stale control (>30 s without a pong) is
  terminated; ready timeout 8 s; data-socket open timeout 15 s
  (`relay-transport.ts:48-57`, `:197-256`, `:358-367`).
- Reconnect: `min(30000, 1000 * attempt)` ms backoff on the control socket
  (`relay-transport.ts:330-340`).
- A client that disappears is not torn down immediately: the daemon keeps the session for
  `EXTERNAL_SESSION_DISCONNECT_GRACE_MS = 90_000` waiting for a reconnect
  (`packages/server/src/server/websocket-server.ts:516`, `:2360-2380`). Relay sockets are
  `lifecycle:"reconnectable"` (`websocket-server.ts:1631`).
- The relay's own half-open repair: if a client connects but the daemon never opens the data
  socket, the DO nudges with `sync` after 10 s and force-closes the control socket 5 s later
  (`cloudflare-adapter.ts:212-243`), and it buffers up to 200 client frames per connection
  (`:245-260`).

## 3. Pairing offer

### Format

```json
{ "v": 2, "serverId": "srv_…", "daemonPublicKeyB64": "<44-char X25519 public key>",
  "relay": { "endpoint": "<relay-host>:443", "useTls": true },
  "minimumSecurityMode": "protected" }        // optional, added v0.13.0
```

Schema: `packages/protocol/src/connection-offer.ts:9-25`. `serverId` is `srv_` + 12 base64url chars
(9 random bytes), persisted at `$PASEO_HOME/server-id`, overridable with `PASEO_SERVER_ID`
(`packages/server/src/server/server-id.ts:23-27`, `:35-83`); it doubles as the relay session id.

The QR payload and the copyable link are **the same string**: the offer JSON, base64url-encoded,
appended as a URL fragment —

```
<appBaseUrl>/#offer=<base64url(json)>
```

`packages/server/src/server/connection-offer.ts:45-52`. `appBaseUrl` defaults to
the hosted web app origin (`packages/server/src/server/pairing-offer.ts:40`) and comes from
`daemon.app.baseUrl` in config otherwise. Because it is a fragment, the web host never receives
the key (upstream `SECURITY.md:20-22`).

Daemon-side generation: `generateLocalPairingOffer` (`pairing-offer.ts:14-73`) — loads/creates the
static keypair (`packages/server/src/server/daemon-keypair.ts:31-69`, JSON `{v:2,publicKeyB64,
secretKeyB64}` at `daemon-keypair.json`, mode 0600), builds the v2 offer, encodes the URL, and
renders a UTF-8 QR block via the `qrcode` package (`packages/server/src/server/pairing-qr.ts:7-18`).
When relay is disabled it returns `{relayEnabled:false, url:null, qr:null}` and no QR at all
(`pairing-offer.ts:27-34`). When `relay.requireProtectedSecurity` is on it stamps
`minimumSecurityMode:"protected"` (`pairing-offer.ts:47-50`) so clients pin before their first
handshake.

### The other accepted shape: `relay://` URIs

`relay://<endpoint>/<serverId>?key=<pub>&ssl=true&security=protected&password=…`, also accepted
inside a `#connect=` fragment (`packages/protocol/src/daemon-endpoints.ts:22-72`). Clients parse
this into the same offer; the `password` query param is the daemon password. Upstream's app accepts
both forms in paste and scan; the scanner only accepts data containing `#offer=`, `#connect=` or
starting with `relay://` (`packages/app/src/hosts/add-host/internal/pair-scan-model.ts:97-103`).

A trailing detail that must be copied exactly: `useTls` is optional in the offer and defaults to
"port == 443" for the hosted relay (`daemon-endpoints.ts:264-271`, applied in
`host-target.ts:74-88`).

## 4. Key exchange and E2EE

Two modes exist (`packages/relay/src/secure-channel.ts:10-23`). A peer that is new on both sides
always lands in `protected`; legacy exists only for old peers and a present-but-invalid `protected`
field never falls back to legacy (`:20`, test at `packages/relay/src/secure-channel.test.ts:414-433`).

### 4.1 Protected mode (what we implement)

`Noise_NK_25519_ChaChaPoly_SHA256`, spec revision 34, implemented token-by-token in
`packages/relay/src/noise/index.ts:1-14`, `:69-72`:

```
NK:  <- s
     ...
     -> e, es
     <- e, ee
```

- **Role:** the phone is the initiator, the daemon the responder. `s` is the daemon's static
  X25519 key from the offer; there is no second identity (`docs/relay-endpoint-security.md:18-22`).
- **Prologue:** the ASCII bytes `paseo-relay-e2ee/1` (`secure-channel.ts:114`). Mixed into `h`,
  then the responder static public key is mixed as the pre-message `s`
  (`noise/index.ts:123-127`).
- **Message 1** (`-> e, es`) is the payload `[0x01][flags]` (2 bytes, version + `binaryCiphertext`
  bit 0), encrypted with the handshake key and carried base64 inside the plaintext JSON hello:

  ```json
  { "type": "e2ee_hello", "key": "<legacy ephemeral pub>",
    "capabilities": { "binaryCiphertext": true },
    "protected": { "v": 1, "message": "<base64 msg1>" } }
  ```

  `secure-channel.ts:153-181`, `:792-805`.
- **Message 2** (`<- e, ee`) is the selected params `[0x01][flags]`:

  ```json
  { "type": "e2ee_ready", "protected": { "v": 1, "message": "<base64 msg2>" } }
  ```

  `secure-channel.ts:477-504`. Outer `capabilities` is ignored in protected mode because it is not
  authenticated (`docs/relay-endpoint-security.md:24`).
- **Rules that fail the handshake:** wrong envelope `v`, unknown params version, reserved flag bits,
  which the daemon *selected* a bit the client did not offer (`secure-channel.ts:281-288`,
  `:799-805`). The `key` field in the hello is a separate legacy ephemeral, present only so an old
  daemon can still complete a legacy handshake; in protected mode it is unused. A modern client
  still has to send a syntactically valid 32-byte base64 key there.
- **Split:** HKDF-SHA256 over the chaining key with two outputs; the initiator sends with the first
  state, receives with the second; the daemon mirrors (`noise/index.ts:196-204`,
  `symmetric-state.ts:53-72`).
- **Nonces:** 12-byte ChaCha20-Poly1305 nonce = 4 zero bytes then the 64-bit counter little-endian;
  the sender reserves `n` synchronously before any await; the receiver advances `n` **only after the
  tag verifies**, so a rejected record does not desynchronise the stream
  (`noise/cipher-state.ts:1-76`). Nonce exhaustion throws rather than wrapping.
- **Keys are zeroed** on close and on split (`cipher-state.ts:61-66`, `noise/index.ts:201-203`,
  `secure-channel.ts:685-691`).

### 4.2 Record framing (per application frame, not per write)

```
chunk plaintext = kind(1) || flags(1) || totalLength(u32 BE) || data
wire record     = (u16 BE ciphertextLength || ciphertext)+
```

`kind` `0x00` text / `0x01` binary; flags bit 0 FIRST, bit 1 FINAL; transport AD is always empty
(`packages/relay/src/protected-records.ts:1-35`, `:46-69`). Constants:

| Constant | Value | Where |
| --- | --- | --- |
| max Noise message | 65535 | `noise/cipher-state.ts:5-6` |
| chunk payload cap | 65513 (`65535 − 16 tag − 6 header`) | `protected-records.ts:31-32` |
| per-chunk overhead | 24 (`2 len + 6 header + 16 tag`) | `protected-records.ts:35` |
| chunk count | `max(1, ceil(len / 65513))` | `protected-records.ts:37-39` |
| wire length | `len + chunks*24` | `protected-records.ts:41-44` |

Receiver-side rejections (all fatal, nothing partial delivered): record not starting with FIRST,
FIRST repeated, kind/length changed mid-record, FINAL flag misplaced, non-final chunk not exactly
65513 bytes, byte total ≠ `totalLength`, trailing bytes, empty record, reserved flags, invalid kind,
and a claimed length that does not match the received wire length *checked before allocation*
(`protected-records.ts:81-198`).

### 4.3 WebSocket representation

Both modes negotiate `binaryCiphertext` (`secure-channel.ts:116-118`, `:166-172`):

| app frame | negotiated | not negotiated |
| --- | --- | --- |
| text | base64 of the record, WS **text** | base64, WS text |
| binary | raw record bytes, WS **binary** | base64, WS text |

`secure-channel.ts:643-668`; upstream `SECURITY.md:25-27`. We always offer it, and a 0.15.2 daemon
always selects it.

### 4.4 Retries, transcripts, close codes

- The client resends **the same hello text** every 1000 ms until a ready arrives
  (`secure-channel.ts:118`, `:205-213`). Sends queued while handshaking are buffered and flushed in
  order after open, capped at 200 (`:119-120`, `:355-363`, `:494-501`).
- The daemon caches the exact hello text and ready text. An **identical** retry gets the identical
  ready and the counters keep running; a **different** hello on an open channel closes with
  `1008 E2EE re-handshake transcript mismatch`; a duplicate ready after open is ignored
  (`secure-channel.ts:571-574`, `:631-641`, `:503-525`; tests
  `secure-channel.test.ts:294-411`). So our client must keep the hello bytes stable across retries
  and must not regenerate an ephemeral per retry.
- A client never answers hellos (`secure-channel.ts:635`).
- Close codes:

| code | who | meaning | where |
| --- | --- | --- | --- |
| `1008` | daemon | `protected endpoint security required` (legacy refused by policy) | `secure-channel.ts:99-100`, `:513-519` |
| `1008` | daemon | re-handshake transcript mismatch | `secure-channel.ts:111-112` |
| `1011` | daemon | record failure | `secure-channel.ts:110` |
| `4002` | client | protected handshake failed / daemon offered only legacy | `secure-channel.ts:101-102`, `:272-277` |
| `4003` | client | inbound record failed auth or framing | `secure-channel.ts:103-108` |
| `4001` | client | channel never opened (our transport maps this) | `packages/client/src/daemon-client-relay-e2ee-transport.ts:203-207` |

  A browser `WebSocket.close` only accepts 1000 or 3000-4999, which is why the client side uses
  4xxx (`secure-channel.ts:103-108`, `docs/relay-endpoint-security.md:50`). URLSession has the same
  restriction in practice — use 4002/4003 here too.
- Daemon admission wraps this in a 15 s handshake timeout (`HANDSHAKE_TIMEOUT_MS`,
  `packages/server/src/server/websocket/secure-relay-ingress.ts:21`, `:60-63`); a policy rejection
  closes with the carried code and logs `relay_e2ee_handshake_rejected` (`:101-110`). Note the
  close code stops at the relay: both relays replace a daemon-side close with their own, so an old
  client just sees a disconnect (`docs/relay-endpoint-security.md:64`).

### 4.5 Legacy mode (do not implement)

Curve25519 ECDH + XSalsa20-Poly1305 (NaCl `box`), random 24-byte nonce prefixed to the ciphertext,
`[nonce(24)][ciphertext]`, wire = base64 text or binary, no replay protection
(`packages/relay/src/crypto.ts:1-13`, `:134-181`;
`packages/relay/src/encrypted-channel.ts:118-129`). A recorded legacy transcript (hello,
credentials, commands) replays onto a fresh daemon channel (`docs/relay-endpoint-security.md:5`,
`:78-80`). XSalsa20 is **not** in CryptoKit, so supporting it would mean writing XSalsa20+Poly1305
by hand. Skip it: refuse a legacy ready with `4002`.

## 5. Speaking the normal daemon protocol through the relay

Once the record channel is open, the frames are exactly the direct-connection frames:
`{"type":"hello",…}`, then `{"type":"session","message":…}`, including binary terminal/file frames.
Nothing is relay-specific except:

- **Credentials.** They go in the encrypted `hello.auth`
  (`packages/protocol/src/messages.ts:7973-7996`: `{kind:"password",password}` or
  `{kind:"localCredential",token}`); the daemon refuses before `server_info`
  (`websocket-server.ts:1884-1934`, `hello.rejected` shape at `messages.ts:8030-8036`). Upstream
  refuses to send relay credentials without E2EE
  (`packages/client/src/daemon-client.ts:1769-1773`).
- **Downgrade check.** `server_info.features.relayProtectedSecurity` is advertised on every session
  (`websocket-server.ts:2025-2026`). A relay client that ended up legacy against such a daemon
  closes with `4002` before admission (`packages/client/src/daemon-client-relay-e2ee-transport.ts:67-101`,
  `:139-153`, reason string `:43`).
- **Size limit.** `MAX_RELAY_WEBSOCKET_MESSAGE_BYTES = 32 MiB` versus `100 MiB` direct
  (`packages/protocol/src/websocket-message-limit.ts:2-5`). The largest *plaintext* frame that
  fits is `maxSecuredPlaintextByteLength(32 MiB) = 25_156_584` bytes (~23.99 MiB)
  (`secure-channel.ts:710-722`). Upstream rejects an oversized send synchronously instead of
  closing the socket (`daemon-client-relay-e2ee-transport.ts:226-240`).
- **Reconnect.** Client backoff is `min(base*2^attempt, max)`, default 1500 ms → 30 000 ms
  (`packages/client/src/daemon-client.ts:1138-1139`, `:7630-7650`), and a relay session resumes
  inside the daemon's 90 s grace window. A fresh socket means a fresh Noise ephemeral and a fresh
  handshake.
- **Pinning.** Upstream persists a per-daemon-identity floor: once a daemon public key negotiated
  `protected`, every later relay connection to that key passes `minimumMode:"protected"`; the floor
  rises in-process too, so a reconnect cannot be downgraded even before the pin is stored
  (`docs/relay-endpoint-security.md:54-66`; `packages/client/src/daemon-client.ts:1472-1493`,
  `:1607-1616`; `packages/app/src/runtime/host-runtime.ts:1526-1540`).

## 6. Daemon config, and this host

Required for any of this: `daemon.relay.enabled: true`. Optional:
`daemon.relay.requireProtectedSecurity` (default `false`), `daemon.relay.endpoint`,
`relay.publicEndpoint`, `relay.useTls`, `relay.publicUseTls`; also settable via
`PASEO_RELAY_ENABLED`, `PASEO_RELAY_ENDPOINT`, `PASEO_RELAY_PUBLIC_ENDPOINT`,
`PASEO_RELAY_USE_TLS`, `PASEO_RELAY_PUBLIC_USE_TLS`
(`packages/server/src/server/config.ts:114-120`, `:303-345`). Defaults: the hosted relay endpoint
`DEFAULT_RELAY_ENDPOINT`, with TLS on for that exact endpoint (`config.ts:39`, `:325-336`). Relay
can also be toggled live over the config RPC (`config.ts:595-596`, `webSocket features.relayConfig`
`websocket-server.ts:2079-2080`) and from the daemon status payload
(`messages.ts:5355-5443`, `daemon.get_status.response.payload.relay`).

**Read-only state of this host** (`$PASEO_HOME`, checked 2026-11-09; nothing changed,
no offer generated):

- `paseo --version` → `0.15.2`.
- `$PASEO_HOME/config.json` → `daemon.relay = { "enabled": true }`. No `endpoint`,
  `publicEndpoint`, `useTls`, `publicUseTls` overrides, and **no `requireProtectedSecurity`**, i.e.
  `false`: the daemon currently still admits legacy relay clients.
- `$PASEO_HOME/daemon-keypair.json` exists with `v: 2` and 44-char `publicKeyB64`/`secretKeyB64`
  (32-byte X25519 keys): pairing offers are possible without touching anything.
- 0.15.2 ships protected mode, so this daemon advertises
  `features.relayProtectedSecurity: true` and always negotiates `protected` with a modern client.
- For a later ticket that wants an end-to-end relay test: generating a pairing offer is the only
  way to get `serverId` + the daemon public key, and it is on the ticket's forbidden list here.
  That test needs explicit permission (read `$PASEO_HOME/server-id` and the keypair file, or issue
  `daemon.get_pairing_offer.request`).

## 7. What the upstream host settings "Pair device" page does

`packages/app/src/desktop/components/pair-device-section.tsx` (a desktop modal in upstream; the
feature it exercises is daemon-side and version-gated):

1. Gate on features: `daemonStatusRpc` for the RPC, `relayConfig` for the toggle
   (`pair-device-section.tsx:51-53`).
2. `daemon.get_pairing_offer.request {requestId}` → `daemon.get_pairing_offer.response
   {requestId, url, qr, relayEnabled}` (`packages/protocol/src/messages.ts:1489-1492`, `:5439-5448`;
   daemon handler `packages/server/src/server/session/daemon/daemon-session.ts:233-269`). The daemon
   renders `qr` as a UTF-8 block of `\u001b` colour codes — useful only in a terminal; the app
   ignores it and re-renders the URL itself.
3. The app renders the URL as an SVG QR (`type:"svg", errorCorrectionLevel:"M", margin:1`) and
   caches it for 5 minutes (`pair-device-section.tsx:78-89`); `Copy` puts the URL on the
   clipboard (`:91-105`).
4. When relay is off: "Relay is not enabled. Enable relay to pair a device.", an "Enable relay?"
   confirmation, `patchConfig({relay:{enabled:true}})`, then refetch
   (`:67-76`; wording `packages/app/src/i18n/resources/en.ts:1969-1984`). If `relayConfig` is
   missing it says "Update the host to enable relay…" (`en.ts:1983`).
5. Always shown next to the code: "Treat this pairing link like a password. Anyone with it can
   access this daemon." (`en.ts:1987-1988`), plus "Scan this QR code with Paseo on your phone, or
   copy the link below." (`en.ts:1985-1986`).

## 8. What it takes in this client

### 8.1 Crypto primitives

| need | algorithm | params | CryptoKit (iOS)? | on Linux? |
| --- | --- | --- | --- | --- |
| X25519 ephemeral keygen + DH | Curve25519 | 32-byte keys | `Curve25519.KeyAgreement` | no |
| HKDF, 2×32-byte outputs | HMAC-SHA256 | salt = chaining key, empty info | `HKDF<SHA256>.deriveKey` | no |
| handshake hash | SHA-256 | 32 bytes | `SHA256.hash` | no |
| transport AEAD | ChaCha20-Poly1305 | 12-byte nonce, 16-byte tag, arbitrary AAD | `ChaChaPoly` | no |

CryptoKit has everything protected mode needs and **nothing** legacy mode needs. But CryptoKit
does not exist on Linux, so with the current "Foundation only, builds and tests on Linux" rule the
crypto could not be built or tested here at all — and the ticket's own rule 6 forbids untested
platform branches. Options:

1. **`swift-crypto` (recommended).** Apple's own open-source implementation of the *CryptoKit API*
   (module `Crypto`), builds on Linux, iOS and macOS from the same source. The code we write is the
   same `Curve25519.KeyAgreement` / `HKDF` / `ChaChaPoly` code on every platform, and the Noise and
   record tests run here under `swift test`. `HKDF<SHA256>.deriveKey(inputKeyMaterial:salt:info:
   outputByteCount:)` is byte-identical to Noise's `HKDF(ck, ikm, 2)`: extract with the chaining key
   as salt, expand with empty info, `T(1)=HMAC(PRK,0x01)`, `T(2)=HMAC(PRK,T(1)||0x02)` — compare
   `packages/relay/src/noise/symmetric-state.ts:66-72`. Same for `ChaChaPoly.seal(_:using:nonce:
   authenticating:)` against `noise/cipher-state.ts:33-51`.
2. Hand-rolled X25519 + ChaCha20-Poly1305 + SHA-256 in Swift. Rejected: constant-time field
   arithmetic and AEAD are exactly the things not to write by hand.
3. CryptoKit behind `#if canImport(CryptoKit)` and nothing on Linux. Rejected: the transport would
   be untestable on this machine, and rule 8 requires the tests to run here.

So: **ask the lead to approve `swift-crypto` (one dependency, Apple-maintained, package
`.package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0")`) added to the
`PaseoKit` target only.** It is the smaller of the two risks, and it also gives a Linux CI story.
Fallback if the answer is no: the whole relay feature is blocked on Linux verification, not just
slower.

### 8.2 Where it fits

- New files in `Packages/PaseoCore/Sources/PaseoKit/Relay/`: `ConnectionOffer` (parse `#offer=`,
  base64url, `relay://`, TLS default), `NoiseNK` (handshake state machine), `RelayRecordCodec`
  (chunk framing), `RelayChannel` (handshake driver, retry, close codes, pending-send buffer) and
  `RelayWebSocketTransport: WebSocketTransport`.
- `RelayWebSocketTransport` wraps the existing `URLSessionWebSocketTransport`
  (`Packages/PaseoCore/Sources/PaseoKit/DaemonConnection.swift:947-1029`) pointed at the relay URL
  and conforms to `WebSocketTransport` (`DaemonClient.swift:111-125`), so `DaemonConnection`
  (`DaemonConnection.swift:14-40`, factory at `:67`) needs only an endpoint change — exactly the
  seam `ARCHITECTURE.md` promises.
- **Pull vs push.** `WebSocketTransport.receive()` is request/next-frame; the relay channel is
  callback-driven and a handshake must complete before the first application frame. Adapt with an
  `AsyncStream<WebSocketFrame>` plus a small state machine: frames arriving before the caller's
  first `receive()` are buffered; `send` while handshaking queues (cap 200); `receive` throws
  `WebSocketClosed` carrying 4002/4003 so `DaemonConnection` reports the real reason
  (`DaemonClient.swift:127-131`). Do not surface channel errors before the close code — upstream
  learned that the hard way (`daemon-client-relay-e2ee-transport.ts:186-197`).
- Outbound size check in `send` using the framed wire length; reject `> 32 MiB` rather than closing.
- `DaemonEndpoint` (`DaemonClient.swift:9-24`) is URL+credential today. A relay endpoint needs
  `serverId` + `daemonPublicKeyB64` + `minimumSecurityMode` alongside the URL; add them as optional
  fields or a sibling `case relay(offer:)` — a decision for the transport ticket, since it changes a
  public type in PaseoKit.
- `App/Sources/SavedHosts.swift` keys hosts by URL (`:62-101`) and stores the password per host id
  (`:107-118`). Relay hosts must key on `serverId` + daemon public key instead, or every re-pair
  creates a duplicate host and loses the password. Also needs the pinned
  `minimumSecurityMode` and a "known key" record.

### 8.3 Pairing UI on iOS

- **QR scan:** `VisionKit.DataScannerViewController` (`barcodeSymbologies: [.qr]`, iOS 16+, A12+) is
  the least code; `AVFoundation` + `AVCaptureMetadataOutput` is the fallback if we want a custom
  camera UI and deterministic tests. Permission string
  `NSCameraUsageDescription` must mirror upstream's wording ("Allow camera access to scan the
  pairing QR code from your daemon.", `en.ts:1962`). Scan → validate the payload (`#offer=`,
  `#connect=`, `relay://`) → start one pairing attempt and stop scanning until the attempt ends,
  so the same code in view does not retrigger (`pair-scan-model.ts:1-16`).
- **Paste:** `UIPasteboard` link/paste prompt into the same parser; the offer lives in the fragment
  so nothing is sent anywhere (`SECURITY.md:20-22`). Password prompt only after the probe fails
  with `password_required`/`incorrect_password` (`host-runtime.ts:2129-2150`).
- **Confirmation sheet** before saving a new host or a changed key/relay/TLS setting. Upstream
  wording, port verbatim (`en.ts:1840-1850`):
  - title "Connect to this host?"
  - body "This host will be able to run code in this app and reach your other connected hosts. Only
    connect if you recognize it." / changed: "This link changes how you connect to this host. …"
  - rows: "Host" = serverId, "Key fingerprint" = formatted key, "Relay" = endpoint
    (`host-confirmation-sheet.tsx:28-46`).
  - Fingerprint format: strip non-alphanumerics from the **public key string itself** (not a hash),
    groups of four; if longer than 16 chars show `first 8 … last 8`
    (`host-confirmation.ts:87-97`). Do not "improve" this into a SHA-256 digest — the user compares
    it against what the daemon shows.
  - A link that matches a saved host exactly asks nothing (`host-confirmation.ts:58-69`); one
    question at a time, newer cancels older (`:71-78`).
- Entry points to mirror: welcome screen offers Scan QR / Paste pairing link / Direct / Remote SSH
  (`packages/app/src/components/welcome-screen.tsx:192-244`), add-host sheet
  (`add-host/internal/add-host-method-modal.tsx:45-80`), both labelled "Encrypted relay connection."
  (`en.ts:1862-1867`).

### 8.4 Host settings "Pair device"

For a later UI ticket: `daemon.get_pairing_offer.request` (needs `features.daemonStatusRpc`), render
our own QR from `url`, copy button, "Treat this pairing link like a password…" warning, and an
"Enable relay?" flow behind `features.relayConfig` via `set_daemon_config_request` with
`{relay:{enabled:true}}` (`messages.ts:258-266`, `:198-205`). Never log or persist the offer URL.

## 9. Security notes

What a mistake exposes:

- **Accepting a legacy ready when the offer pinned protected** = silently dropping replay
  protection; a recorded transcript can be replayed onto that daemon. Client side: treat it as
  `4002` and stop reconnecting, exactly as upstream does
  (`docs/relay-endpoint-security.md:56-64`, `:78-80`).
- **Skipping the `minimumSecurityMode` pin on re-import** = the same downgrade, later, without the
  user noticing. The pin belongs to the daemon identity (public key), not the relay address
  (`docs/relay-endpoint-security.md:58`).
- **Trusting the relay's `server_info` before authenticating it** = MITM. The daemon identity is
  only proven by msg2 decrypting; do the `relayProtectedSecurity`/downgrade check *after* the
  channel is open, never on a plaintext frame.
- **Nonce reuse** (reusing a sender state across a reconnect, or reusing one ephemeral for a new
  hello) breaks ChaCha20-Poly1305 outright. One channel per socket, one ephemeral per channel;
  never re-send a *different* hello on the same socket (the daemon closes with 1008 anyway).
- **Releasing frames on a failed record** = delivering unauthenticated data; framing violations
  must close and drop everything from that record.
- **Logging the offer URL / daemon public key / password** turns a log into a credential. The URL
  *is* the trust anchor (`SECURITY.md:39-44`).
- **A leaked pairing link is not full access** if the daemon has a password: the password rides
  inside the encrypted hello, so a leaked link alone fails admission
  (`SECURITY.md:44-45`).
- **Host confirmation is a security control**, not a nicety: it is the only place a user can notice
  that a link carries a different key than the host they think they are adding.

### Test vectors we can copy

- **Noise NK vectors** (real third-party vectors from rweather/noise-c "cacophony"):
  `packages/relay/src/noise/fixtures/nk-25519-chachapoly-sha256.json` — per vector:
  `init_prologue`, `init_ephemeral` (secret), `init_remote_static`, `resp_prologue`,
  `resp_static` (secret), `resp_ephemeral` (secret), and `messages[]` of
  `{payload, ciphertext}` where the first two are handshake messages and the rest are transport
  messages alternating directions. The consumer test is `noise/noise.test.ts:19-58`. Copy the file
  into `Tests/PaseoFixtures` and assert msg1/msg2 bytes and each transport ciphertext exactly.
- **X25519 low-order/unsupported points** to reject: `crypto.test.ts:84-112`
  (`00…00`, `01 00…00`, `e0eb7a…`, `5f9c95…`, `ec ff…7f`, `ed ff…7f`, `ee ff…7f`).
- **Non-canonical base64 rejection** for the public key (`crypto.test.ts:47-58`): length must be a
  multiple of 4, canonical alphabet, and re-encoding must round-trip.
- **Record framing**: round-trip and every malformed case in `protected-records.test.ts:1-175`
  (>65513-byte frames, split chunks, trailing bytes, flags, kind, length mismatch).
- **Handshake semantics**: identical-hello retry keeps counters, different hello closes 1008,
  recorded transcript cannot replay into a fresh daemon channel, stripped `protected` does not
  downgrade, protected-only client refuses legacy — `secure-channel.test.ts:294-411`, `:414-571`;
  retry stopping after close/rejection `handshake-lifetime.test.ts:24-59`.
- **Legacy vectors** (not needed if we skip legacy): `encrypted-channel.test.ts` and the
  `[nonce][ciphertext]` 40-byte overhead constant (`encrypted-channel.ts:121-129`).

## 10. Proposed ticket split

1. **R16 — relay crypto core (PaseoKit, Linux-testable).** Add `swift-crypto` (needs approval).
   `NoiseNK` (initiator only, prologue `paseo-relay-e2ee/1`, params `[0x01][flags]`, split, nonce
   discipline), `RelayRecordCodec` (encode/decode with all the rejection rules),
   `ConnectionOffer` (parse/validate `#offer=`, `relay://`, TLS default, key/base64 validation),
   plus tests against the vendored NK vectors, the low-order point list and the framing cases.
   No sockets, no UI.
2. **R17 — relay transport + reconnect + pinning.** `RelayWebSocketTransport` over the base
   `URLSessionWebSocketTransport`, hello retry/transcript stability, pending-send queue, 32 MiB
   bound, 4002/4003 mapping, `server_info.relayProtectedSecurity` downgrade check, `DaemonEndpoint`
   relay shape, minimum-mode floor and its persistence. Tests with a scripted fake daemon transport
   (the NK responder side is needed in the test target only — or reuse a captured transcript).
3. **R18 — pairing UI (App + PaseoUI).** Scan (VisionKit), paste, password prompt, host
   confirmation sheet with the three rows and upstream wording, `SavedHosts` identity change to
   `serverId` + key, completed-host state. Cannot be compiled here; needs an Xcode pass.
4. **R19 — host settings Pair device.** `daemon.get_pairing_offer` request type in PaseoProtocol,
   QR rendering, copy, security warning, enable-relay flow behind `relayConfig`.

Risks, in order: (a) the dependency decision blocks every test in 1–2; (b) `relay://` + password
handling is easy to get wrong and is a credential path; (c) no end-to-end relay test is possible
without permission to read the host's offer material — otherwise R17 is verified only against fakes;
(d) 4002/4003 close-code fidelity matters more than it looks (a wrong code means silent reconnect
loops or a stuck "connecting" state); (e) the daemon still admits legacy clients
(`requireProtectedSecurity` is off on this host), so a client bug that accepts legacy is exploitable
until that flag is flipped; (f) `SavedHosts` URL-keyed identity will silently break re-pairing if
R18 forgets it.

## 11. Not verified here

- No relay connection was made from this machine and no offer was generated (ticket rule). The
  host state in §6 is from the config and keypair files plus `paseo --version` only.
- `swift-crypto` is not in the local package cache; nobody has built the Noise code with it on this
  box yet. The `HKDF`/`ChaChaPoly` equivalence arguments above are from the spec and the upstream
  implementation, and are the first thing R16 should prove with the vendored vectors.
- VisionKit / camera specifics and all of `Packages/PaseoUI` + `App/` are unbuilt here.
