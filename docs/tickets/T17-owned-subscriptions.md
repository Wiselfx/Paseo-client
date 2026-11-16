# T17: advertise `owned_subscriptions`

Branch `t17-owned-subscriptions`. Backend only (PaseoCore). Read `AGENTS.md`, `ARCHITECTURE.md`,
`docs/tickets/PHASE3-BACKEND.md`. Reference: upstream server
`/home/paseo/dev/paseo-reference/packages/server/src/server/owned-subscriptions*.ts`,
`wire-compat.test.ts`, and the client side in `packages/client` / `packages/app` (search
`owned_subscriptions`, `ownedSubscription`). Daemon on this host: Paseo 0.15.2.

Today the hello (`PaseoProtocol/Handshake.swift`, `ClientCapabilities.implemented`) does not
advertise `owned_subscriptions`, so terminals detach through the legacy unsubscribe and workspace
setup (`PaseoStore/WorkspaceSetup.swift`) polls instead of receiving pushes.

1. Document the exact wire contract (cite path:line): what advertising the capability changes in
   the daemon's behavior for *every* subscription kind (terminals, setup, anything else), the
   subscribe/unsubscribe message shapes, ownership ids, and what happens on reconnect.
   Put it in `docs/research/09-owned-subscriptions.md`.
2. Implement it end to end so advertising is safe: every subscription path the daemon changes
   must be handled (terminal attach/detach, setup push in `WorkspaceSetup`, others you find).
   Re-subscribe correctly after `DaemonConnection` reconnects. Keep a single switch so it can be
   turned off if the daemon misbehaves.
3. Tests in new files (FakeDaemonClient-driven), plus a live check **only** against the sandbox
   (`/tmp/fixture-sandbox`, agent `1c51ee58-765c-4f8d-bf27-7009338b361e`; never touch other agents,
   workspaces or terminals): setup status arrives by push, a sandbox terminal attaches/detaches.
   Any captured fixture must be scrubbed (no real ids, titles, paths outside /tmp, server ids).

Done = `rm -rf .build && swift build --build-tests && swift test` fully green. No background
tasks or subagents; don't end your turn while waiting. Commit "T17: owned subscriptions", don't
push. Final message: contract summary, what changed, test totals, risks.
