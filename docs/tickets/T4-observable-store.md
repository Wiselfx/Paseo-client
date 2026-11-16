# T4: Observable store

Implement `HostSession` and `ConversationStore` in PaseoStore: the `@Observable` objects the UI
binds to. They own the event loop that keeps conversations live.

## Files you own

- `Packages/PaseoCore/Sources/PaseoStore/HostSession.swift`: fill in the bodies. You may add
  `internal` initializers, methods and stored properties (for example an internal
  `ConversationStore.init(agentId:client:)` and internal `handleStream`/`applyAgent` methods),
  and split the file in two. Keep every existing `public` declaration and doc comment as is.
- `Packages/PaseoCore/Sources/PaseoStore/TimelineState.swift`: you may add exactly one public method,
  `mutating func removePendingUserMessage(clientMessageId: String)`, with a test.
- New files in `Packages/PaseoCore/Tests/PaseoStoreTests/`.

Read but don't change: `PaseoKit/DaemonClient.swift`, `PaseoProtocol/*`, `TimelineState`
(other than the one method), `Turn.swift`, existing tests.

PaseoKit's `DaemonConnection` is being written in parallel (T1). You don't need it: the store only
talks to the `DaemonClient` protocol. Test with a fake.

## HostSession

- `init(client:)`: keep the client. Do no work.
- `start()`: start two long-lived tasks on the main actor, holding `self` weakly:
  - iterate `client.states`: set `connection`; on `.connected(info)` set `serverInfo`. When
    `.connected` follows a `.reconnecting`, run **resync** (below).
  - iterate `client.events` and route (below).
  Then `await refreshAgents()`.
- `refreshAgents()`: `FetchAgentsRequest(page: .init(limit: 200), subscribe: true)`. `agents` =
  entries without `archivedAt`, sorted by `updatedAt` descending (parse with `PaseoDate`; break
  ties by id). Fill `projects` from entries. On error set `agentsError`, keep the old list.
  On success clear `agentsError`.
- `conversation(for:)`: return the open store for that id, or create one: give it the current
  snapshot from `agents`, add it to the open set, send `SetAgentTimelineSubscriptionRequest` with
  **all** open ids (fire and forget, in a Task), and start `load()` (in a Task). Return it.
- `closeConversation(_:)`: remove it from the open set; send the subscription again with the
  remaining ids.

**Routing events**
- `.agentStream(p)`: if a conversation for `p.agentId` is open, hand it the payload. Else ignore.
- `.agentUpdate(.upsert(agent, project))`: replace or insert in `agents` (drop it if archived),
  re-sort, update `projects`, and give the snapshot to the open conversation, if any.
- `.agentUpdate(.remove(id))`: remove from `agents`.
- `.timelineReplacement(agentId, _)`: if open, that conversation reloads its tail.
- Anything else: ignore.

**Resync** (after a reconnect): resend the subscription for all open ids, `refreshAgents()`, and
have every open conversation catch up (below).

## ConversationStore

- `isRunning`: `activeTurnId != nil || agent?.status == .running`.
- Keep `turns` equal to `TurnBuilder.turns(from: timeline.rows, activeTurnId: activeTurnId)`:
  recompute after every change to `timeline` or `activeTurnId`, nowhere else.
- **Agent snapshot** (from HostSession): `agent = snapshot`, `activeTurnId = snapshot.activeTurn?.turnId`.
- `load()`: `FetchAgentTimelineRequest(agentId:, direction: .tail, limit: 40)`. Apply the page. If
  the page has an `agent`, apply it as a snapshot. `phase = .ready`. On error:
  `phase = .failed(message)` if there are no rows yet, else set `actionError`.
- `loadOlder()`: no-op if `isLoadingOlder` or `!timeline.hasOlder` or no `startCursor`.
  Otherwise fetch `.before` from `timeline.startCursor` with limit 40 and apply.
- **Stream payload** (from HostSession):
  - `.turnStarted(id)`: `activeTurnId = id`. `.turnCompleted`, `.turnFailed`, `.turnCanceled`:
    `activeTurnId = nil`.
  - `.timeline`: `timeline.applyStream(p)`. On `.gap`, catch up. On `.epochChanged`, `load()`.
  - Other events: ignore for now.
- **Catch up**: if a catch-up is already running, do nothing. If `timeline.endCursor` is nil,
  `load()`. Otherwise fetch `.after` from `endCursor` (limit 0) and apply; repeat while
  `hasNewer` is true.
- `send(_:)`: trim; return if empty. `clientId = UUID().uuidString`. Add the pending row with the
  current time as ISO-8601 with fractional seconds. If `text` equals `draft` trimmed, clear
  `draft`. Send `SendAgentMessageRequest(agentId:, text:, messageId: clientId,
  activeTurnBehavior: isRunning ? "steer" : nil)`. If it throws or `accepted == false`: remove
  the pending row, put the text back in `draft` if `draft` is empty, set `actionError`. On success,
  clear `actionError`.
- `cancel()`: `CancelAgentRequest`. Error (thrown or `error` in the response) → `actionError`.

## Tests

Write `FakeDaemonClient: DaemonClient` in the test target. It records every request, answers
from a handler closure per request type (use the fixtures in `PaseoFixtures`, and the `Load`
helpers in `Tests/PaseoStoreTests/Helpers.swift`), and lets the test push events and states.
Tests run on the main actor. Required cases:

1. `start()` loads the agent from `fetch_agents_response` and follows `states` into `connection`.
2. `conversation(for:)` sends a subscription containing that id, loads the tail; after load,
   `phase == .ready` and `turns.count == 2`. Asking again returns the same instance.
3. Load `Load.page(before: 8)`, then push the `Load.stream()` payloads as events: the second
   turn ends up with a prose segment whose text is the full streamed answer, and `activeTurnId`
   is nil after `turn_completed`.
4. A stream gap triggers a `.after` fetch with the store's `endCursor`.
5. `send` shows a pending row before the request resolves, sends `messageId`, clears `draft`.
   With a failing handler: the pending row is gone, `draft` holds the text, `actionError` is set.
6. `closeConversation` sends a subscription without that id.
7. States `.connected` → `.reconnecting` → `.connected` cause a resubscribe and a catch-up fetch.
8. `agentUpdate` upsert of a newer agent moves it to the front; remove deletes it.

Async tests that wait for the store: poll with a short timeout (for example a helper that
awaits `Task.yield()`/`Task.sleep(for: .milliseconds(5))` until a condition holds, failing
after one second). No fixed long sleeps.

## Done when

- `swift test` passes everything except PaseoKit tests (T1 is separate).
- No warnings in your files under Swift 6 strict concurrency.
