# T8: Terminals and scripts

Live terminals in a workspace: list, create, attach with replay, type, resize, kill, and the
workspace scripts panel. The app will render with SwiftTerm, which consumes raw bytes, so the
store's job is to deliver an ordered byte stream per terminal and accept input. Read
`PHASE2-CONVENTIONS.md`.

Spec: `docs/research/03-protocol-terminals-scripts.md`, all of it, especially the binary frame
byte layouts and §13 "Minimal set for a v1 client".

## Exceptions to the conventions (this ticket only)

- **PaseoKit changes are yours.** `DaemonConnection` currently ignores binary frames. Add a
  `DaemonEvent` case carrying binary frames (keep it generic: raw `Data`), decode terminal frames
  in PaseoProtocol (a pure codec with byte-level tests), and route them in the store by slot.
- **Hello capabilities.** Advertise only what this client implements: add the terminal capabilities
  §13 lists. Do not advertise `binary_chunking_v1` sends or `owned_subscriptions` unless you
  implement their behavior fully (if you do implement owned subscriptions, release them with
  `subscription.release.request`).

## What the UI will need (design the API to serve this)

1. Per workspace: a live list of terminals (name, activity bucket, whether it's a script).
2. Create a terminal; kill one.
3. Attach: given the view's grid size, get an `AsyncStream<TerminalOutput>` where output is either
   bytes to feed the emulator or replay begin/end markers (so the view can reset). Detach
   releases the subscription.
4. Send input (text/bytes) and resize (claim vs update, per the spec).
5. Terminal exit and re-attach on reconnect.
6. Scripts: list with lifecycle/health/URLs, start and stop.

## Live fixtures

Create terminals only in the `/tmp/fixture-sandbox` workspace; kill them when done. Capture a
subscribe response, the replay frames, some output (e.g. run `printf 'hello\n'; ls`), an exit,
and a `terminals_changed`. Scripts: add a `paseo.json` with one tiny script to a copy of the
sandbox under `/tmp/fixture-terminals`, register it, start/stop it, then archive it.

## Probe

`paseo-probe terminal <workspaceId>`: creates a terminal, attaches, runs `echo hello`, prints
the received bytes (escaped), detaches, kills it.
