# R1: reopen the app where you were (drafts and screen)

Read `AGENTS.md`, then `docs/tickets/_P-common.md`, then this file. One worker, one commit per part.

## Behaviour to match (upstream, read in full)
1. **A draft is saved as you type, not on send.** `packages/app/src/stores/draft-store/` (`index.ts`, `state.ts`, `persistence.ts`,
   `migration.ts`), `composer/draft/input-draft.ts`.
   - A draft record holds `{input: {text, attachments}, lifecycle: active | sent | abandoned, updatedAt, version}`.
   - Text saves with a 200 ms debounce (`DRAFT_PERSIST_INTERVAL_MS`, `persistence.ts:3`) and is flushed when the app goes to the
     background or closes, so the last keystrokes survive.
   - An emptied draft (no text, no attachments) becomes `abandoned` (`state.ts:44`); sending marks it `sent`; finished records are
     dropped after 5 minutes (`FINALIZED_DRAFT_TTL_MS`, `state.ts:10`). Active drafts are kept indefinitely.
   - Reading is asynchronous: the composer waits for the draft to hydrate (`isHydrated`) and then shows the saved text once
     (`input-draft.ts` `hydrated` replacement). It never flashes empty then fills while the user types.
   - Attachments on a draft are kept on disk and protected from cleanup while the draft is active (`runAttachmentGc`, `index.ts:~120`).
   - Each draft has its own key: one per draft tab (`draftId`), so two unsent new-session drafts do not overwrite each other.
     Existing conversations also keep their own unsent text by agent id.
2. **The choices made in a draft persist too**: provider, model, mode, thinking level and provider options are remembered per provider
   as "form preferences" (`create-agent-preferences/preferences.ts`: `provider`, `providerPreferences[provider].{model,mode,thinkingByModel,
   options}`, `favoriteModels`, `isolation`). A new draft opens with the last-used values.
3. **The app reopens on the screen you left.** `docs/expo-router.md` ("Startup"), `app/h/[serverId]/index.tsx`,
   `navigation/host-runtime-bootstrap.ts:157-169`, `stores/workspace-layout-store.ts` (persisted layout).
   - The last navigated workspace (host + workspace) is remembered and restored at launch. Restore is based on what you last opened,
     not on connection state: if the host is still connecting or offline, you still land on that workspace and it shows its own
     loading/offline state. Do not jump to another host.
   - If that workspace is proven missing after the host's directory has loaded, fall back to upstream's open-project screen.
   - The workspace's layout is persisted per workspace (open tabs, which tab was focused, including draft tabs and their draft ids);
     temporary tabs (commit diffs) are dropped. So reopening lands on the same tab, with the same unsent prompt.
   - Panels (sidebar / workspace panel) are NOT restored: a cold start begins on the main screen (`docs/mobile-panels.md`: "Compact panel
     selection is not persisted; a cold start begins at agent").

## What we have today (read before changing)
- Per-agent unsent text only: `SavedDraftStore` (UserDefaults `paseo.draft.<agentId>`), used in `ChatController` (~lines 932, 1029-1040).
- The new-session screen (`DraftChatView` / `DraftSession` in `PaseoStore/DraftSession.swift`) keeps its text and choices in memory only.
- Launch selects the first agent (`ShellView.swift` ~line 95); it does not restore the last screen.

## Work
A. **Draft store in Core** (Linux-testable, `PaseoStore`): one persisted draft record type like upstream's (text, attachment references, lifecycle,
   updatedAt, version), debounce 200 ms, flush on background, finalize (sent/abandoned) with the 5-minute prune, hydrate before first use. Move
   `SavedDraftStore`'s job into it (existing conversations keep their unsent text through the same store; migrate existing `paseo.draft.*` keys
   on first read, do not lose them). Use the app's existing persistence style (UserDefaults JSON / Application Support file as
   `WorkspaceReviewDrafts` does); do not add a dependency.
B. **New-session draft persists**: `DraftSession` reads and writes its draft through the store (text, attachments, and provider/model/mode/
   thinking/options as form preferences). Opening a new session shows the last-used choices and any unsent prompt for that draft.
C. **Remember the screen**: persist the last open screen (host, workspace, and either the selected agent or the unsent new-session draft
   with its draft id) and restore it at launch after the directory hydrates, as in point 3. Offline/connecting does not change the target.
   Missing workspace/agent after hydration: fall back to what we do today (first agent), not an error.
D. Attachments: persist and protect them as upstream does, but only for what our composer already stores as attachments; if our
   attachment pipeline cannot keep them across launches without new infrastructure, skip D and say so.

## Owns
`Packages/PaseoCore/Sources/PaseoStore/DraftSession.swift` and a new `DraftStore.swift` beside it, `Packages/PaseoUI/Sources/PaseoUI/Conversation/Composer/SavedDraftStore.swift`
(replace by the new store), `ChatController.swift` only the draft save/load lines, `Draft/DraftChatView.swift`, and the minimal launch-restore
change in `Shell/ShellView.swift` and `App/Sources/RootView.swift`. Another worker (Q2) edits `Sidebar/*`, `Shell/*` and workspace files:
start part C only after `git log` on foundation shows Q2 merged, or keep your ShellView change to a few lines.
Commits: `R1.A draft store`, `R1.B new-session draft`, `R1.C restore screen`, `R1.D attachments`.

Final message: per part done / skipped (why), upstream citations, build and test results, anything unsure.
