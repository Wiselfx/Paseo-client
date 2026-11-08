# T6: Agent control

Everything you do to an agent besides chatting: answer its permission requests, create new
agents, pick provider/model/mode/thinking, stop, rename, archive. Read `PHASE2-CONVENTIONS.md`.

Spec: `docs/research/04-protocol-agents-permissions-settings.md`, sections on permissions,
creation, provider snapshots, mode/model/thinking/feature changes, archive, update, attention,
and its "Minimal set for a v1 client" (items 3, 6–10, 11, 13).

## What the UI will need (design the API to serve this)

1. **Permissions.** A conversation shows a pending permission request as an actionable card
   (what the agent wants to do, the options the daemon offers) and the user answers it.
   `ConversationStore` exposes the pending requests for its agent (typed, from the agent
   snapshot's `pendingPermissions` and from live permission events) and a method to answer.
   A request disappears when resolved, from either side.
2. **New agent.** The user picks a workspace (an id is enough for now), a provider and model,
   optionally mode and thinking level, types a first prompt, and starts it. `HostSession` exposes
   a provider catalog (providers, their models, modes, thinking options, availability) and a
   create method that returns the new agent's id or an error.
3. **Switch** mode, model, and thinking level on an existing agent, from the conversation.
4. **Rename** and **archive** an agent.
5. **Attention.** The agent list knows which agents need attention and why (`finished`,
   `error`, `permission`); opening a conversation clears it on the daemon.

## Live fixtures

Create agents only inside `/tmp/fixture-sandbox`'s workspace, and archive them when done. To get
real permission requests, use provider `omp` with model `opencode-go/deepseek-v4.1-flash` in mode
`ask` ("Always Ask"; check the exact mode id with `paseo provider ls`) and prompt it to run a
shell command. Capture the request event, answer it once with allow and once with deny, and
capture the resolution. Capture the provider snapshot, a create, each setting change, and an
archive.

## Probe

`paseo-probe agent-control`: lists providers and models, creates a sandbox agent, switches its
mode, triggers and answers a permission request, renames it, archives it.
