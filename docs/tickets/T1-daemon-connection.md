# T1: DaemonConnection

Implement `DaemonConnection` and `URLSessionWebSocketTransport` in PaseoKit, write their tests,
and build a small live probe.

## Files you own

- `Packages/PaseoCore/Sources/PaseoKit/DaemonConnection.swift` (fill in the bodies; add private helpers)
- New files in `Packages/PaseoCore/Sources/PaseoKit/` if you want to split the code
- `Packages/PaseoCore/Sources/paseo-probe/main.swift`
- New files in `Packages/PaseoCore/Tests/PaseoKitTests/`

Read but don't change: `DaemonClient.swift`, everything in `Sources/PaseoProtocol/`.

## Behavior

**connect()**
1. State → `.connecting`. Create the transport with `transportFactory(endpoint.url)`.
2. Start one receive loop for this transport (see Routing).
3. Send `Hello(clientId:appVersion:credential:)` JSON-encoded as the first text frame.
4. Wait for the `server_info` status message (`InboundHeader.status == "server_info"`), at most
   `configuration.helloTimeout`. Decode it with `SessionPayloadEnvelope<ServerInfo>`.
   State → `.connected(info)`. Return `info`.
5. If a `hello.rejected` frame arrives (decode `HelloRejected` from the frame itself, it's not
   session-wrapped), or the socket closes with code 4401 before `server_info`: throw
   `ConnectionError.rejected(reason:)`, state → `.failed`, and do **not** reconnect. For a 4401
   close without a rejected frame, use the close reason, or `password_required` if empty.
6. Other failures before `server_info`: throw (`.timeout`, `.transport`, `.closed`), state → `.failed`.

**send(_:timeout:)**
- If not `.connected`, throw `.disconnected` right away.
- Set a fresh `requestId` (UUID string), encode `SessionRequestEnvelope(request)`, register the
  pending request **before** sending, then send.
- Resolve when a frame arrives whose `InboundHeader.requestId` matches. Decode
  `SessionPayloadEnvelope<R.Response>`; a decoding failure throws `.protocolViolation(description)`.
- After `timeout`, throw `.timeout` and forget the request; a late response is dropped silently.
- Responses can arrive in any order.

**Routing** (receive loop; never let one bad frame stop the loop)
- Binary frames: ignore.
- Text: decode `InboundHeader`. Undecodable text: ignore.
- `type == "pong"`: ignore. `type == "hello.rejected"`: see connect.
- Session messages: `server_info` resolves the hello; a `requestId` that matches a pending request
  resolves it; otherwise emit an event:
  - `agent_stream` → `.agentStream(payload)` (`SessionPayloadEnvelope<AgentStreamPayload>`)
  - `agent_update` → `.agentUpdate(payload)`
  - `agent.timeline.replacement` → `.timelineReplacement(agentId:epoch:)` (payload has both)
  - anything else, or a known type that fails to decode → `.unhandled(messageType:raw:)`

**Keepalive and reconnect**
- While connected, send `{"type":"ping"}` every `pingInterval`.
- Any received frame counts as life. No frame for `idleTimeout` → treat the socket as dead.
- When a connected socket dies or closes (not via `disconnect()`):
  fail every pending request with `.disconnected`, close the old transport, then retry.
  Attempt n waits `min(reconnectBaseDelay * 2^(n-1), reconnectMaxDelay)` + up to 20% jitter.
  State → `.reconnecting(attempt: n, lastError:)` before each wait. Each attempt runs the same
  hello handshake. Success → `.connected(info)` and the attempt counter resets. A rejection
  during reconnect → `.failed(.rejected…)` and stop. Keep retrying any other failure.
- `disconnect()`: stop everything, fail pending requests with `.disconnected`, close the transport
  with code 1000, state → `.idle`. A later `connect()` works again.

**Streams**
- `events` and `states` are each created once in `init` (`AsyncStream.makeStream`). `states`
  yields `.idle` immediately, then every change. Don't yield the same state twice in a row.
- Use buffering policy `.unbounded` for events (the store must not miss a delta).

**URLSessionWebSocketTransport**
- Wrap `URLSessionWebSocketTask`. Import `FoundationNetworking` when `canImport` (Linux).
- Set `maximumMessageSize` to 64 MiB; the default (1 MiB) is too small for timeline pages.
- `receive()` maps `.string`/`.data` to `WebSocketFrame`. When the task has closed
  (`closeCode != .invalid`), throw `WebSocketClosed(code:reason:)` with the close code and the
  UTF-8 close reason.
- `close(code:)` cancels with that close code.

**Concurrency.** The class is `@unchecked Sendable`; protect all mutable state with one lock
(`Synchronization.Mutex` or `NSLock`) or move it into a private actor. Never hold a lock across an
`await`. No data races, no warnings under Swift 6.

## Tests (new files in Tests/PaseoKitTests)

Write a `FakeTransport` (scripted inbound frames, records outbound frames, can simulate a close)
and a factory that counts how many transports were created. Use small `Configuration` timings.
Required cases:

1. Connect returns the `ServerInfo` from `Fixture.data("server_info")`; the first outbound frame
   is a hello with the right `clientId`, `clientType: "mobile"` and password auth.
2. `hello.rejected` with `incorrect_password` → throws `.rejected(reason: "incorrect_password")`,
   final state `.failed`, factory called exactly once even after waiting past the reconnect delay.
3. Close with 4401 before `server_info` → `.rejected`.
4. Two concurrent requests whose responses arrive in reverse order both resolve correctly
   (use `fetch_agents_response` and `send_agent_message_response` fixtures, rewriting `requestId`).
5. Timeout → `.timeout`; a late response afterwards causes no crash and no event.
6. Every frame in `Fixture.streamFrames()` comes out of `events` as `.agentStream`, in order;
   an unknown message type comes out as `.unhandled`.
7. A connected socket closes → pending request fails with `.disconnected`, states go
   `.reconnecting(attempt: 1, …)` then `.connected`, and the factory was called twice.
8. `disconnect()` → state `.idle`, pending request fails with `.disconnected`, no further reconnects.

## paseo-probe (live check)

A command-line smoke test against a real daemon. Usage:

```
swift run paseo-probe [--url ws://127.0.0.1:6767/ws] [--local-credential PATH | --password-env VAR] <command>
  info                     print server id, version, protocol version
  agents                   list agents: id prefix, provider, status, title
  timeline <agentId>       fetch the tail; print one line per entry: seq, type, short text
  watch <agentId> [secs]   subscribe (SetAgentTimelineSubscriptionRequest) and print each
                           stream event's seq and type for N seconds (default 30)
```

Default credential: `--local-credential /home/paseo/.paseo/local-credential`.

## Done when

- `swift build --build-tests` has no errors or warnings in your files.
- `swift test --filter PaseoKitTests` passes, and `FixtureDecodingTests` still passes.
- `swift run paseo-probe info`, `agents`, and `timeline <id>` work against the local daemon
  (pick any agent id from `agents`). Paste their output (trimmed) in your final message.
