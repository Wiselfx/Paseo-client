# M8b: message queue, saved drafts, full-screen composer

Branch `m8b-queue-drafts`. Shared rules: top of `docs/tickets/M3-workspace-panel.md`. Update the
matching Composer rows in `docs/PARITY.md` in the same commit. You may edit the **composer
section** of `Chat/ClaudeChatView.swift`, new PaseoUI files, and a new
`PaseoCore/Sources/PaseoStore/MessageQueue.swift` + its tests (new test file). Do **not** edit the
chat header or transcript (M7 owns them) or the sidebar (M2.7).

1. **Queue** (`docs/research/01-app-features.md:46,75,88-89`). While a turn runs, a plain send
   still steers (unchanged). **Long-press the send button** → queue the draft instead (medium
   haptic). Queued messages show as a quiet stack above the composer card (ink at secondary
   emphasis, one line each, max 3 visible then "+N more"), each with **Edit** (moves it back into
   the draft) and **Send now** (steers it immediately). When the turn ends, the first queued message
   sends automatically, then the next after that turn ends, etc. Queue lives in PaseoStore
   (`MessageQueue`, per agent, pure logic, Linux-tested: enqueue, edit/remove, dequeue-on-idle,
   no double send when `activeTurnId` flickers). Lost on relaunch is fine; say so in PARITY.
2. **Saved drafts**: the unsent draft per agent survives relaunch (UserDefaults keyed by agent id,
   written debounced ~500 ms, cleared on send, restored when the conversation opens if the store's
   draft is empty). Keep it in PaseoUI, small.
3. **Full-screen composer** (`01-app-features.md:77`): when the draft is taller than ~5 lines, a
   small expand control appears in the composer's top-right (left of the crab's spot; don't
   collide with the mascot overlay). It opens a full-height sheet editor (Serif? no: same Sans as
   the composer, 17 pt) with Done/Send; the draft is the same binding. Reduce Motion respected.

Commit "M8b: queue, saved drafts, full-screen composer", don't push. Final message: what changed,
test counts for MessageQueue, unsure-compile spots.
