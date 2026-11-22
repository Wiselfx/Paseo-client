# Future work

## Chat transcript smoothness

- **Animate the end-of-turn fold.** When a turn finishes, its work disappears in one step
  (`ClaudeTurnView` folds on `turn.phase`). It could fold with the same disclosure motion as a
  tapped chevron, but only if the cell height animates with it (the engine's `animatesResizes`
  path); otherwise the cell snaps while its contents animate, which looks worse.
- **Display-synced reveal clock.** `ClaudeRevealProse` paces streamed text with `Task.sleep`, so
  reveal steps don't line up with display refreshes on 120 Hz ProMotion. A display-link-driven
  clock would make the reveal cadence steadier.
- **Review the opened tool-call steps.** The folded work lines and live status line were reviewed
  for jumps; the opened `WorkToolSteps` timeline and per-step output (`WorkToolStep`,
  `WorkFileStep`) haven't had the same streaming/jitter pass.
