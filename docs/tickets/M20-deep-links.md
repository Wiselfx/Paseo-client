# M20: `paseo://` deep links + host chooser

Branch `m20-deep-links`. Read `AGENTS.md`, `ARCHITECTURE.md`, `docs/research/11-relay-pairing.md`
(§3, §8, §9), the shared UI rules at the top of `docs/tickets/M3-workspace-panel.md`, and R18's code
(`App/Sources/AppModel.swift`, `App/Sources/RootView.swift`, `PaseoUI/Chat/PairingFlow.swift`).
iPhone first.

Upstream: scheme `paseo` (`packages/app/app.config.js:107`), routing in `packages/app/src/app/_layout.tsx`,
`hosts/host-chooser.tsx`, `screens/open-project-screen.tsx`, `hooks/use-import-session.tsx`.
Port wording verbatim (cite path:line); never invent copy.

## Hard safety rules

- A pairing/offer link is a credential: never log it, persist it, or put it in errors. Tests use
  generated keys (`RelayResponderFake.swift`), `srv_FIXTURE`-style ids.
- No live relay connection, no relay enable, no daemon config change. Never touch the real saved host;
  never call `daemon.get_pairing_offer` / `set_daemon_config_request` against the real daemon.

## Work

1. Inventory every link form upstream handles (offer links with `#offer=`, open-project, import
   session, agent/workspace routes…). Write it as a short table at the top of your final message.
2. **Parsing** in PaseoStore (or PaseoKit if it needs offer types): a pure `DeepLink` enum + parser for
   the forms we can support on iOS, with tests (valid, malformed, unknown → ignored).
3. **App:** register the `paseo` URL scheme (xcodegen `project.yml` / Info.plist) and `.onOpenURL`.
   Offer links go through R18's existing confirmation path (same sheet, same pins logic, nothing new).
   Links that need a host and more than one saved host exists → the **host chooser** (searchable,
   local-first order, "No matching hosts" empty state, per upstream); one host → use it.
4. Route the supported targets (open project / agent / workspace) using the existing navigation;
   unsupported ones get a plain message, upstream wording if it exists.
5. PARITY: "Host chooser for deep-link flows" and any deep-link rows; recount.

Done = PaseoCore `rm -rf .build && swift build --build-tests && swift test` green with new tests,
`swiftc -parse` every touched UI/App file, `Tools/api-audit` no new real findings (baseline in its
README). No background tasks or subagents; don't end your turn while waiting. Commit "M20: deep links",
don't push. Final message: what changed, link table, wording sources, unsure-compile spots with exact
Apple signatures.
