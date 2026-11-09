# T15: git actions and file operations (backend)

Branch `t15-git-files-ops`. Backend only: PaseoProtocol + PaseoStore + tests + probe. Follow
`docs/tickets/PHASE2-CONVENTIONS.md` (fixtures first, sandbox only, tolerant decoding, errors as
observable properties, a probe subcommand). No background tasks, no subagents, don't end your turn
while waiting. T14 (file upload) and M2.7 run in parallel: put your work in **new files**
(`PaseoProtocol/GitActions.swift`, `PaseoProtocol/FileEntries.swift`, `PaseoStore/GitActions.swift`,
`PaseoStore/FileEntries.swift` or similar) and keep edits to shared files (message registries,
`HostSession`) to the smallest possible additions.

Spec: `docs/research/02-protocol-workspaces-git-files.md` §5.4, §5.7, §6.2, §6.3, §7.3, §7.4 and
the capability table §8; confirm every field against upstream `/home/paseo/dev/paseo-reference`
(`packages/protocol/src/messages.ts`) and cite file:line in your final message.

1. **Git actions** on the checkout/workspace git store (extension or helper on `CheckoutStore` /
   `WorkspaceGitExtras`, your call, consistent with what's there): `pull()`, `mergeFromBase()`,
   `createPullRequest(title:body:baseRef:) -> (url, number)?`, `mergePullRequest(method:)`,
   `setAutoMerge(enabled:method:)` (respect the "no mergeMethod when disabling" gotcha), each
   with an in-flight flag and a typed error (`MERGE_CONFLICT` distinguishable). Refresh status/PR
   status after success the way the existing `commit`/`push` do.
2. **Commits ahead of base** (gate `features.commitsList`): `loadCommits()` → observable list
   (sha, subject, author, date, files if present) and `loadCommitFileDiff(sha:path:)`.
3. **File entries** on `WorkspaceFiles` (gate `features.fsEntryOps`, duplicate on
   `features.fsEntryDuplicate`): `createEntry(parentPath:name:kind:)`, `rename(path:to:)`,
   `duplicate(path:)`, `delete(path:)`, each returning the new path or success, re-listing the
   affected directory afterwards, collisions surfaced as the daemon's error text.
4. **Text write** (gate `features.workspaceFileEditing`): `write(path:content:expectedModifiedAt:)`
   returning written / conflict(current modifiedAt) / error.
5. Feature flags readable from the session (e.g. `session.serverFeatures.commitsList`) if not
   already exposed; reuse what exists.
6. Probe: `paseo-probe git-ops` and `paseo-probe fs-ops` against `/tmp/fixture-sandbox` only:
   create a file, rename, duplicate, write, delete; list commits. Do not push or open PRs for real
   (fixture-test PR create/merge/auto-merge only).

Done means `rm -rf Packages/PaseoCore/.build && swift build --build-tests && swift test` green, no
warnings in your files. Commit "T15: git actions and file operations", don't push. Final message:
API summary, upstream citations, test counts, probe output, anything unsure.
