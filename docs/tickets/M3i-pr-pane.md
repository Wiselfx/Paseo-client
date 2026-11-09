# M3i: PR pane and base branch

Branch `m3i-pr-pane`. Shared rules: top of `docs/tickets/M3-workspace-panel.md`; backend parts follow
`docs/tickets/PHASE2-CONVENTIONS.md` (tolerant decoding, errors as observable state, tests).
Update the Git & changes rows in `docs/PARITY.md` in the same commit. You may edit
`Workspace/*.swift`, new UI files, and new PaseoProtocol/PaseoStore files plus minimal one-line
access wideners (like you did for TerminalRename). Do not edit `Chat/*`.
Reference: `docs/research/01-app-features.md:155-178`, `docs/research/02-protocol-workspaces-git-files.md`
§6.1, §6.6, upstream `packages/app/src/git/pull-request-panel/`.

1. **PR section** on the Changes page when the branch has a PR (T11 PR status; `CheckoutPrStatus.checks`
   is already decoded): title, number, state pill, review decision, **checks** as rows (status
   glyph in success/failure/pending ink, name, workflow secondary, duration) with a rollup line
   ("3 checks passed", "1 failing", "2 running"); tap a check with a `url` → in-app Safari
   (reuse M3g's SFSafariViewController helper). "Open on GitHub" row.
2. **Activity timeline** (backend + UI): add `pull_request_timeline_request`/`_response`
   (spec §6.6, upstream `packages/protocol/src/messages.ts:2573-2580,6074-6244`; cite file:line in
   comments) with tolerant decoding (unknown item kinds kept as `.unknown`, error kinds
   `not_found|forbidden|unknown`), and a store call on `GitExtras` (or a new extension file)
   returning items + error as observable state. Fixtures: hand-written from the upstream schema
   (the sandbox has no GitHub PR), clearly marked as such; tests for decode and error mapping.
   UI: reviews (author, verdict, body excerpt, nested inline comments when `reviewId` matches),
   comments, commits; relative times; refresh on appear and pull-to-refresh. **Add to chat** per
   review/comment: inserts a short quoted Markdown excerpt with author and link into the open
   conversation's draft through the existing panel → composer path (M3e mention plumbing).
3. **Base branch**: a "Base: main" row on the Changes page (gate `supportsWorkspaceBaseBranch`)
   opening a searchable branch picker (T11 branches list), `WorkspaceDirectory.setBaseBranch`
   with a full ref, then refresh diff/ahead-behind. Errors inline.

Run `rm -rf .build && swift build --build-tests && swift test` in Packages/PaseoCore; swiftc -parse
every touched UI file. Commit "M3i: PR pane and base branch", don't push. Final message: what
changed, test counts, store gaps, unsure-compile spots.
