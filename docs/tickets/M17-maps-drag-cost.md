# M17: map cards, drag a file into the composer, conversation cost

Branch `m17-maps-drag-cost`. Read `AGENTS.md`, `ARCHITECTURE.md` (rich registry ~:73-77),
`docs/research/05-rich-media-spec.md`, `06-dsh-ux-spec.md` (~:190 hover bubble), shared UI rules at
the top of `docs/tickets/M3-workspace-panel.md`. Update PARITY rows and recount.

1. **Map cards** (rich content): a detector entry in T13's rich detection (PaseoStore, pure,
   tested) for coordinates and map links (Apple Maps / Google Maps URLs; plain street addresses
   only if doc 05 specifies a safe rule: no fuzzy guessing that turns prose into cards), rendered
   as a calm MapKit snapshot card (`MKMapSnapshotter`, no live map in the transcript) that opens
   Apple Maps on tap. Follow doc 05's card sizing and the existing rich cards' style.
2. **Drag a file into the composer**: dragging a file row from the workspace panel (Files tree,
   Changes list) onto the composer attaches it as the existing workspace-file attachment (the
   same one `@`-mentions/Add to chat produce). Use SwiftUI `draggable`/`dropDestination` with a
   small Transferable payload; long-press "Add to chat" already exists, so keep both.
3. **Conversation cost in the mascot bubble** (DSH hover bubble → on iOS: tap/long-press the
   crab): show the conversation's cost/tokens from M8e's context-usage data if the agent reports
   it (DSH wording). There is no balance source in Paseo: omit that line, don't fake it.

Done = PaseoCore tests green (new detector tests), `swiftc -parse` every touched UI file,
`Tools/api-audit` no new real findings. No background tasks or subagents; don't end your turn while
waiting. Commit "M17: maps, drag, cost", don't push. Final message: what changed, gaps,
unsure-compile spots.
