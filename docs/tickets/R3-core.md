# R3: core support for the refactor (PaseoCore)

Branch: `r3-core` (from `foundation`). Read `docs/tickets/_R-common.md` first. PaseoCore only: it
builds and tests on Linux. Runs in parallel with R1 (PaseoUI moves), so **do not touch PaseoUI**.

Owns: `Packages/PaseoCore/Sources/PaseoStore/{TimelineState,HostSession,WorkspaceFiles,ConversationSubagents,BackgroundWorkStore}.swift`,
a new `Sources/PaseoStore/Signposts.swift`, small edits to the store files named in §4, and new
test files.

## Why

The chat view scans the whole timeline four times per streamed token, and the whole agent list three times, to
feed the mascot (audit B N2, `PaseoUI/.../Conversation/ChatMascot.swift:36-108`). It also does an O(rows)
`firstIndex` per visible turn (`ChatTranscript.swift` `boundaryBefore`). R6 will read these as O(1)
values from the store. You build those values here.

## 1. `TimelineState` digest (O(1) reads, maintained incrementally)

Add to `TimelineState` (public, read-only), all kept equal to what a full scan of `rows` would give:

| Property | Meaning (= the full-scan definition) |
|---|---|
| `failedToolCalls: [FailedToolCall]` | `struct FailedToolCall: Sendable, Equatable { callId: String; seq: Int }`, for every row with `.toolCall(call)` where `call.status == .failed && MascotToolError.isFailure(call)`, in row order. `seq` = the row's `seqEnd`. |
| `runningSubAgentCount: Int` | rows with `.toolCall(call)` where `call.status == .running` and `call.detail` is `.subAgent` |
| `lastCompactionStatus: String?` | `status` of the last `.compaction(status, _, _)` row |
| `latestRowKind: RowKind?` | `enum RowKind: Sendable, Equatable { case reasoning, toolCall, other }` of `rows.last`, plus `latestRowId: String?` |
| `rowIndex(forSeqEnd seq: Int) -> Int?` | O(1): index of the row whose `seqEnd == seq` (dictionary maintained alongside `rows`) |

Rules:
- **Incremental paths:** every `rows` mutation updates these. The streaming paths (`merge`,
  `appendRow`, `appendText`) update in O(1) amortized. A tool-call row that changes status in place
  must add or remove its entry, and the running count must go up and down correctly.
- **Full recompute (O(rows)) is allowed only** in `applyPage` (page loads, prepends, epoch resets) and
  `removePendingUserMessage`. Put the recompute in one private `rebuildDigest()` and call it there.
  The incremental paths must give the same result as `rebuildDigest()`.
- **`TimelineState` stays `Equatable`.** If the digest is stored, equality must still mean "same rows" (the digest is
  derived). Either exclude it from `==` with a custom implementation that compares the existing fields,
  or keep it consistent so the synthesized `==` is still correct; say which in your final message.

**Tests** (new file `Tests/PaseoStoreTests/TimelineDigestTests.swift`):
1. **Property test:** a seeded SplitMix64 RNG (copy the one in `IncrementalTurnBuilderTests.swift` into
   your file) generates random stream deltas, status changes, pages, prepends, pending add/remove and
   resets. After **every** step, assert that the digest equals a reference full-scan function written
   in the test. At least 3,000 steps.
2. Targeted cases: a tool call goes running → failed; an AbortError failure doesn't count; a subagent goes
   running → completed; compaction loading → completed; `rowIndex` after a prepend.

## 2. `HostSession` aggregates and a cheap agents signal

- Add public read-only `runningAgentCount`, `pendingPermissionCount` (sum of
  `pendingPermissions.count`) and `attentionCount` (`requiresAttention == true`). Update them where
  `agents` changes. The cost per agent update must not be O(agents) passes **per property**; one pass
  in the setter is fine.
- **`apply(.upsert)`** (`HostSession.swift` ~`:431`):
  - if the incoming snapshot `==` the stored one, return without assigning `agents` (no observer
    notification);
  - otherwise replace it in place and **re-position only that agent**: remove it, then insert at the
    index found by binary search with the existing order (`isNewer`, newest `updatedAt` first, ties
    by id);
  - cache parsed dates in a private `[agentId: Date?]` so the comparator never parses.

  The result must equal `sortedAgents(agents)` exactly; assert that in a test with random upserts.
- `.remove`: the same cache upkeep.

**Tests** in `Tests/PaseoStoreTests/HostSessionAggregatesTests.swift`, using the existing fake
client: counts after upsert, remove and archive; equal upserts don't change `agents` (observe with
`withObservationTracking` and assert no `onChange` fired); order equals the full sort over 500 random
upserts.

## 3. One decode per pushed subagent and background-work update

`HostSession` loops every open conversation with `handleSubagentUpdate` and
`handleBackgroundWorkUpdate`, and each conversation decodes the same payload. Instead:
- decode once in `HostSession`, by `messageType`;
- route to `conversations[parentAgentId]` only;
- keep each store's public behavior and its existing tests green.

If a payload has no parent id, fall back to today's loop for that message only. Replace the per-call
`JSONDecoder()`s in the store handlers you touch with one `private static let decoder` per type
(`JSONDecoder` is safe for repeated sequential use on the main actor).

## 4. A side-effect-free file read for inline images

`WorkspaceFiles.read` writes the shared `file`/`phase` state that the Files page shows. So when the
chat loads several inline images at once, they overwrite each other (audit B N8). Add:

```swift
/// Reads one file without touching this store's visible state. For inline previews.
public func fetch(_ path: String, maxBytes: Int? = nil) async throws -> FileExplorerFile
```

It uses the same request as `read`, and throws `PaseoStoreError` (or the existing error type the file
uses) when `response.file` is nil. Add a test with the fake client: two concurrent `fetch`es return their own
files, and `file`/`phase` are unchanged.

## 5. Signposts

New `Sources/PaseoStore/Signposts.swift`:

```swift
import os
public enum PaseoSignpost {
    public static let log = OSSignposter(subsystem: "dev.paseo.client", category: "perf")
}
```

Wrap these in `log.beginInterval` / `endInterval` (static names):
- "stream commit" (the coalescer's commit);
- "turn rebuild" (`IncrementalTurnBuilder` update);
- "timeline page" (`applyPage`).

`OSSignposter` is in `os`. If `import os` / `OSSignposter` isn't available in the Linux toolchain,
wrap **only** `Signposts.swift`'s body in `#if canImport(os)`, with a no-op shim of the same API in the
`#else`. This is the one allowed platform branch; list it in your final message.

## Done

- `swift build --build-tests` with no warnings in your files.
- `swift test`: all suites green. Report the counts.
- Final message as in `_R-common.md`.
