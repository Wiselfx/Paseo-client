# Owned subscriptions — what advertising `owned_subscriptions` changes

**What this is.** The wire contract the native client has to satisfy in order to advertise
`owned_subscriptions`, traced to the daemon source that enforces it. Every `file:line` is
relative to the daemon reference checkout (`packages/...`; our own files start with
`Packages/`). Live values come from a sandbox daemon only (0.15.2); nothing captured here
carries a host, token, agent or workspace id.

**Short version.** The capability is a mode switch, not a feature. The moment a socket's
`hello` carries `owned_subscriptions: true` the daemon marks that socket `modern`, stops
broadcasting, and delivers *only* frames that a live subscription it created for that socket
produced. Anything the client used to receive for free (terminal lists, setup progress, session
events, workspaces, labels, agent timelines) must be re-acquired through a request whose
response or first frame hands back a server-assigned subscription id, and every one of those
subscriptions is destroyed with the socket. There is no half-modern state.

## 1. The switch itself

- Capability name: `owned_subscriptions` (`packages/protocol/src/client-capabilities.ts:5-6`,
  added v0.8.0). The `server_info.features` key is **camelCase** `ownedSubscriptions`
  (`packages/server/src/server/websocket-server.ts:2029`). The daemon announces support; the
  client announces use. Both are needed before a setup subscription is accepted.
- The daemon reads the *hello* payload once: `updateClientCapabilities` calls
  `delivery.attach(source, capabilities?.[CLIENT_CAPS.ownedSubscriptions] === true)`
  (`packages/server/src/server/session.ts:1372`). From that point the socket is either modern
  or legacy for its whole life. Sockets that do not advertise are untouched.
- Modern delivery is default-deny: `permits(socket, message)` returns `false` unless the
  message object is in the proof map for a live owner of *this* socket
  (`packages/server/src/server/session/owned-subscriptions/index.ts:422-450`). Broadcasts to
  "all clients" therefore reach a modern socket never, and `sendOwned` is the only path that
  tags a message with its `subscriptionId`
  (`index.ts:452-465`, `withSubscriptionId` at `index.ts:468-475`).

Practical consequence: advertising is **all or nothing**, so the client must advertise only
when it implements *every* subscription family in section 2. That is what the single switch
`OwnedSubscriptions.isEnabled` (`Packages/PaseoCore/Sources/PaseoProtocol/OwnedSubscriptions.swift`)
is for: `false` restores the legacy-capability hello byte for byte.

## 2. Every subscription kind, and how it is acquired

Each family is created by a request. On a modern socket the id comes back either in the
response payload (`payload.subscriptionId`) or, for a request that has no response, in the
tagged frames it emits. Two families are conditional on `workspace_setup_observation`.

| Family | Request | Id arrives in | Notes |
| --- | --- | --- | --- |
| Workspace directory | `fetch_workspaces_request` | `fetch_workspaces_response.payload.subscriptionId` | Replaces the broadcast `workspaces_changed`. |
| Labels | `workspace.label.list.request` | `workspace.label.list.response.payload.subscriptionId` | Per project. |
| Agents | `fetch_agents_request` | `fetch_agents_response.payload.subscriptionId` | Replaces `agents_changed`. |
| Agent timeline | `agent.timeline.set_subscription.request` | `.response.payload.subscriptionId` | Replaces `agent.timeline.updated` broadcasts. |
| Terminal directory | `subscribe_terminals_request` | `terminals_changed.payload.subscriptionId` | **Requires `requestId`** — see below. |
| Terminal stream | `subscribe_terminal_request` | `subscribe_terminal_response.payload.subscriptionId` | Also carries the binary `slot`. |
| Session events | `session.events.set_subscription.request` | `.response.payload.subscriptionId` | Closed enum, section 4. |
| Workspace setup | `workspace.setup.subscribe.request` | `.response.payload.subscriptionId` | Gated, section 3. |
| Browser host | `browser.host.register.request` | `.response.payload.subscriptionId` | Not used by this client. |

Release is uniform: `subscription.release.request { requestId, subscriptionId }` answered by
`subscription.release.response { requestId, subscriptionId }`
(`packages/protocol/src/messages.ts:3402-3411`), handled by
`session.ts:2533-2542` → `delivery.release(id)` (`index.ts:381-389`). The legacy per-family
teardown (`unsubscribe_terminals_request`, `unsubscribe_terminal_request`) **throws** on a
modern socket: *"Release subscriptions using the server-assigned subscription ID"*
(`index.ts:391-400`). So a client that advertises but still sends the old unsubscribe gets an
error and leaks the subscription until the socket dies.

**Directory subscribe needs a `requestId`.** `begin()` rejects a modern request without one
("Owned subscriptions require a requestId", `index.ts:289-291`), and
`subscribe_terminals_request.requestId` is optional in the schema because legacy clients never
sent it. Our first live attempt omitted it and the daemon silently dropped the subscription:
no `terminals_changed`, no id, and `store.directorySubscriptionId` stayed `nil`. Sending a
fresh UUID fixed it. The request id is echoed on the first snapshot only
(`packages/server/src/terminal/terminal-session-controller.ts:402-412`).

## 3. Setup observation

`workspace_setup_observation` is its own capability
(`packages/protocol/src/client-capabilities.ts:48`, added v0.12.0), and the subscribe handler
demands **both** it and a modern socket:

```
if (!this.supports(CLIENT_CAPS.workspaceSetupObservation) ||
    !this.delivery.isModern(this.delivery.currentSource))
  throw new Error("Workspace setup observation requires owned subscriptions");
```
(`packages/server/src/server/session.ts:2481-2490`)

The response payload is `{ requestId, subscriptionId, workspaceId, snapshot }`
(`session.ts:2508-2519`), so the current snapshot arrives *with* the subscription — no separate
status call. After that every change is pushed as `workspace_setup_progress` through the owner
(`session.ts:2503-2506`). The compensation for that is that the daemon stops broadcasting setup
progress to any client that advertises the capability, at all
(`session.ts:8998-9012`): a client that advertises and then fails to subscribe sees no setup
status anywhere. If a socket advertises `owned_subscriptions` but not
`workspace_setup_observation`, setup keeps working over the legacy broadcast and
`workspace.setup.subscribe.request` is rejected — that combination is legal, but our hello sends
them together (the single switch controls both).

## 4. Session events (the explicit-event path)

Unicast pushes — `providers_snapshot_update`, `agent_attention_required`,
`agent_permission_request`/`_resolved`, `script_status_update`, `terminal_attention_required`,
`agent.provider_subagents.update`, `agent.background_work.update`,
`status.daemon_config_changed`, `project.update`, `checkout_status_update` — are routed by
`wantsEvent` (`session.ts:9000-9020`) and only delivered when the socket has a matching event
subscription. `session.events.set_subscription.request { requestId, events[] }` replaces the
whole set (it is not additive) and answers with a `subscriptionId`
(`packages/protocol/src/messages.ts:3380-3389`).

`events` is a **closed enum** (`messages.ts:3359-3378`). One name the daemon does not know
rejects the entire request — and because the request id is not echoed on failure, our client
saw only a 30 s timeout that read as "disconnected". Live on 0.15.2
`agent.background_work.update` is *not* in the enum (that push postdates 0.15.2), so the base
set in `OwnedEventSubscription.baseEvents` only carries names that shipped with the capability;
`agent.background_work.update` is appended only when the daemon advertises
`agentBackgroundWork`. Any future push must follow the same rule: gate on the feature, never
assume the enum is forward compatible.

## 5. Reconnect

Subscription ids are owned by the socket. `delivery.detach(socket)` marks the source inactive,
aborts its cancellation scope and releases every owner it created
(`index.ts:180-194`); a new socket starts with an empty source, so:

- every id held by the client is dead the moment the socket closes, and reusing one in
  `subscription.release.request` resolves to nothing;
- every subscription must be re-created from scratch after `connected` (there is no `resume`);
- ids are not portable between hosts either — they are daemon-assigned per connection.

Our stores therefore clear their recorded ids on `disconnected`
(`TerminalsStore`, `WorkspaceDirectory`, `WorkspaceLabelsStore`, `OwnedEventSubscription`) and
re-subscribe on the next `connected`. Setup is the one that needs a dedicated
`resubscribe()`: unlike the others it is scoped to a workspace the user has open, and the new
subscribe response also re-delivers the snapshot, which is what keeps the status row correct
across a reconnect.

Two ordering rules follow from the above: release *before* replacing a subscription (otherwise
the old owner leaks for the lifetime of the socket), and never release a subscription that
belongs to the previous socket. Both are handled by `releaseOwnedSubscription(_:)` in
`Sources/PaseoStore/OwnedSubscriptionSupport.swift`, which is best-effort (500 ms, never
throws) so a dead socket cannot stall a `disconnect` or a view teardown.

## 6. Live check (sandbox, daemon 0.15.2)

`swift run paseo-probe info` → `ownedSubscriptions: feature=true client=true modern=true`.

- Terminal attach/detach (`paseo-probe terminal wks_…9e3 /tmp/fixture-sandbox`): directory
  subscription id received, stream subscription id received, `stream subscription after
  detach: released`, snapshot replayed and the shell echoed `hello`.
- Setup (`paseo-probe setup /tmp/fixture-sandbox`): `owned=true` and a subscription id — the
  daemon accepts the gated request. The snapshot is `null` because that workspace has no setup
  run, so no progress push could be observed without starting one; the push path itself is
  covered by `OwnedSubscriptionsTests` (a `workspace_setup_progress` frame after subscribe is
  applied to the snapshot).
- Workspace directory: loads over the owned subscription (earlier failure was the missing
  directory `requestId`, section 2).
