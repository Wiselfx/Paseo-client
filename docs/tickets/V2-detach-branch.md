# V2: detach subagent + branch switcher

Worker: DeepSeek. Read `AGENTS.md`, `_U-common.md`, `docs/UX-SPEC.md` §0 first. Upstream checkout:
`/home/paseo/dev/paseo-reference/packages`. Sweep: `/tmp/reviews/parity-sweep-2026-11-09.md` B8, B12.
Copy is verbatim from upstream.

## 1. Detach subagent (upstream `app/src/subagents/detach-subagent.ts`, `app/src/subagents/track.tsx`)
- Protocol: `agent.detach.request {agentId, requestId}` → `agent.detach.response {payload: AgentActionResponsePayload}`
  (`protocol/src/messages.ts:2151-2161`). Add the request/response in `PaseoProtocol` the way other agent
  actions are done (look at an existing `AgentActionResponsePayload` user), plus wire tests.
- Check first which subagents upstream lets you detach (managed child agents with a parent, vs provider
  subagents). Cite it. Only offer Detach where upstream does.
- UI: in our subagents sheet (`Conversation/ChatSubagents.swift`) or the managed-agents list, wherever those
  agents appear, add a Detach action (swipe action + context menu). Confirmation dialog exactly per
  `resolveDetachSubagentDialog`: title "Detach subagent?", message "<title or 'This subagent'> will leave this
  track and continue as a standalone agent.", buttons "Detach" / "Cancel", not destructive. On success open
  the detached agent; on failure show the error the usual way.
- Store method + tests with `FakeDaemonClient`.

## 2. Branch switcher (upstream `app/src/components/branch-switcher.tsx`)
- Store already has `GitExtras.swift:338 switchBranch`. Check what lists branches (we have a branch list for
  new workspace; reuse it).
- UI: in the workspace panel's Changes tab header where the branch name is shown (`Workspace/WorkspaceChangesView.swift`),
  tapping the branch opens a searchable sheet (SheetHeader per UX-SPEC) listing branches, current one checked.
  Port upstream's rules: what happens with uncommitted changes, which errors are shown, wording.
- Haptics.selection on pick; spinner while switching; panel refreshes after.

## Done
PaseoCore green (clean build + all tests), touched UI files pass `swiftc -parse`, commit `V2: detach + branch switcher`
on branch `v2-detach-branch`. Final message: upstream citations for every rule and string, anything skipped.
