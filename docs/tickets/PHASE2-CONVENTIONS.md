# Phase 2 ticket conventions

Applies to T6, T7, T8. Read `AGENTS.md` and `ARCHITECTURE.md` first. Phase 1 is done:
`PaseoProtocol` (wire types), `PaseoKit` (`DaemonConnection`), and `PaseoStore`
(`HostSession`, `ConversationStore`, `TimelineState`, `TurnBuilder`). Read them before you start;
copy their patterns.

## Specs

Your spec is the audited research in `docs/research/` (the section your ticket names) plus the
upstream source at `/home/paseo/dev/paseo-reference` (`packages/protocol/src/messages.ts` is the
truth for wire shapes). When the research and the source disagree, the source wins; note it in
your final message.

## You own the contract this time

Unlike phase 1, there is no pre-written API. You design it, within these rules:

- **PaseoProtocol**: one new file per area (e.g. `Permissions.swift`). Requests conform to
  `PaseoRequest`. Every enum decodes unknown values into `.unknown`, every new field is optional
  unless the source marks it required, and nothing throws on fields a newer daemon might add.
  Each type has a `// Source: messages.ts <SchemaName>` comment.
- **PaseoStore**: `@MainActor @Observable` classes, one file per store. Views will read their
  `public private(set)` properties and call their `async` methods. No `throws` in the public store
  API: failures land in an observable error property, as in `ConversationStore`.
- **Events**: new daemon message types arrive in PaseoKit as `DaemonEvent.unhandled(messageType:raw:)`.
  Decode them in your store's code from `raw`. Don't add cases to `DaemonEvent` unless your ticket
  says so.
- **HostSession**: keep your edits to it minimal: a property for your store, and one line in the
  event routing that hands `.unhandled` events to it. Everything else goes in your own files.
  Other tickets edit `HostSession` in parallel; small edits merge cleanly.
- Capability flags (`ServerInfo.features`): check them once, in the store, and expose a plain
  `Bool` such as `isSupported`.

## Fixtures first

1. Extend `Tools/capture-fixtures.mjs` with a new mode, or write `Tools/capture-<area>.mjs`, to
   record real traffic for your area into `Packages/PaseoCore/Tests/PaseoFixtures/Fixtures/<area>/`.
2. **Only operate on sandboxes.** Use `/tmp/fixture-sandbox` (a tiny git repo already registered as
   a Paseo workspace), or create new directories under `/tmp/fixture-<area>`. Never create,
   archive, rename, kill or modify any workspace, agent, terminal or project you didn't create.
   Never touch `/home/paseo/dev`. Clean up what you created when you're done.
3. Scrub fixtures: no real ids except the ones you created, no hostnames, no tokens. Check with
   `grep -rn "srv_\|hostname" <your fixture dir>`; replace with `srv_FIXTURE` / `fixture-host`.
4. Tests decode the fixtures and drive the stores with `FakeDaemonClient`
   (`Tests/PaseoStoreTests/FakeDaemonClient.swift`). Reuse it; extend it in a backward-compatible way if needed.

Credentials for capture scripts: the local credential at `/home/paseo/.paseo/local-credential`
(the existing capture tool shows how). The daemon is at `ws://127.0.0.1:6767/ws`.

## Live check

Add a `paseo-probe` subcommand that exercises your store against the live daemon, on sandboxes
only, and paste its trimmed output in your final message.

## Done when

- `swift build --build-tests` has no warnings in your files; `swift test` passes everything.
- Fixtures committed, probe subcommand works live.
- Commit on your branch with the ticket name. Don't push.
- Final message: the public API you added (signatures only), test summary line, probe output,
  where research and source disagreed, and anything you were unsure about.
