# M8c: provider features (fast mode etc.) and default send behaviour

Branch `m8c-agent-features`. Store + UI. Store side follows `docs/tickets/PHASE2-CONVENTIONS.md`
(fixtures first, sandbox only, tolerant decoding); M2.8 is in PaseoCore concurrently, so put
protocol/store code in **new files** and keep shared-registry edits minimal. UI: the composer
section of `Chat/ClaudeChatView.swift`, `Chat/ClaudeAgentControlsSheet.swift`,
`Chat/PaseoSettingsView.swift` (one row), new files. Update PARITY rows (provider-feature chips,
Fast mode both rows, Keyboard behavior/Default send) in the same commit.

Spec: `docs/research/04-protocol-agents-permissions-settings.md` §3.4 (`set_agent_feature_request`),
§3.5, §8.1 (`list_provider_features_request`), snapshot `features` (`messages.ts:887`, feature
shapes `:338-362`); app usage `packages/app/src/composer/agent-controls/index.tsx:1726-1760`;
`docs/research/01-app-features.md:84,325`.

1. **Store**: decode `AgentSnapshot.features` (toggle / select, tolerant of unknown types), and
   `AgentControlStore` (or a new helper) `setFeature(agentId:featureId:value:)` optimistic with
   rollback; tests with fixtures captured from the sandbox agent.
2. **Composer**: the agent's features show in the existing controls sheet as a "Features" group
   (toggle rows, select rows as menus), and **Fast mode** (whatever the provider calls its fast
   toggle; match by id from the upstream app, cite it) gets a small quiet chip in the composer's
   bottom toolbar when it's on (bolt glyph, accent ink at low emphasis); tapping it turns it off.
3. **Default send while running** (Settings → Chat, persisted `paseo.defaultSend`):
   Steer (current) / Queue (M8b's queue) / Interrupt (sends with `activeTurnBehavior: interrupt`,
   check `HostSession` supports it; if not, add it minimally). Long-press on send does the
   opposite of the default between steer and queue.

Commit "M8c: provider features and default send", don't push. Final message: what changed, test
counts, fixture source, unsure-compile spots.
