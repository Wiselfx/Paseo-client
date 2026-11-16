# Stores and Core

Rules: PF-20, PF-25, PF-32, PF-33, PF-21. MUST: M04, M05, M26, M30, M40. Checks: H16, H17, H18, H28, F10. Tests: Swift Testing, new files only.
`@Observable` setters notify even for an equal value. Repeated snapshots (pushes, polls, reconnects) are the normal case.

## 1. Write only on change (`W3`, `WorkspaceDirectory`, `CheckoutStore`, `TerminalsStore`, `HostUsageStore`)
Per-step UI flags are the same rule, checked by C49/M42: see [hot-paths-and-indexing.md](hot-paths-and-indexing.md) section 4.
BAD:
```swift
workspaces[index] = workspace                  // a push that repeats what we hold notifies every reader of `workspaces`
status = update.status
```
GOOD:
```swift
if workspaces[index] != workspace { workspaces[index] = workspace }
if status != update.status { status = update.status }
private func setPhase(_ next: Phase) { if phase != next { phase = next } }
private func setTerminals(_ t: [TerminalInfo], in id: String) { if terminalsByWorkspace[id] != t { terminalsByWorkspace[id] = t } }
```
Sort into a copy and assign only if the order changed (`sort()` on the stored array notifies even when nothing moved). `groups` is one pass over `workspaces`, not one filter per project.

## 2. Publish the one value a view draws (`d62664c`, `ConversationWorkspaceIdTests`)
BAD: the shell read `conversation.agent` for the workspace id: every agent update re-ran `ShellView.body`.
GOOD: `didSet { if agent?.workspaceId != workspaceId { workspaceId = agent?.workspaceId } }` and `public private(set) var workspaceId: String?`.

## 3. Lazy derived data (`510c546`)
`mediaIndex` is a computed property over `@ObservationIgnored private var mediaIndexStorage`, updated incrementally when asked (the media sheet), not on every `updateTurns()` on main.

## 4. Off-main persistence and bounded retention
`DraftStore` snapshots on main, encodes and writes on a serial queue (`flush()` waits). `HostSession.retainedConversationLimit = 6`, busy conversations are never closed. See [concurrency](concurrency-and-main-thread.md), [caches](caches-and-memory.md).

## 5. Pin each rule with a test (new file, Swift Testing)
`ConversationWorkspaceIdTests` (value follows agent; unchanged write does not move it), `PaseoDateCacheTests` (cached equals uncached), `ConversationRetentionTests`
(oldest closed past the limit, busy kept), `StreamingIdentityTests` (ids stable while `seqEnd` moves). Templates: [tests](../TEMPLATES/tests.swift.md).

If you remember nothing else:
- Every setter that can receive a repeated value compares first; sorting happens on a copy.
- Publish one narrow value (`workspaceId`, `mascotState`) instead of letting views read a big struct.
- Persistence and retention are bounded, off main, and pinned by a test in a new file.
