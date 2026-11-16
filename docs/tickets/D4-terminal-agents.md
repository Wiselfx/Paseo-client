# D4: buttery terminal, and the full agent list

Branch `d4-terminal`, from `foundation`. Read `_D-common.md` first.

**Owns:**
- `Workspace/PaseoTerminalView.swift`
- `Workspace/WorkspaceTerminalsView.swift`
- `Workspace/PaseoTerminalKeyBar.swift`
- `Workspace/WorkspaceTerminalFileSheet.swift`
- the terminals store in PaseoCore (`PaseoStore` terminal files)
- `PaseoProtocol/Agents.swift`
- `PaseoStore/HostSession.swift` (`refreshAgents` only)
- new test files

## 0. Read upstream's book first

Upstream documents exactly how they keep terminals smooth:
- `/home/paseo/dev/paseo-reference/docs/terminal-performance.md`
- `terminal-rendering.md`
- `terminal-worker.md`
- `terminal-activity.md`

Their client-side invariants are the spec for §1. Where our client breaks one, fix it, and cite
the doc line in your final message.

## 1. The terminal tab is "janky and clanky"; make it buttery

Known problems found by the lead (verify each, and find the rest):

1. **Every tab switch rebuilds the emulator and replays.** `terminalArea` mounts one
   `PaseoTerminalView` with `.id("\(selectedTerminalId)-\(exitGeneration)")`.
   - Upstream: "Retained terminal tabs in the focused workspace keep their streams. Hidden mounted
     terminals continue applying output, so switching tabs does not resubscribe or request a fresh
     snapshot."
   - **Build:** keep up to 4 recently used terminals mounted (an LRU) in a `ZStack`. The selected one
     is visible and hit-testable; the others are `opacity(0)`, `allowsHitTesting(false)` and
     `accessibilityHidden(true)`, and keep their streams and emulators.
   - A switch is a 0.15 s `Motion.fade` crossfade, with no replay and no blank frame.
2. **Output re-renders SwiftUI per chunk.** `onOutput: { markCurrentViewed() }` writes view state
   on every output chunk, so build output re-evaluates the whole terminals page many times a second.
   - **Build:** activity tracking is coalesced: at most one state write per 500 ms, and none when the
     value didn't change. Move it into the coordinator or store as plain bookkeeping.
3. **Feeding.** `streamTask` feeds `view.feed(byteArray:)` once per chunk on the main actor.
   - Upstream: plain writes drain contiguously; xterm batches.
   - **Build:** coalesce the chunks that arrive within one display frame into one `feed` (append to a
     buffer, flush on the next `CADisplayLink` tick or `Task.yield()` boundary). Only replay
     begin/reset are barriers.
   - Keystroke echo must not wait a frame when idle: a leading flush, like their coalescer.
4. **Resize thrash.** Keyboard show and hide, and the key bar, change the terminal's height in
   animated steps, and each `sizeChanged` sends a resize to the host.
   - Upstream: "Replay geometry belongs to the parser queue"; size has one claimant.
   - **Build:** send the resize once, after the keyboard animation settles (debounce 120 ms, or wait
     on `keyboardDidShow` / `DidHide`). Never resize during replay. Only the visible terminal claims
     size.
5. **Keyboard and key bar.**
   - The key bar must ride the keyboard with no lag (it is the `inputAccessoryView`, so check nothing
     re-creates it per update: `makeKeyBar` in `makeUIView` only).
   - Key taps fire on touch-down, with a `Haptics.selection()` only on modifier toggles (Ctrl/Alt
     latches), not on every key.
6. **Scroll.**
   - The emulator's own scroll must not fight an enclosing scroll view or the panel's pan.
   - Check `ShellContainerController`'s pan delegate and the panel's `panelHandlesBack`.
   - If a horizontal edge pan starts on the terminal, it belongs to the panel only from the
     `EdgeDrawer.edgeZone`.
   - Report what you found; you don't own `ShellContainer.swift`.
7. **Exit overlay and empty and loading states:** fade in with `Motion.fade`; no jump.

Measure before and after in reasoning terms: per-chunk main-actor work, and SwiftUI body
evaluations per output burst.

## 2. 65 subagents instead of 72

`HostSession.refreshAgents` sends `FetchAgentsRequest(page: .init(limit: 200), subscribe: true)`,
then filters `archivedAt == nil` client-side, and never pages.
- With many agents, archived ones fill the 200-row page and active ones fall off.
- Upstream (`packages/app/src/runtime/directory-sync/index.ts:701-745`):
  - requests `scope: "active"` (and `includeBackground: true` when the host supports background
    workspaces);
  - uses `sort`;
  - loops on `pageInfo.hasMore` / `nextCursor` (`resolveAgentNextPage`) with `PAGE_LIMIT = 200`.

**Build:**
- Add the request fields that upstream sends (check the server schema in
  `/home/paseo/dev/paseo-reference/packages/server/src/shared/messages.ts` for exact names; old
  hosts must still accept the request: optional fields only, gated on features where upstream gates
  them).
- Decode `pageInfo`.
- Loop pages: subscribe on the first page only, as upstream does.
- Keep the client-side archived filter as a safety net.

**Tests** (new file):
- two pages are merged;
- the subscribe flag is on the first page only;
- a missing `pageInfo` means one page.

## Proof

- PaseoCore: `swift build --build-tests && swift test` green.
- `swiftc -parse` on the UI files.
- Final message: each §1 item, with what you found, what you changed and the upstream doc line.
