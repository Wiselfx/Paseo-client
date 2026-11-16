# Lazy stacks and scrolling

Rules: PF-12, PF-14, PF-15, PF-28, PF-29. MUST: M12, M21, M22. Checks: C44, H27, F14. Rejected here: [DECISIONS.md](../DECISIONS.md) D01, D06, D07.
A `LazyVStack` knows only the rows it has built. Offsets beyond them are estimates, and it builds nothing under an offset it was moved to in one step.

## 1. Mount a window, reveal on demand (`97ccf22`; open 2274 -> 1105 ms Debug, 93 to 115 parses -> 9)
BAD: hand the stack every turn of a 65 000 pt chat: it estimates the content, lands on an estimated bottom, builds ~100 pieces in one pass.
GOOD (ChatTranscript.swift):
```swift
static let windowSize = 16      // do not change without a measurement (8/8 made opens 2.5 to 4 s: D01)
static let windowStep = 12
private var windowedTurns: ArraySlice<Turn> {
    let all = store.turns
    store.turns[windowStartIndex...]   // windowStartIndex: first turn ending at/after windowStartSeq (a timeline position, never a turn id)
}
```
Older turns reveal 12 at a time on scroll with the history anchor; find and jumps grow the window only to the target (8 turns of lead, `mountTurn(at:)`), never to the whole chat. The start is a seq because a turn id (its first row's id) changes when an older page prepends rows to a partial turn. Not while the re-seat settles (PF-28, `dbfda10`: the window had grown to the whole chat, 370 bodies, 2.6 s).

## 2. Re-seat on a real row, not the estimated edge (`c07b6a0`; content 33k to 48k -> 13.5k to 17.8k pt; stalls 1232/1431 -> 513 to 830 ms)
BAD: `scrollPosition.scrollTo(edge: .bottom)`: targets the estimated bottom, each re-seat realises rows around a wrong offset (D06).
GOOD: `scrollPosition.scrollTo(id: "bottom", anchor: .bottom)` on the end marker row; a one-time 2 pt nudge at the end of a converged layout makes the stack build rows under the final offset.

## 3. The re-seat ends on the reader's action (PF-14; `b92e930`, `54d75bc`)
Ends on composer focus, `keyboardWillShow`, a finger, a send, a find/jump, live traffic (`a3c6fab`: a streaming turn fought the re-seat and left the chat blank), or a 16-pass cap.
BAD: end it because "only the insets moved" (a tall saved draft then left the chat blank) or on a timer (it ended at an estimated end).

## 4. Long programmatic jumps (PF-15; D07)

Inside a jump, the window start and the nearest built row are lookups, not scans: `FindNavigation.firstTurnIndex` (binary
search) and `nearestIndex` (outward search), [hot-paths-and-indexing.md](hot-paths-and-indexing.md) sections 1 and 2.
A jump of tens of thousands of points leaves the realised rows at the old offset until a real scroll event: blank. Scroll in bounded hops, or mount a window around the target first.
Find and the outline jump now go through `TranscriptJumpRunner` (W4): scroll to the turn id, hop from the nearest built turn when it will not build, aim the row id once the measured turn is under the viewport and the layout holds, verify with the row's measured frame, correct by that measured offset. See `docs/perf/W1-findings.md` (W4).
Find-in-chat variants tried and reverted before that: turn id first then row then nudge (`64605f6`); outline glide (`ed90b93`). Both landed blank.

If you remember nothing else:
- A lazy stack gets a window of recent turns, never the whole history; do not touch `windowSize`/`windowStep` without a 3-run measurement.
- Scroll to a real row id, never to an estimated edge, and never jump thousands of points in one step.
- The open re-seat ends on what the reader does, not on a layout guess; if it blanks, escalate.
