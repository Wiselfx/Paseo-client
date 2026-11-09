# T16: connection-test flake, context and usage store

Branch `t16-flake-usage`. Backend only (PaseoKit/PaseoProtocol/PaseoStore + tests + probe), per
`docs/tickets/PHASE2-CONVENTIONS.md`. New files where possible (M7d and M8c edit PaseoCore too).

1. **Flake**: `DaemonConnectionTests.connectReturnsServerInfoFromFixture` failed once in a full
   run after T14 (`stateLog.states.contains(.connected(info))` at line 31) and passed 5 isolated
   reruns. Find the race (likely state-log observation vs the new `initiate` waiter path), fix it
   in the code if it's a real ordering bug, or in a **new** test helper if it's test-side; never
   weaken the existing test. Prove it with 30 consecutive full-suite runs of PaseoKitTests.
2. **Context and usage** (`docs/research/01-app-features.md:59,100,391-398`, DSH
   `features/context-stats/`, upstream app `packages/app/src` context meter; find the wire source:
   agent snapshot/timeline usage fields or a usage RPC, cite messages.ts lines): a
   `ConversationStore` (extension) `contextUsage` (used tokens, window size, percent, session cost
   if present) kept live from the stream; and the host usage summary if the protocol has one
   (`usage.enabled` in config). Fixtures from the sandbox agent. If the data isn't on the wire,
   say exactly what is.

Done = `rm -rf .build && swift build --build-tests && swift test` green, no warnings in your files.
Commit "T16: flake fix, context and usage", don't push. Final message: root cause, API, test
counts, probe output.
