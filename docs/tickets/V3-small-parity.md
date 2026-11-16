# V3: small parity items

Worker: Crouton. Read `AGENTS.md`, `_U-common.md`, `docs/UX-SPEC.md` §0 first. Upstream checkout:
`/home/paseo/dev/paseo-reference/packages`. Sweep: `/tmp/reviews/parity-sweep-2026-11-09.md` B13, B14, B21.
Copy verbatim from upstream; cite file:line for each string in your final message. Do not touch
`Conversation/`, `Chat/ChatComposer.swift`, `Chat/DictationController.swift` or `Workspace/WorkspaceChangesView.swift`
(other workers own them).

1. **Test notification** (B21): Settings → Notifications gets the upstream "send test notification" row
   (find it upstream; port its wording). It posts a local notification through our existing notification code
   (`App/Sources/NotificationCoordinator.swift` or whatever posts local notifications today; if that lives in App/,
   expose a small closure through the existing settings plumbing instead of importing App into PaseoUI).
2. **Open service URLs** (B13, upstream `app/src/screens/settings/open-location/open-location-section.tsx:29`):
   a setting with upstream's options and labels; `Workspace/WorkspaceTerminalsView.swift:142` follows it
   (in-app SafariView vs `openURL` external; "ask" shows a confirmation dialog with both). Persist like other
   app settings (look at how existing toggles persist).
3. **PR check rows → Add to chat** (B14): `Workspace/WorkspacePRPane.swift:124` check rows get the same
   "Add to chat" action that reviews/comments already have (`:437`), via context menu. Reuse that code path.

## Done
PaseoCore green if you touched it; every touched UI file passes `swiftc -parse`. Commit `V3: small parity`
on branch `v3-small-parity`.
