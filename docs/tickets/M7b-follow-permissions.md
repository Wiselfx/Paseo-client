# M7b: chat-follow and permission cards

Branch `m7b-follow-perms`. Shared rules: top of `docs/tickets/M3-workspace-panel.md`. Update the
matching rows in `docs/PARITY.md` (Conversation & turns, Composer "fade band", Permissions) in the
same commit. You may edit the **transcript section** of `Chat/ClaudeChatView.swift` (not the
composer section: M8b owns it; not the header), `Chat/ClaudePermissionCard.swift` and new files.

1. **Chat-follow** (`docs/research/06-dsh-ux-spec.md:288-295`, DSH `features/chat-follow/`):
   the transcript follows the tail while the reader is at the bottom; scrolling up more than ~one
   screen-third stops following. While not following, a small round "back to the end" button
   (arrow.down, panel fill, hairline, soft shadow) sits **centred over the composer, 12 pt above
   its top edge** (it must not collide with the crab on the composer's right). Tap = animated
   scroll to the bottom and follow resumes (Reduce Motion: jump), light haptic. Fade in/out 150 ms.
   Plus the **40 pt fade band**: the transcript fades to the canvas color just above the composer
   (a gradient mask, not an overlay that eats taps). Use iOS 18+/26 scroll APIs
   (`onScrollGeometryChange`, `scrollPosition`) rather than GeometryReader hacks. Don't fight M7's
   find bar or its scroll-restore; find mode disables follow.
2. **Permission cards** (`docs/research/01-app-features.md:49-51,331`; protocol
   `docs/research/04-protocol-agents-permissions-settings.md`; upstream app source under
   `/home/paseo/dev/paseo-reference/packages/app/src` for the exact copy):
   - **Question kind**: render the question form ("How would you like to proceed?" or the
     request's own text), one row per option, plus a free-text "Other" field; submit through the
     existing respond path with the answer payload the protocol expects (check the store; if the
     store can't carry an answer payload, say exactly what's missing and render options read-only).
   - **Plan kind**: a "Proposed plan" card: the plan markdown (ClaudeProse), Approve / Reject.
   - **Resolved state**: after a response, the card collapses in place to one quiet line
     ("Approved plan" / "Rejected plan" / "Allowed: <tool>" / "Denied" / "Canceled") instead of
     disappearing, if the store/timeline can tell (else keep a client-side record of what you
     answered this session, and say so).

Commit "M7b: chat-follow and permission cards", don't push. Final message: what changed, store
gaps, unsure-compile spots.
