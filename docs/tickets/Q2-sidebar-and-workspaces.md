# Q2: sidebar and workspaces (all hosts, workspace screen, provider background tasks)

Read `AGENTS.md`, then `docs/tickets/_P-common.md` (same rules: upstream and daemon roads first, no extra work, no existing tests edited,
one commit per item, never push), then this file. Do the items in order. For each, first read the PARITY row (`docs/PARITY.md`, search the feature
name) and the upstream code it cites, then decide: build it as upstream does, or skip it and say why.

1. **"All hosts" filter** (PARITY row): upstream `en.ts:1254`. The sidebar can show every saved host's workspaces at once. First check how upstream
   gets other hosts' workspaces and whether our one-host-per-daemon model (L2: `SavedHost`, `HostSwitchContext`) can serve it without keeping several
   live sessions beyond what upstream does. If it needs a second live connection per host, do it the way upstream does or skip and explain.
2. **Workspace screen with tabs** (PARITY row "Workspace screen with tabs…"): upstream's tabs (agents / terminals / files / diffs / PR / setup),
   rename / close / pin / move. Our right-edge workspace panel already has agents, files, changes and terminal pages: reuse it and add only what
   upstream has that we lack (pin, rename, close, move). iPhone first.
3. **Provider background tasks** (PARITY row "Provider subagent list/timeline"): the store exists; add the list/timeline screen where upstream shows it.

Owns: `Packages/PaseoUI/Sources/PaseoUI/Sidebar/*`, `Shell/*`, `Workspace/WorkspacePanel*.swift` and workspace tab files, the subagent/background-task
screen, and Core `WorkspaceDirectory*` only when a wire type is genuinely missing. Do NOT touch `HostSession.swift`, `AgentControlStore.swift`,
`TerminalsStore.swift`, `HostSettingsStore.swift`, `OverviewPage.swift`, `ChatHeader.swift`, `ChatSubagents.swift`, `Workspace/WorkspaceFile*.swift`
(other workers own them). If you need a change there, list it and stop that item.
Commits: `Q2.1 all hosts`, `Q2.2 workspace tabs`, `Q2.3 provider background tasks`.

Final message: per item done / skipped (why), files, upstream citations, build and test results, doubts.
