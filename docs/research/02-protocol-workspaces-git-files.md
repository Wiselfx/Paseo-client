# Protocol map — projects, workspaces, worktrees, git/diffs, forge and files

**Audit:** re-checked every wire fact in §§1–8 against `packages/protocol/src/messages.ts`, the binary codecs, `packages/client/src` and the app call sites: message type strings, field names/optionality, enum values, response shapes, feature-flag keys, release semantics, plus the §9 v1 minimally-sufficient list. 158 facts checked, 21 corrected (chief fixes: `sort` is an array of `{key, direction}` objects, modern directory subscriptions *are* released over the wire, `authState` is `unknown` on the wire, the app drives `DaemonClient` not the `PaseoClient` facade, wrong client method names, and `project.add.request` was missing from the v1 set).

Read-only research for a native iOS client that speaks the Paseo daemon WebSocket protocol directly. Source of truth: `/home/paseo/dev/paseo-reference` (referenced below as `<ref>`). All `path:line` citations are relative to `<ref>` unless they start with `docs/` (i.e. `docs/…` means `<ref>/docs/…`) or note otherwise. `<ref>` HEAD was read on 2026-11-08.

Scope: project.list/create/add/remove, fetch_workspaces + workspace create/archive/rename, worktree creation, checkout diff subscribe/unsubscribe + diff payloads, git status/branches/commit/push/merge, forge (GitHub) features and the clone flow, fs listing/reading/watching/subscribing. Agent, terminal, voice and plugin RPCs are out of scope except where they share the subscription machinery.

Background that applies everywhere:

- Wire schemas live in `packages/protocol/src/messages.ts`. New RPCs use dotted names; flat names remain valid protocol (`docs/rpc-namespacing.md:1-17`, migration rule `:78-88`).
- Requests keep parameters at the top level; responses put correlated data under `payload` with `requestId` in both (`docs/rpc-namespacing.md:19-66`).
- The protocol contract is append-only; features are gated once on `server_info.features.*` (`docs/protocol-compatibility.md:19-55`). The `features` key sits at `packages/protocol/src/messages.ts:3811`, on the `server_info` schema at `:3796`; server advertises it from `packages/server/src/server/websocket-server.ts:2025-2180`.
- Modern (owned) subscriptions are released with `subscription.release.request` (`packages/protocol/src/messages.ts:3402`), handled at `packages/server/src/server/session.ts:2533` via `SessionDelivery.release` (`packages/server/src/server/session/owned-subscriptions/index.ts:381`). Legacy (broadcast-era) subscriptions have per-family release RPCs instead — noted per operation below. A directory subscription on a modern socket (`fetch_workspaces_request` with `subscribe`) **is** an owned subscription: the server registers it via `delivery.begin("workspaces", …)` (`packages/server/src/server/session.ts:6698-6705`) and `subscription.release.request` tears it down server-side. Only *legacy* directory slots have no release RPC — the client detaches the local listener and stops routing (`packages/client/src/connection/legacy.ts:163-196`, `default: return null`).
- Modern clients negotiate `owned_subscriptions` against `features.ownedSubscriptions` (`packages/protocol/src/messages.ts:4000`, `docs/protocol-compatibility.md:96-104`). `hello` carries `capabilities`; the daemon gates new wire values on `session.supports(CLIENT_CAPS.*)` (`docs/architecture.md` §WebSocket protocol, compatibility rules; rules at `docs/protocol-compatibility.md:9-30`).
- Hub/principal permission gating is a separate, coarse axis for daemon-mediated calls: the map at `packages/server/src/server/authorization/operation-permissions.ts:6-502` assigns each RPC a semantic permission (`workspace.read` / `workspace.write` / `workspace.manage` / …). A local client connected directly is not affected; Hub-routed connections are.
- App paths cite `packages/app/src/…`. Every `client.*` call below is the **low-level `DaemonClient`** (`packages/client/src/daemon-client.ts`), which the app imports as `@getpaseo/client/internal/daemon-client` — not the `PaseoClient` facade (`packages/client/src/index.ts`). The facade only wraps `hosts`/`projects`/`workspaces`/`agents`/`providers`/`terminals`/`config` and exposes **no** git, diff or filesystem surface; its method names differ (`workspaces.list({ subscribe: {} })`, `projects.list()`, `workspaces.create()`), so do not translate `observeWorkspaces`/`getCheckoutStatus`/`readFile` into facade calls.

## 1. Projects

### 1.1 `project.list.request` — list registered projects

- **Name/purpose:** list the daemon-global project registry (survives workspace archival). One line.
- **Request:** type `project.list.request` — `projectId` none, `requestId: string`, optional `sync: DirectorySyncRequestSchema` (replica cursor) (`packages/protocol/src/messages.ts:1404-1410`).
- **Response:** type `project.list.response` — `payload: { requestId: string, projects: WorkspaceProjectDescriptorPayload[], sync?: DirectorySyncMetadata }` (`packages/protocol/src/messages.ts:4659-4665`). `WorkspaceProjectDescriptorPayload` = `{ projectId, projectKey?, projectDisplayName, projectCustomName?, projectCustomIconRevision?, projectIconRevision?, projectRootPath, projectKind: "git"|"non_git"|"directory", syncSeq? }` (`packages/protocol/src/messages.ts:4506-4522`).
- **Live updates:** `project.update` — discriminated union `upsert`/`remove`, `{ subscriptionId?, kind, project|projectId, generation?, seq? }` (`packages/protocol/src/messages.ts:4639-4657`). Projects flow through the same directory-sync machinery as workspaces; on modern hosts the subscription comes from `fetch_workspaces_request`/`project.list.request` with `subscribe`/`sync`. Release: modern → `subscription.release.request` (`packages/protocol/src/messages.ts:3402`); legacy directory slots → local detach, no RPC (`packages/client/src/connection/legacy.ts:186-188`).
- **Capability gate:** client-side `server_info.features.projectList` (`packages/protocol/src/messages.ts:3977`); app gates the project snapshot on it at `packages/app/src/runtime/directory-sync/index.ts:569` (plus `directorySync` at `:570`). Server advertises it at `packages/server/src/server/websocket-server.ts:2124-2125`.
- **How the app uses it:** `client.listProjects(...)` from the directory-sync owner, `packages/app/src/runtime/directory-sync/index.ts:819`; surfaced via `useProjects` (`packages/app/src/hooks/use-projects.ts:163`).
- **Gotchas:** pre-`projectList` daemons return workspace rows only and the app synthesizes project descriptors from workspaces (`packages/app/src/runtime/directory-sync/index.ts:651-659`, legacy path `:578-584`). `sync` is COMPAT-tagged: `directorySync` gate, remove after 2027-02-12 (`packages/protocol/src/messages.ts:1407-1409`).

### 1.2 `project.suggestions.request` — recent-project suggestions

- **Name/purpose:** rank past provider sessions into "recent projects to open" for the add-project flow.
- **Request:** type `project.suggestions.request` — `requestId: string`, optional `providers: string[]`, optional `since: string` (ISO; defaults to 30 days ago), optional `limit: int ≤ 100` (`packages/protocol/src/messages.ts:1411-1419`).
- **Response:** type `project.suggestions.response` — `payload: { requestId, suggestions: ProjectSuggestion[], providerErrors: { provider, message }[] }`; suggestion = `{ rootPath, displayName, sessionCount, providerIds, lastActivityAt }` (`packages/protocol/src/messages.ts:4668-4685`).
- **Live updates:** none.
- **Capability gate:** `server_info.features.projectSuggestions` (`packages/protocol/src/messages.ts:3979`). No server-side CLIENT_CAPS check seen.
- **How the app uses it:** `packages/app/src/components/add-project-flow.tsx` (recommended-path list); RPC not used elsewhere.
- **Gotchas:** `rootPath` is "the main repository root for git checkouts and their worktrees; the session cwd otherwise" (`packages/protocol/src/messages.ts:4669-4671`). Provider errors are non-fatal and reported in-band (`:4680`).

### 1.3 `project.add.request` — register an existing directory as a project (+ workspace)

- **Name/purpose:** add an on-disk directory to the registry; unlike `open_project_request` it is the modern, gated path and returns a project descriptor.
- **Request:** type `project.add.request` — `cwd: string`, `requestId: string` (`packages/protocol/src/messages.ts:2797-2802`).
- **Response:** type `project.add.response` — `payload: { requestId, project: WorkspaceProjectDescriptorPayload | null, error: string | null, errorCode: "directory_not_found" | nullish }` (`packages/protocol/src/messages.ts:4768-4776`).
- **Live updates:** `project.update` upsert (§1.1) and possibly `workspace_update` (§2.1). Release per §1.1.
- **Capability gate:** `server_info.features.projectAdd` (`packages/protocol/src/messages.ts:3923`); app additionally requires `stableProjectIdentity` before offering Add (`packages/app/src/hooks/use-open-project.ts:13-18`, usage `:39-46`).
- **How the app uses it:** `openProjectDirectly` in `packages/app/src/hooks/open-project.ts` (via `useOpenProject`, `packages/app/src/hooks/use-open-project.ts:17-40`); also the desktop deep-link path (`packages/app/src/app/_layout.tsx:780`).
- **Gotchas:** daemon-side handler `handleProjectAddRequest` (`packages/server/src/server/session.ts:7359`). Semantic permission `workspace.manage` for Hub-routed calls (`packages/server/src/server/authorization/operation-permissions.ts:154`).

### 1.4 `project.create_directory.request` — create a new directory and register it

- **Name/purpose:** mkdir under `parentPath` and register it as a project in one step (add-project flow "new folder").
- **Request:** type `project.create_directory.request` — `parentPath: string`, `name: string`, `requestId: string` (`packages/protocol/src/messages.ts:2803-2808`).
- **Response:** type `project.create_directory.response` — `payload: { requestId, directoryPath: string | null, project: WorkspaceProjectDescriptorPayload | null, error: string | null, errorCode: string | null }` — codes open on the wire for forward-compat (`packages/protocol/src/messages.ts:4787-4799`).
- **Live updates:** `project.update` upsert (§1.1).
- **Capability gate:** `server_info.features.projectCreateDirectory` (`packages/protocol/src/messages.ts:3975`).
- **How the app uses it:** add-project flow (`packages/app/src/components/add-project-flow.tsx`).
- **Gotchas:** error codes are deliberately open-ended, not an enum — an older client must keep parsing after a newer daemon learns a new failure reason (`packages/protocol/src/messages.ts:4793-4795`). Semantic permission `workspace.manage` (`packages/server/src/server/authorization/operation-permissions.ts:155`).

### 1.5 `project.rename.request` / `workspace.title.set.request` — rename project and workspace

- **Name/purpose:** set or clear a custom name. (Workspace rename is listed here because the app's rename UI hits both.)
- **Request (project):** type `project.rename.request` — `projectId: string`, `customName: string | null` (null/empty clears the override), `requestId: string` (`packages/protocol/src/messages.ts:1027-1034`).
- **Request (workspace):** type `workspace.title.set.request` — `workspaceId: string`, `title: string | null` (null/empty clears), `requestId: string` (`packages/protocol/src/messages.ts:1048-1054`).
- **Response (project):** type `project.rename.response` — `payload: { requestId, projectId, accepted: boolean, customName: string | null, error: string | null }` (`packages/protocol/src/messages.ts:2195-2203`).
- **Response (workspace):** type `workspace.title.set.response` — `payload: { requestId, workspaceId, accepted: boolean, title: string | null, error: string | null }` (`packages/protocol/src/messages.ts:2231-2243`).
- **Live updates:** `project.update` upsert (`packages/protocol/src/messages.ts:4639`) and/or `workspace_update` upsert (`:4543`) — name is carried inside the descriptor (`projectCustomName` `:4313`, `title` `:4333`).
- **Capability gate:** none for either — established RPCs, ungated.
- **How the app uses it:** project rename: project settings screen (`packages/app/src/screens/project-settings-screen.tsx`); workspace rename: `workspace.title.set.request` from the workspace menu (`packages/app/src/components/sidebar/sidebar-workspace-menu.tsx`).
- **Gotchas:** the descriptor keeps the raw override (`title`/`projectCustomName`) separate from the resolved `name`/`projectDisplayName`; the rename UI prefills from the raw field and offers "reset" (`packages/protocol/src/messages.ts:4309-4313`, `4327-4333`).

### 1.6 `project.remove.request` — remove a project (and its workspaces)

- **Name/purpose:** unregister a project; removes the backing workspace records too.
- **Request:** type `project.remove.request` — `projectId: string`, `requestId: string` (`packages/protocol/src/messages.ts:1042-1047`).
- **Response:** type `project.remove.response` — `payload: { requestId, projectId, accepted: boolean, removedWorkspaceIds: string[], error: string | null }` (`packages/protocol/src/messages.ts:2218-2226`).
- **Live updates:** `workspace_update` remove (one per removed workspace) and `project.update` remove (`packages/protocol/src/messages.ts:4543`, `4639`).
- **Capability gate:** `server_info.features.projectRemove` (`packages/protocol/src/messages.ts:3921`).
- **How the app uses it:** `removeProjectFromHosts` (`packages/app/src/projects/project-remove.ts:1-40`), surfaced in the sidebar (`packages/app/src/components/sidebar-workspace-list.tsx:143-144`).
- **Gotchas:** workspace rows can disappear for reasons other than archive — handle the `workspace_update` `remove` kind generally. Semantic permission `workspace.manage` (`packages/server/src/server/authorization/operation-permissions.ts:161`).

### 1.7 `project.icon.get.request` / `project.icon.set.request` — project icons

- **Name/purpose:** read or set a custom project icon (automatic discovery otherwise).
- **Request (get):** type `project.icon.get.request` — `projectId: string`, `requestId: string` (`packages/protocol/src/messages.ts:3060-3064`). **Request (set):** type `project.icon.set.request` — `projectId: string`, `source: ProjectIconSourceSchema` (`automatic` or `upload` with base64 `data`), `requestId: string` (`packages/protocol/src/messages.ts:1035-1041`, source schema `:1019-1025`).
- **Response (get):** type `project.icon.get.response` — `payload: { projectId, icon: { data, mimeType } | null, error, requestId }` (`packages/protocol/src/messages.ts:6484-6494`). **Response (set):** type `project.icon.set.response` — `payload: { requestId, projectId, accepted, error }` (`packages/protocol/src/messages.ts:2200-2208`).
- **Live updates:** `project.update` upsert with a new `projectIconRevision`/`projectCustomIconRevision` (`packages/protocol/src/messages.ts:4314-4316`, `4506-4522`).
- **Capability gate:** `project.icon.set.request` → `server_info.features.projectCustomIcon` (`packages/protocol/src/messages.ts:4016`); app checks `projectCustomIcon` before offering upload (same area of `messages.ts`; gate key confirmed at `packages/protocol/src/messages.ts:4016`). `project.icon.get` ungated (read).
- **How the app uses it:** project settings screen (`packages/app/src/screens/project-settings-screen.tsx`).
- **Gotchas:** the daemon never fetches an icon URL on the host's network; upload sources are client-supplied bytes only (`packages/protocol/src/messages.ts:1019-1022`).

### 1.8 `workspace.github.search_repositories.request` — search GitHub repos to clone

- **Name/purpose:** search (via the host's `gh` CLI) for repositories to clone into a new project.
- **Request:** type `workspace.github.search_repositories.request` — `query: string`, optional `limit: int ≤ 50`, `requestId: string` (`packages/protocol/src/messages.ts:2820-2826`).
- **Response:** type `workspace.github.search_repositories.response` — discriminated union on `status`: `success` (`repositories: GithubRepository[]`, `available: true`, `error: null`), `unavailable` (`reason: "gh_missing"`, `available: false`), `unauthenticated` (`available: false`), `error` (`available: true`, `error: string`) — all with `requestId` (`packages/protocol/src/messages.ts:4800-4834`). Every branch carries `repositories` (**required**; empty array on failure), `available` and `error` (`requestId` in each) — decode them unconditionally, then branch on `status`. `GithubRepository = { id, name, nameWithOwner (min 3: "a/b"), description: string | null, visibility, updatedAt, cloneUrl }` (`packages/protocol/src/messages.ts:2810-2818`).
- **Live updates:** none.
- **Capability gate:** `server_info.features.workspaceGithubRepositorySearch` (`packages/protocol/src/messages.ts:3973`); app gates the clone UI on it at `packages/app/src/components/add-project-flow.tsx:335-336`.
- **How the app uses it:** add-project → GitHub clone page (`packages/app/src/components/add-project-flow.tsx:334-364`).
- **Gotchas:** shells out to `gh` on the host with `cwd: homedir()` (`packages/server/src/server/session.ts:7482-7489`); failure modes are in-band `status`, not `rpc_error` — check `status` before `repositories` (`packages/server/src/server/session.ts:7535-7546`).

### 1.9 `project.github.clone.request` — clone a GitHub repo into a new project

- **Name/purpose:** clone `repo` into `targetDirectory/<name>` on the host, register it as a project, and return the descriptor.
- **Request:** type `project.github.clone.request` — `repo: string` (min 3; `owner/repo` shorthand accepted), optional `cloneProtocol: "https" | "ssh"`, `targetDirectory: string`, `requestId: string` (`packages/protocol/src/messages.ts:2827-2836`).
- **Response:** type `project.github.clone.response` — `payload: { requestId, repo, checkoutPath: string | null, project: WorkspaceProjectDescriptorPayload | null, error: string | null }` (`packages/protocol/src/messages.ts:4835-4845`).
- **Live updates:** `project.update` upsert after registration (§1.1).
- **Capability gate:** `server_info.features.projectGithubClone` (`packages/protocol/src/messages.ts:3971`); app gates at `packages/app/src/components/add-project-flow.tsx:333-334` and in `useCloneGithubProject` (`packages/app/src/hooks/use-open-project.ts:48-82`).
- **How the app uses it:** `cloneGithubProjectDirectly` → `client.cloneGithubProject({ repo, targetDirectory, cloneProtocol })`, `packages/app/src/hooks/open-project.ts:117-151`.
- **Gotchas:** clones to a staging dir then `rename(2)` into place; on failure the staging dir is removed and the error is returned in-band (`packages/server/src/server/session.ts:7558-7610`). The clone URL is built from `repo`, not fetched — the daemon never receives an arbitrary URL from the client. `gh` is used for search (§1.8) but plain `git clone` for the clone itself (`packages/server/src/server/session.ts:7573-7577`). 5-minute clone timeout, 1 MiB output cap (`:7575-7577`). Semantic permission `workspace.manage` (`packages/server/src/server/authorization/operation-permissions.ts:156`).

## 2. Workspaces

### 2.1 `fetch_workspaces_request` — page/subscribe the workspace directory

- **Name/purpose:** list visible workspaces (paged) and optionally subscribe that socket to live `workspace_update`s.
- **Request:** type `fetch_workspaces_request` — optional `includeBackground: boolean`, `requestId: string`, optional `filter { query?, projectId?, idPrefix? (accepted, ignored), includeInternal?, includeBackground? }`, optional **`sort` = an array of `{ key: "status_priority"|"activity_at"|"name"|"project_id", direction: "asc"|"desc" }`** (`direction` is required per entry; this is not a bare enum), optional `page { limit ≤ 200, cursor? }`, optional `subscribe: { subscriptionId? }`, optional `sync: DirectorySyncRequestSchema` (`packages/protocol/src/messages.ts:1366-1403`, sort at `:1381-1389`).
- **Response:** type `fetch_workspaces_response` — `payload: { requestId, subscriptionId?: string | null, entries: WorkspaceDescriptorPayload[], emptyProjects?: WorkspaceProjectDescriptorPayload[] (first page only, default []), pageInfo: { nextCursor, prevCursor, hasMore }, sync?: DirectorySyncMetadata }` (`packages/protocol/src/messages.ts:4524-4541`). `WorkspaceDescriptorPayload` = `{ id, projectId, projectDisplayName, projectCustomName?, projectRootPath, workspaceDirectory?, setupStatus?, worktreeSlug?, projectKind, workspaceKind: "directory"|"local_checkout"|"checkout"|"worktree", name, title?, pinnedAt?, labels?, background?, archivingAt?, status: "needs_input"|"failed"|"running"|"attention"|"done", activityAt, diffStat?, scripts[], gitRuntime?, githubRuntime?, forge?, ... }` (`packages/protocol/src/messages.ts:4302-4404`).
- **Live updates:** `workspace_update` — discriminated union `upsert` (workspace descriptor) / `remove` (`id`, optional `emptyProject`, optional `removedProjectId`), plus `generation`/`seq` (`packages/protocol/src/messages.ts:4543-4583`). Release: `subscription.release.request` on a modern socket (the server-side directory registration is owned — `packages/server/src/server/session.ts:6698-6705`); on a legacy socket there is no release RPC, the client just drops the local slot (`packages/client/src/connection/legacy.ts:163-196`).
- **Capability gate:** `subscribe` needs a modern socket (owned subscriptions) — nothing else; `sync` is gated by `server_info.features.directorySync` (`packages/protocol/src/messages.ts:3836`); `includeBackground` needs `features.backgroundWorkspaces` (`packages/protocol/src/messages.ts:3824`) and is enforced client-side in `requireBackgroundWorkspaces` (`packages/client/src/daemon-client.ts:2878-2880`).
- **How the app uses it:** directory-sync owner — `client.observeWorkspaces(...)` when subscribing, else `client.fetchWorkspaces(...)` (`packages/app/src/runtime/directory-sync/index.ts:609-633`); `workspace_update` messages applied via `client.observeWorkspaces` subscription (`:622-629`). SDK: `packages/client/src/daemon-client.ts:2984-3025`.
- **Gotchas:** the workspace directory is daemon-global and sequenced; a missing/expired cursor returns a full snapshot (`docs/architecture.md`, "The three directory entity types have independent monotonic sequences"). `emptyProjects` exists so a project whose last workspace was archived keeps rendering in the sidebar (`packages/protocol/src/messages.ts:4529-4533`, comment `:4502-4505`). Entries carry both `syncSeq` and per-row `generation`; clients advance per-entity cursors, not a global one (`docs/architecture.md`, same section). Semantic permission `workspace.read` + `hub.execute` (`packages/server/src/server/authorization/operation-permissions.ts:97`).

### 2.2 `workspace.create.request` — create a workspace (directory or worktree)

- **Name/purpose:** create a fresh workspace record; optionally one initial agent + prompt. Never deduplicates by directory (unlike `open_project_request`).
- **Request:** type `workspace.create.request` — optional `workspaceId: string` (must match `^wks_[a-f0-9]{16}$`, supplied IDs keep identity on replay), optional `agent: WorkspaceInitialAgentSchema` (same shape as `agent.create.request` minus type/requestId/idempotencyKey/subscribe/workspaceId/worktree/**worktreeName**/git — the omit list at `packages/protocol/src/messages.ts:1858-1866` includes `worktreeName`), optional `subscribe: boolean`, `requestId: string`, optional `idempotencyKey: string (≤512)`, optional `title: string`, optional `firstAgentContext { prompt?, attachments? }`, optional `background: boolean`, optional `callerAgentId: string`, and **`source`**: discriminated union (`packages/protocol/src/messages.ts:2846-2891`):
  - `{ kind: "directory", path: string, projectId?: string }` — open existing directory (`:2866-2871`)
  - `{ kind: "worktree", cwd?: string, projectId?: string, action?: "branch-off"|"checkout", refName?: string, baseBranch?: string, branchName?: string, checkoutSource?: ChangeRequestCheckoutSourceSchema, githubPrNumber?: number (COMPAT), worktreeSlug?: string }` — cut a worktree (`:2872-2891`). `checkoutSource` = `{ kind: "change_request", forge?: string, number: int>0, projectPath?: string }` (`packages/protocol/src/messages.ts:1280-1286`).
- **Response:** type `workspace.create.response` — `payload: { agent?: AgentSnapshotPayload, creation?: CreationSnapshot, workspace: WorkspaceDescriptorPayload | null, setupTerminalId: string | null, setupSkippedReason?: string, error: string | null, errorCode?: string, requestId: string }` (`packages/protocol/src/messages.ts:5279-5293`).
- **Live updates:** `workspace_update` upsert before provider startup (negotiated creation; "Workspace readiness is published before provider startup" — `docs/architecture.md` §Creation ownership). Also `workspace_setup_progress` / `script_status_update` if a setup script runs (§2.7), and `agent_update` for the initial agent.
- **Capability gate:** `subscribe`/receipts → `server_info.features.workspaceRequestReceipts` / `creationLifecycle` (`packages/protocol/src/messages.ts:3816`, `3817`); worktree source for a PR checkout needs forge support host-side (no client gate — `checkoutSource` rides the request); `background` needs `features.backgroundWorkspaces` (`:3824`). The app gates the whole create surface on `workspaceMultiplicity` (`packages/protocol/src/messages.ts:3919`; app: `packages/app/src/screens/new-workspace-screen.tsx:884-885`).
- **How the app uses it:** `createMultiplicityWorkspace` → `client.createWorkspace({ idempotencyKey, agent, source: { kind: "worktree"|"directory", ... }, firstAgentContext })`, `packages/app/src/screens/new-workspace-screen.tsx:309-336`. SDK entry: `packages/client/src/daemon-client.ts:5299-5347`.
- **Gotchas:** `internal` is retained for parse only — public internal creation was removed (`packages/protocol/src/messages.ts:2860-2861`, enforced server-side `packages/server/src/server/session.ts:7149-7155`). `agent.background` must not be set per-agent; background is a workspace-level flag (`packages/server/src/server/session.ts:7151-7154`). Retries must reuse the same `idempotencyKey`; the creation journal owns identity — reconnect subscribes to the creation key (`docs/architecture.md` §Creation ownership). `source.kind: "worktree"` requires `cwd` or `projectId` (`packages/server/src/server/session.ts:7235-7244`). `workspaceId` on the response, not the request, is the handle for all later RPCs (`packages/protocol/src/messages.ts:2787-2789` is the analogous comment for `open_project_request`).

### 2.3 `open_project_request` — legacy open-or-create-by-directory

- **Name/purpose:** "open this folder": deduplicates by directory into an existing workspace when possible. Predates `project.add`/`workspace.create`.
- **Request:** type `open_project_request` — `cwd: string` (path used only for lookup/creation; use the returned `workspace.id` afterwards), `requestId: string` (`packages/protocol/src/messages.ts:2787-2792`).
- **Response:** type `open_project_response` — `payload: { requestId, workspace: WorkspaceDescriptorPayload | null, error: string | null, errorCode: "directory_not_found" | nullish }` (`packages/protocol/src/messages.ts:4757-4766`). `errorCode` degrades unknown codes from newer daemons to null (`:4763-4764`).
- **Live updates:** `workspace_update` upsert if a workspace was created (§2.1); none if it matched an existing one.
- **Capability gate:** none.
- **How the app uses it:** superseded in the app by `project.add.request` for the Add-project CTA (`packages/app/src/hooks/open-project.ts:77-116`, gate in `packages/app/src/hooks/use-open-project.ts:13-46`); `open_project_request` remains for compatibility (e.g. CLI `paseo <path>`).
- **Gotchas:** unlike `workspace.create.request` it deduplicates by directory — two opens of the same folder return the same workspace (`packages/protocol/src/messages.ts:2843-2845`, contrast comment). Semantic permission `workspace.manage` (`packages/server/src/server/authorization/operation-permissions.ts:134`).

### 2.4 `archive_workspace_request` (+ undo/recovery) — archive a workspace

- **Name/purpose:** archive (soft-delete) a workspace: stops its agents/terminals, removes it from the directory, keeps records for undo/restore.
- **Request:** type `archive_workspace_request` — `workspaceId: string`, `requestId: string` (`packages/protocol/src/messages.ts:2837-2841`).
- **Response:** type `archive_workspace_response` — `payload: { requestId, workspaceId, archivedAt: string | null, error: string | null, canceled?: boolean }` — `canceled` set when an undo stopped the archive mid-flight; `error` carries the reason (`packages/protocol/src/messages.ts:4904-4914`).
- **Live updates:** `workspace_update` `remove` (§2.1) — with `emptyProject` when the project lost its last workspace. Agents receive `agent_archived`.
- **Capability gate:** none for archive itself. Undo → `server_info.features.workspaceArchiveUndo` (`packages/protocol/src/messages.ts:3929`); app gate at `packages/app/src/workspace/archive-undo/internal/capability.ts` (via `supportsWorkspaceArchiveUndo`, used at `packages/app/src/workspace/use-workspace-archive.ts:66-75`, COMPAT tag `:71`). Recovery → `features.workspaceRecovery` (`packages/protocol/src/messages.ts:3927-3928`).
- **How the app uses it:** `archiveWorkspaceWithUndo` when supported, else optimistic archive with fallback (`packages/app/src/workspace/use-workspace-archive.ts:56-95`); confirm-dirty-worktree warning for `worktree`-kind workspaces (`:84-98`). SDK: `packages/client/src/daemon-client.ts:3287-3300`.
- **Gotchas:** archiving a worktree-kind workspace removes the on-disk worktree only when it is Paseo-owned and unreferenced — drive disk deletion off `scope` on the archive path (§3.3), not here. `workspace.recovery.inspect`/`workspace.recovery.restore` peek at / re-materialize archived worktrees (`packages/protocol/src/messages.ts:1116-1119`, `1122-1126`, responses `:2277-2303`). Semantic permission `workspace.manage` (`packages/server/src/server/authorization/operation-permissions.ts:41`).

### 2.5 `workspace.pin.set.request` / `workspace.base_branch.set.request` — pin and base branch

- **Name/purpose:** pin a workspace to the sidebar; set the base ref used for diff/merge comparison.
- **Request (pin):** type `workspace.pin.set.request` — `workspaceId: string`, `pinned: boolean`, `requestId: string` (`packages/protocol/src/messages.ts:1056-1062`).
- **Request (base branch):** type `workspace.base_branch.set.request` — `workspaceId: string`, `baseRef: string`, `requestId: string` (`packages/protocol/src/messages.ts:1063-1069`).
- **Response (pin):** type `workspace.pin.set.response` — `payload: { requestId, workspaceId, accepted: boolean, pinnedAt: string | null, error: string | null }` (`packages/protocol/src/messages.ts:2244-2255`).
- **Response (base branch):** type `workspace.base_branch.set.response` — `payload: { requestId, workspaceId, accepted: boolean, baseRef: string | null, error: string | null }` (`packages/protocol/src/messages.ts:2249-2258`).
- **Live updates:** `workspace_update` upsert; descriptor gains `pinnedAt` (`packages/protocol/src/messages.ts:4334-4335`). Base branch feeds `comparisonBaseRef`/`baseRefExact` in checkout status (§5.1).
- **Capability gate:** pin → `server_info.features.workspacePinning` (`packages/protocol/src/messages.ts:3962`); base branch → `server_info.features.workspaceBaseBranch` (`packages/protocol/src/messages.ts:3841`).
- **How the app uses it:** pin: sidebar pin actions (`packages/app/src/hooks/use-global-workspace-pin-action.ts`, `use-sidebar-workspace-pin.ts`); base branch: `packages/app/src/git/workspace-base-branch-picker.tsx`.
- **Gotchas:** base branch is per-workspace, not per-directory — two workspaces on one checkout may compare against different refs (directory-backed vs workspace-owned rule, `docs/architecture.md` §Right-sidebar boundary).

### 2.6 `workspace_setup_status_request` / `workspace.setup.subscribe.request` — setup script observation

- **Name/purpose:** read or subscribe to the per-workspace setup/hook script snapshot.
- **Request (status):** type `workspace_setup_status_request` — `workspaceId: string`, `requestId: string` (`packages/protocol/src/messages.ts:2754-2759`).
- **Request (subscribe):** type `workspace.setup.subscribe.request` — `workspaceId: string`, `requestId: string` (`packages/protocol/src/messages.ts:2760-2765`).
- **Response (status):** type `workspace_setup_status_response` — `payload: { requestId, workspaceId, snapshot: WorkspaceSetupSnapshot | null }` (status `running|completed|failed|blocked`) (`packages/protocol/src/messages.ts:4748-4756`; the status emit callback lives at `packages/server/src/server/session.ts:2490-2499`).
- **Response (subscribe):** type `workspace.setup.subscribe.response` — `payload: { requestId, subscriptionId?, workspaceId, snapshot: WorkspaceSetupSnapshot | null }` — `subscriptionId` is optional and `snapshot` is **nullable** (`packages/protocol/src/messages.ts:4728-4736`; emitted at `packages/server/src/server/session.ts:2505-2512`).
- **Live updates:** `workspace_setup_progress` (`{ status: "running"|"completed"|"failed"|"blocked", workspaceId, subscriptionId?, ... }`, `packages/protocol/src/messages.ts:4695-4707`). Release: modern only — `subscription.release.request` (§0); requires owned subscriptions (`packages/server/src/server/session.ts:2483-2487`).
- **Capability gate:** `server_info.features.workspaceSetupObservation` (`packages/protocol/src/messages.ts:4003`); the subscribe path additionally requires a modern socket (`packages/server/src/server/session.ts:2483-2487`). `workspace.setup.run.request` (rerun) is gated on `features.workspaceSetupRun` (`:3843`).
- **How the app uses it:** setup UI lives in `packages/app/src/components/workspace-setup-dialog.tsx` (subscribe + run); unrelated to the file explorer hook.
- **Gotchas:** capable clients cannot observe setup via the legacy session-event category — older hosts need an update to emit nothing at all (`docs/protocol-compatibility.md:118-124`).

### 2.7 `workspace.label.list.request` etc. — labels (skip unless needed)

Out of the requested scope; note only that workspace labels are a separate subscribed sequence with their own `workspace.label.update` events (`packages/protocol/src/messages.ts:1080-1130`, updates `:4588-4627`), gated on `features.workspaceLabels` (`:3838`). Fetched alongside workspaces in the directory-sync owner.

## 3. Worktrees

Worktree creation is the same RPC as workspace creation (§2.2, `source.kind: "worktree"`) plus two legacy-ish RPCs below. The app's New-workspace screen branches off a base ref or checks out a branch/PR into a new worktree (`packages/app/src/screens/new-workspace-screen.tsx:1237-1262`, picker → `pickerItemToCheckoutRequest` at `packages/app/src/screens/new-workspace-picker-item.ts:183-235`).

Creation modes (all expresses through `source: { kind: "worktree", ... }` or `checkoutSource`):

- **branch-off:** `action: "branch-off"`, `refName` = base ref to branch from (e.g. `refs/remotes/origin/main` or a local ref), `branchName` = new branch, optional `worktreeSlug` for the directory basename. The app sends the upstream ref when known, not `origin/<branch>`, because forks may track `upstream/main` (`packages/app/src/screens/new-workspace-picker-item.ts:163-181`).
- **checkout existing branch:** `action: "checkout"`, `refName` = the branch/ref to check out (`refs/heads/x` or `refs/remotes/origin/x`).
- **checkout a change request (PR/MR):** `action: "checkout"`, `checkoutSource: { kind: "change_request", forge, number, projectPath? }`, plus `githubPrNumber` for pre-`checkoutSource` daemons (COMPAT, `packages/protocol/src/messages.ts:2883-2887`, `1792-1797`). Forge-neutral; `forge` defaults to `github` on the wire (`checkoutSource.forge?` at `packages/protocol/src/messages.ts:1282`).
- **agent-scoped worktree (internal):** `git: GitSetupOptionsSchema` and `worktree: CreateAgentWorktreeTargetSchema` on `create_agent_request`/`agent.create.request` (`packages/protocol/src/messages.ts:1784-1797`, `1801-1814`) — relevant only if a future client creates worktrees from the agent screen; not the workspace path.

### 3.1 `create_paseo_worktree_request` — legacy worktree-create RPC

- **Name/purpose:** create a Paseo worktree (and its workspace record) without creating an initial agent. Superseded by `workspace.create.request` with `source.kind = "worktree"`; still served.
- **Request:** type `create_paseo_worktree_request` — `cwd: string` (repo root/checkout), optional `projectId`, optional `worktreeSlug`, `nameContext?`, optional `attachments`, optional `firstAgentContext`, optional `refName`, optional `action: "branch-off"|"checkout"`, optional `checkoutSource: ChangeRequestCheckoutSourceSchema`, optional `githubPrNumber` (COMPAT), `requestId: string` (`packages/protocol/src/messages.ts:2736-2752`).
- **Response:** type `create_paseo_worktree_response` — `payload: { workspace: WorkspaceDescriptorPayload | null, error: string | null, errorCode?: string, setupTerminalId: string | null, setupSkippedReason?: string, requestId: string }` (`packages/protocol/src/messages.ts:6352-6362`).
- **Live updates:** `workspace_update` upsert (§2.1); `workspace_setup_progress` if a setup script runs.
- **Capability gate:** none client-side; semantic permission `workspace.manage` (`packages/server/src/server/authorization/operation-permissions.ts:79`).
- **How the app uses it:** not used by the current app — the New workspace flow uses `workspace.create.request`. The CLI/tests still call it.
- **Gotchas:** handler is `handleCreatePaseoWorktreeRequest` → shared `createPaseoWorktreeWorkflow` (`packages/server/src/server/session.ts:7750-7790`). Worktree directory naming: `worktreeSlug` is the basename of the Paseo worktree root (`worktreeSlug` in the descriptor, `packages/protocol/src/messages.ts:4321-4323`).

### 3.2 `paseo_worktree_list_request` — list Paseo-owned worktrees

- **Name/purpose:** enumerate Paseo-created worktrees for a repo (used by archive warnings and tests).
- **Request:** type `paseo_worktree_list_request` — optional `cwd: string`, optional `repoRoot: string`, `requestId: string` (`packages/protocol/src/messages.ts:2700-2705`).
- **Response:** type `paseo_worktree_list_response` — `payload: { worktrees: PaseoWorktree[], error: CheckoutError | null, requestId: string }`; `PaseoWorktree = { worktreePath, createdAt, branchName?: string | null, head?: string | null }` (`packages/protocol/src/messages.ts:6326-6339`). `CheckoutError = { code: "NOT_GIT_REPO"|"NOT_ALLOWED"|"MERGE_CONFLICT"|"UNKNOWN", message: string }` (`packages/protocol/src/messages.ts:2325-2334`).
- **Live updates:** none.
- **Capability gate:** none; semantic permission `workspace.read` (`packages/server/src/server/authorization/operation-permissions.ts:136`).
- **How the app uses it:** not used by the app UI; surfaced by the CLI (`paseo worktree ls` compat alias, `docs/architecture.md` §`packages/cli`).
- **Gotchas:** lists all Paseo-owned worktrees, not just ones backed by workspaces — an orphaned worktree appears here but has no workspace row.

### 3.3 `paseo_worktree_archive_request` — archive/remove a worktree

- **Name/purpose:** archive the workspace(s) backed by a worktree, optionally deleting the directory when Paseo-owned and unreferenced.
- **Request:** type `paseo_worktree_archive_request` — optional `worktreePath`, optional `repoRoot`, optional `branchName`, optional `workspaceId` (archive this exact record — a directory can back multiple workspaces, Model B), optional `scope: "workspace"|"worktree"` (default `"workspace"`; `"worktree"` archives every active workspace on the directory), optional `deleteWorktreeFromDisk: boolean` (COMPAT, ignored — disk deletion derives from scope + last-reference + ownership), `requestId: string` (`packages/protocol/src/messages.ts:2707-2734`).
- **Response:** type `paseo_worktree_archive_response` — `payload: { success: boolean, removedAgents?: string[], error: CheckoutError | null, requestId: string }` (`packages/protocol/src/messages.ts:6342-6359`).
- **Live updates:** `workspace_update` remove (§2.1), `agent_archived` for removed agents.
- **Capability gate:** `scope: "worktree"` rides on `features.workspaceMultiplicity` (`packages/protocol/src/messages.ts:3919`); the app's worktree-archive confirmation path uses it. Semantic permission `workspace.manage` (`packages/server/src/server/authorization/operation-permissions.ts:135`).
- **How the app uses it:** worktree-kind archive flow with dirty/ahead warnings (`packages/app/src/workspace/use-workspace-archive.ts:84-111`); underlying call **`client.archivePaseoWorktree`** (compat path; called `paseoWorktreeArchive` nowhere — `packages/client/src/daemon-client.ts:5252`; the list counterpart is `client.getPaseoWorktreeList` at `:5237`).
- **Gotchas:** three COMPAT tags (`worktreeArchiveWorkspaceId`, `worktreeArchiveScope`, `worktreeDiskDeletion`) — all added in v0.1.97, drop when floor ≥ v0.1.97 (`packages/protocol/src/messages.ts:2712-2730`). `deleteWorktreeFromDisk` is ignored as of v0.1.97 — do not send it expecting effect. Model B: two workspaces may share a `cwd`; resolve by `workspaceId` when set, else prefer the `worktree`-kind record on a cwd tie (`:2711-2719`).

## 4. Checkout (git) — diffs

Two diff pipelines coexist. The app's working/base/all diff view uses the modern one when `features.diffSubscription` is set, else the legacy subscribe RPC (`packages/app/src/git/use-working-diff.ts:50-54`, wiring `git/use-diff-query.ts:75-118`, `data/push-router.ts:342-372`).

### 4.1 `diff.subscribe.request` / `diff.unsubscribe.request` — modern binary diff stream

- **Name/purpose:** subscribe to a live diff between two endpoints; updates stream as binary frames (syntax-highlighted hunks), not JSON.
- **Request:** type `diff.subscribe.request` — `requestId: string`, `cwd: string`, `base: DiffEndpoint`, `head: DiffEndpoint`, optional `mergeBase: boolean`, optional `ignoreWhitespace: boolean`, optional `highlight: boolean` (`packages/protocol/src/messages.ts:2359-2368`). `DiffEndpoint` = `{ kind: "rev", rev: string } | { kind: "index" } | { kind: "worktree" } | { kind: "empty" }` (`packages/protocol/src/messages.ts:2343-2348`).
- **Response:** type `diff.subscribe.response` — `payload: { requestId, subscriptionId: string, slot: int 0..255, error: DiffError | null }` (`packages/protocol/src/messages.ts:2374-2383`). `DiffError = { code: "NOT_GIT_REPO"|"REF_NOT_FOUND"|"INVALID_COMPARE"|"TOO_MANY_SUBSCRIPTIONS"|"UNKNOWN", message }` (`packages/protocol/src/messages.ts:2349-2358`). Slot is a binary-frame channel, 256 max.
- **Live updates:** **binary frames**, opcodes `0x40 Begin` (resolved shas, entries), `0x41 Bodies` (files, hunks, tokens), `0x42 End` (`packages/protocol/src/binary-frames/diff.ts:3-4`); decode with `decodeDiffFrame` (`packages/protocol/src/binary-frames/diff.ts:252`), which routes by `bytes[0]` in `decodeBinaryFrame` (`packages/protocol/src/binary-frames/demux.ts:22`). Frame layout: `opcode | slot | version=1 | revision:varint` then opcode-specific fields; slot is `bytes[1]`. Legacy fallback is the §4.2 JSON stream, not a `checkout_diff_update` rewrite. Release: `diff.unsubscribe.request { subscriptionId }` — fire-and-forget, no response (`packages/protocol/src/messages.ts:2370-2373`, comment at `:2369`: "Unsubscribe is fire-and-forget; release has no correlated response."). Modern path: the client-side `OwnedSubscription.release()` sends `subscription.release.request` instead (`packages/client/src/connection/index.ts:20-33`, `packages/protocol/src/messages.ts:3402-3410`). In the SDK, `client.observeDiff(compare)` picks modern (binary) vs legacy (JSON) itself inside `DiffStreamRouter` (`packages/client/src/diff/index.ts:59-120`); the mode comes from `features.diffSubscription` (`packages/client/src/daemon-client.ts:7732`).
- **Capability gate:** `server_info.features.diffSubscription` (`packages/protocol/src/messages.ts:4001`); app gates at `packages/app/src/git/use-working-diff.ts:50-54` and compares `comparisonBaseRef` vs `baseRef` on it (`:53-54`). Server advertises it at `packages/server/src/server/websocket-server.ts:2030`.
- **How the app uses it:** `client.observeDiff({ cwd, base: { kind: "rev", rev }, head: { kind: "worktree"|"rev", ... }, mergeBase, ignoreWhitespace })` from the push router (`packages/app/src/data/push-router.ts:342-354`); route registered via `checkoutDiffPushRoute` (`packages/app/src/git/use-diff-query.ts:99-118`); consumed through `useReplicaQuery` with `pushEvent: "checkout_diff_update"` (`:92-100`).
- **Gotchas:** slots are per-socket; 256 concurrent diff subscriptions max, excess → `TOO_MANY_SUBSCRIPTIONS` (`packages/server/src/server/diff/session.ts:22-33`, code at `packages/protocol/src/messages.ts:2354`). Frame routing by slot byte (`packages/server/src/server/diff/session.ts:36-46`). The response carries the slot assignment — needed to decode frames. Failure tears the subscription down and releases the owner (`:48-58`). Unsubscribe releases slot + subscription (`packages/server/src/server/diff/index.ts` — `DiffSubscriptions`).

### 4.2 `subscribe_checkout_diff_request` / `unsubscribe_checkout_diff_request` — legacy JSON diff stream

- **Name/purpose:** same as §4.1 but JSON snapshots; retained for older daemons and as the wire shape behind `useReplicaQuery` push events.
- **Request:** type `subscribe_checkout_diff_request` — optional `subscriptionId: string` (host assigns when omitted), `cwd: string`, `compare: { mode: "uncommitted"|"base"|"all", baseRef?, ignoreWhitespace?: boolean }`, `requestId: string` (`packages/protocol/src/messages.ts:2394-2400`, compare at `:2337-2341`).
- **Response:** type `subscribe_checkout_diff_response` — `payload: { subscriptionId, cwd, files: ParsedDiffFile[], error: CheckoutError | null, diffTooLarge?: boolean, requestId: string }` (`packages/protocol/src/messages.ts:5797-5812`). `ParsedDiffFile = { path, oldPath? (COMPAT v0.3.0), isNew, isDeleted, additions, deletions, hunks: [{ oldStart, oldCount, newStart, newCount, lines: [{ type: "add"|"remove"|"context"|"header", content, tokens?: [{ text, style|null }] }] }], status?: "ok"|"too_large"|"binary" }` (`:2925-2935`, hunks `:2917-2923`, lines `:2911-2915`, tokens `:2906-2910`).
- **Live updates:** `checkout_diff_update` — `payload: { subscriptionId, cwd, files, error, diffTooLarge? }` (`packages/protocol/src/messages.ts:5820-5823`). Release: `unsubscribe_checkout_diff_request { subscriptionId }` (`packages/protocol/src/messages.ts:2409-2413`) — fire-and-forget, no correlated response; or modern `subscription.release.request`.
- **Capability gate:** none — it is the baseline path. `mode: "all"` (uncommitted ∪ merge-base) is gated on `server_info.features.checkoutDiffAll` (`packages/protocol/src/messages.ts:4023`; app gate `packages/app/src/git/use-diff-query.ts:59-62`). `diffTooLarge` COMPAT added v0.2.4 (`:5803-5804`).
- **How the app uses it:** `client.observeCheckoutDiff(cwd, compare)` (`packages/client/src/daemon-client.ts:4872-4885`); `getCheckoutDiff` for one-shot reads (`:4838-4852`); diff snapshot decoding in `packages/app/src/git/diff-snapshot.ts`.
- **Gotchas:** server-side the subscription is owned per-socket (`SessionDelivery.begin("diffs", ..., "diff:<id>")`, `packages/server/src/server/session/checkout/checkout-session.ts:431-466`); updated snapshots are emitted as `checkout_diff_update` with the *server-assigned* subscription id (`:445-450`). Two same-`cwd` workspaces intentionally share one diff view (directory-backed; `docs/architecture.md` §Right-sidebar boundary, `checkoutDiffQueryKey` at `packages/app/src/git/query-keys.ts:24`). Legacy `checkout_status_request`-adjacent: diff subscriptions also get refreshed by `checkout.refresh.request` (`checkout-session.ts:503-520`).

### 4.3 `checkout.diff.get.request` — one-shot diff read

- **Name/purpose:** same payload as §4.2 without a subscription — a single snapshot for a comparison.
- **Request:** type `checkout.diff.get.request` — `cwd: string`, `compare` as in §4.2, `requestId: string` (`packages/protocol/src/messages.ts:2402-2407`).
- **Response:** type `checkout.diff.get.response` — `payload: { cwd, files, error, diffTooLarge?, requestId }` (subscriptionId omitted) (`packages/protocol/src/messages.ts:5813-5819`).
- **Live updates:** none.
- **Capability gate:** none. (On legacy hosts the client transparently maps it to `subscribe_checkout_diff_request` + immediate release, `packages/client/src/connection/legacy.ts:88-101`.)
- **How the app uses it:** `client.getCheckoutDiff(...)` — used by tooling/tests; the app prefers the subscription.
- **Gotchas:** legacy hosts see a subscribe+unsubscribe pair on the wire, not a clean one-shot (`packages/client/src/connection/legacy.ts:88-101`). Modern hosts serve it as an inline read (`checkout-session.ts:418-429` → `handleReadDiffRequest`).

### 4.4 `subscription.release.request` — modern subscription teardown

- **Name/purpose:** release any owned subscription on this socket (diff, file, workspace/labels/events when supported).
- **Request:** type `subscription.release.request` — `requestId: string`, `subscriptionId: string` (`packages/protocol/src/messages.ts:3402-3406`).
- **Response:** type `subscription.release.response` — `payload: { requestId, subscriptionId }` (`packages/protocol/src/messages.ts:3407-3411`).
- **Live updates:** none; triggers teardown of the owning producer (diff slot, file watcher, directory observation).
- **Capability gate:** requires `features.ownedSubscriptions` (`packages/protocol/src/messages.ts:4000`) — sent only on modern sockets (`packages/client/src/connection/index.ts:18-33`).
- **How the app uses it:** implicitly via `OwnedSubscription.release()` in `data/push-router.ts` (`:310-318`, `:335`, `:385`), file sessions (`packages/app/src/file-panels/file/daemon-session.ts:66-71`), and directory-sync (`packages/app/src/runtime/directory-sync/index.ts:620-622` releases the previous workspace subscription before re-creating).
- **Gotchas:** release failure disposes the transport and reconnects (`packages/client/src/daemon-client.ts:1398-1410`). On release the server runs the owner's teardown callback — e.g. file observer `unsubscribe()` is an awaited barrier after which no callback may fire (`docs/file-observation.md:9`).

## 5. Checkout (git) — status and mutations

### 5.1 `checkout_status_request` — read git status snapshot

- **Name/purpose:** one-shot git status for a cwd (branch, dirty, ahead/behind vs upstream, PR/forge summary attached at push time).
- **Request:** type `checkout_status_request` — `cwd: string`, `requestId: string` (`packages/protocol/src/messages.ts:2388-2392`).
- **Response:** type `checkout_status_response` — `payload` is a union of three shapes sharing `CheckoutStatusCommonSchema` (`cwd, error: CheckoutError|null, requestId, baseRefExact?, comparisonBaseRef?, upstreamRef?`) (`packages/protocol/src/messages.ts:5587-5600`):
  - `{ isGit: false, isPaseoOwnedWorktree: false, repoRoot: null, currentBranch: null, isDirty: null, baseRef: null, aheadBehind: null, aheadOfOrigin: null, behindOfOrigin: null, hasRemote: boolean, remoteUrl: null }` (`:5602-5615`)
  - `{ isGit: true, isPaseoOwnedWorktree: false, repoRoot: string, mainRepoRoot?: string|null, currentBranch: string|null, isDirty: boolean, baseRef: string|null, aheadBehind: {ahead,behind}|null, aheadOfOrigin: number|null, behindOfOrigin: number|null, hasRemote: boolean, remoteUrl: string|null }` (`:5617-5630`)
  - same with `isPaseoOwnedWorktree: true` and `mainRepoRoot: string`, `baseRef: string` (`:5631-5644`)
  Response type string: `checkout_status_response` (`:5646-5651`).
- **Live updates:** `checkout_status_update` (§5.1a) — the push half.
- **Capability gate:** none; semantic permission `workspace.read` (`packages/server/src/server/authorization/operation-permissions.ts:71`).
- **How the app uses it:** `fetchCheckoutStatus` → **`client.getCheckoutStatus(cwd)`** (there is no `checkoutStatus` method — `packages/client/src/daemon-client.ts:4768`) with `checkoutStatusQueryKey(serverId, cwd)`, `packages/app/src/git/use-status-query.ts:16-44`, cache at `packages/app/src/git/checkout-status-cache.ts`.
- **Gotchas:** `upstreamRef` is the full ref `<branch>@{upstream}` resolved by git — never compose `origin/<branch>` yourself; forks may track `upstream/main` (`packages/protocol/src/messages.ts:5592-5598`). `comparisonBaseRef` vs `baseRef`: the app uses `comparisonBaseRef` only when `features.diffSubscription` is set (`packages/app/src/git/use-working-diff.ts:50-54`). Freshness is push-driven; `staleTime: Infinity` + `refetchOnMount` only after invalidation (reconnect) (`packages/app/src/git/use-status-query.ts:30-35`).

#### 5.1a `checkout_status_update` — pushed git status

- Same payload union as §5.1, intersected with `{ subscriptionId?, prStatus?: CheckoutPrStatusPayload }` (`packages/protocol/src/messages.ts:5781-5794`). Emitted by the daemon-level project Git observer (root `.git` entry only, non-recursive, plus slow rescan fallback — `docs/architecture.md` §`packages/server`, "Project identity is daemon-global…") and the per-session workspace git observer.
- The app subscribes via `client.observeEvents(["checkout_status_update", ...])` in `packages/app/src/contexts/session-context.tsx:469-475` and applies it with `applyCheckoutStatusUpdateFromEvent` (`:509-513`; implementation `packages/app/src/git/checkout-status-cache.ts:50`). Gate for receiving it as an explicit event: `features.explicitEventSubscriptions` / owned subscriptions (`packages/protocol/src/messages.ts:3999`); on broadcast-era hosts it is pushed unconditionally.
- Semantic permission `workspace.read` (`packages/server/src/server/authorization/operation-permissions.ts:318`).

### 5.2 `checkout_commit_request` — commit staged/all changes

- **Name/purpose:** create a commit on the current branch.
- **Request:** type `checkout_commit_request` — `cwd: string`, optional `message: string`, optional `addAll: boolean`, `requestId: string` (`packages/protocol/src/messages.ts:2414-2420`).
- **Response:** type `checkout_commit_response` — `payload: { cwd, success: boolean, error: CheckoutError | null, requestId }` (`packages/protocol/src/messages.ts:5825-5833`).
- **Live updates:** triggers `checkout_status_update` + `checkout_diff_update` (server calls `scheduleDiffRefresh(cwd)` after mutations, `packages/server/src/server/session/checkout/checkout-session.ts:556-558`).
- **Capability gate:** none; semantic permission `workspace.write` (`packages/server/src/server/authorization/operation-permissions.ts:63`).
- **How the app uses it:** changes-panel commit flow (`packages/app/src/git/actions-store.ts:192`, push right after at `:222`, `:256`).
- **Gotchas:** `message` omitted → daemon generates one? (No: the handler passes it through to git; nothing in `checkout-session.ts` synthesizes a message — leaving `message` unset surfaces git's own error.) Empty tree → git exits non-zero → `error` set, `success: false`.

### 5.3 `checkout_push_request` — push current branch

- **Name/purpose:** `git push` the current branch to its upstream (sets upstream when absent, per server implementation).
- **Request:** type `checkout_push_request` — `cwd: string`, `requestId: string` (`packages/protocol/src/messages.ts:2445-2450`).
- **Response:** type `checkout_push_response` — `payload: { cwd, success: boolean, error: CheckoutError | null, requestId }` (`packages/protocol/src/messages.ts:5865-5873`).
- **Live updates:** `checkout_status_update` (ahead/behind reset), maybe `checkout_diff_update`.
- **Capability gate:** none; semantic permission `workspace.write` (`packages/server/src/server/authorization/operation-permissions.ts:70`).
- **How the app uses it:** changes-panel push (`packages/app/src/git/actions-store.ts:222`,`:256`); split-button UI (`packages/app/src/git/actions-split-button.tsx`).
- **Gotchas:** push can fail with non-fast-forward; the error is a `CheckoutError` with `code: "UNKNOWN"` — surface `error.message` verbatim.

### 5.4 `checkout_pull_request` / `checkout_merge_request` / `checkout_merge_from_base_request` — pull/merge

- **Name/purpose:** pull from upstream; merge a base ref into the current branch; merge the PR base into a working branch.
- **Request (pull):** type `checkout_pull_request` — `cwd`, `requestId` (`packages/protocol/src/messages.ts:2439-2444`). **Merge:** type `checkout_merge_request` — `cwd`, optional `baseRef`, optional `strategy: "merge"|"squash"`, optional `requireCleanTarget: boolean`, `requestId` (`:2422-2429`). **Merge from base:** type `checkout_merge_from_base_request` — `cwd`, optional `baseRef`, optional `requireCleanTarget`, `requestId` (`:2431-2438`).
- **Responses:** `checkout_pull_response` / `checkout_merge_response` / `checkout_merge_from_base_response` — each `payload: { cwd, success: boolean, error: CheckoutError | null, requestId }` (`packages/protocol/src/messages.ts:5855-5863`, `5835-5843`, `5845-5853`).
- **Live updates:** `checkout_status_update`, `checkout_diff_update`.
- **Capability gate:** none; semantic permission `workspace.write` (`packages/server/src/server/authorization/operation-permissions.ts:64-65`, `69-70`).
- **How the app uses it:** `packages/app/src/git/actions-store.ts:207`, `:252`, `:345`, `:364` (pull/merge/mergeFromBase); surfaced via `use-actions.tsx`.
- **Gotchas:** merge conflicts are reported as `CheckoutError.code: "MERGE_CONFLICT"` (`packages/protocol/src/messages.ts:2328`); `requireCleanTarget` aborts before touching a dirty tree instead of failing mid-merge.

### 5.5 `checkout.refresh.request` — force git snapshot refresh

- **Name/purpose:** force the daemon to recompute the git+forge snapshot for a cwd (and re-fire diff subscriptions).
- **Request:** type `checkout.refresh.request` — `cwd: string`, `requestId: string` (`packages/protocol/src/messages.ts:2451-2455`).
- **Response:** type `checkout.refresh.response` — `payload: { cwd, success: boolean, error: CheckoutError | null, requestId }` (`packages/protocol/src/messages.ts:5875-5883`).
- **Live updates:** `checkout_status_update`, `checkout_diff_update` (invalidates the forge cache too, `packages/server/src/server/session/checkout/checkout-session.ts:503-520`).
- **Capability gate:** `server_info.features.checkoutRefresh` (`packages/protocol/src/messages.ts:3917`); removed-able after 2026-11-29. Semantic permission `workspace.read` (`packages/server/src/server/authorization/operation-permissions.ts:61`).
- **How the app uses it:** pull-to-refresh on the changes view / after manual git operations outside the app.
- **Gotchas:** added v0.1.86 specifically to "poke" forge PR status from clients — without it, PR checks can look stale until the next git event (`packages/protocol/src/messages.ts:3916`).

### 5.6 `checkout.discard_changes.request` — discard working-tree paths

- **Name/purpose:** `git checkout -- <paths>` / restore selected hunks' files.
- **Request:** type `checkout.discard_changes.request` — `cwd: string`, `paths: string[]` (min 1), `requestId: string` (`packages/protocol/src/messages.ts:2457-2463`).
- **Response:** type `checkout.discard_changes.response` — `payload: { cwd, success: boolean, error: CheckoutError | null, requestId }` (`packages/protocol/src/messages.ts:5931-5939`).
- **Live updates:** `checkout_diff_update` (server calls `scheduleDiffRefresh`), `checkout_status_update`.
- **Capability gate:** `server_info.features.checkoutDiscardChanges` (`packages/protocol/src/messages.ts:4022`); semantic permission `workspace.write` (`packages/server/src/server/authorization/operation-permissions.ts:56`).
- **How the app uses it:** discard selected files in the changes panel (`packages/app/src/git/actions-store.ts:375-383`, wired at `packages/app/src/git/diff-pane.tsx:143-172`, gate `:146`).
- **Gotchas:** the discard path passes `paths` to git verbatim with `--literal-pathspecs` at the worktree root — no glob/pathspec injection (`packages/server/src/utils/checkout-git.ts:3849-3900`); `paths` are repo-relative in practice. Irreversible — the app confirms first.

### 5.7 `checkout.commits.list.request` / `checkout.commits.file_diff.request` — commit log ahead of base

- **Name/purpose:** list commits between base and HEAD (the "Commits" section); read one file's diff inside a commit.
- **Request (list):** type `checkout.commits.list.request` — `cwd`, `requestId` (`packages/protocol/src/messages.ts:2518-2523`). **File diff:** type `checkout.commits.file_diff.request` — `cwd`, `sha: string`, `path: string`, `requestId` (`:2524-2530`).
- **Response (list):** type `checkout.commits.list.response` — `payload: { cwd, baseRef: string | null, commits: CheckoutCommit[], error: CheckoutError | null, requestId }` (`packages/protocol/src/messages.ts:5941-5950`). `CheckoutCommit = { sha, shortSha, subject, authorName, authorDate (ISO), isOnRemote: boolean, isOnBase?: boolean (COMPAT v0.2.0), files: [{ path, additions, deletions, status?: "added"|"modified"|"deleted"|"renamed" }] }` (`:2506-2518`). **File diff:** type `checkout.commits.file_diff.response` — `payload: { cwd, sha, path, file: ParsedDiffFile | null (null = absent/binary), error, requestId }` (`:5952-5964`).
- **Live updates:** none (one-shot reads).
- **Capability gate:** `server_info.features.commitsList` (`packages/protocol/src/messages.ts:3981`); app gate `packages/app/src/git/use-commits-query.ts:80-88`. Per-commit base classification: `features.commitBaseClassification` (`:3983`). Semantic permission `workspace.read` (`packages/server/src/server/authorization/operation-permissions.ts:54-55`).
- **How the app uses it:** `listCheckoutCommits` / `getCommitFileDiff` in `packages/app/src/git/use-commits-query.ts:78-95` and `packages/app/src/git/commit-file-diff-query.ts:14-19` (60 s timeout, `packages/client/src/daemon-client.ts:4975-5015`).
- **Gotchas:** `isOnRemote: false` = local-only/unpushed commit; `isOnBase` additive COMPAT (remove after 2027-01-23, `packages/protocol/src/messages.ts:2513-2514`). `sha` re-validated server-side with `assertSafeGitRef` (`packages/server/src/server/worktree-session.ts:135-139`, called at `packages/server/src/server/session/checkout/checkout-session.ts:300`); `path` must be repo-relative — absolute paths and `..` are rejected (`checkout-session.ts:301-303`).

### 5.8 `checkout_switch_branch_request` / `checkout.rename_branch.request` / `validate_branch_request` / `branch_suggestions_request` — branch management

- **Name/purpose:** switch the working tree's branch; rename the current branch; check whether a branch/ref exists; autocomplete branch names.
- **Request (switch):** type `checkout_switch_branch_request` — `cwd`, `branch: string`, `requestId` (`packages/protocol/src/messages.ts:2589-2594` — note: flat name, not yet migrated).
- **Request (rename):** type `checkout.rename_branch.request` — `cwd`, `branch: string` (new name), `requestId` (`packages/protocol/src/messages.ts:2596-2601`).
- **Request (validate):** type `validate_branch_request` — `cwd`, `branchName: string`, `requestId` (`packages/protocol/src/messages.ts:2582-2587`).
- **Request (suggestions):** type `branch_suggestions_request` — `cwd`, optional `query: string`, optional `limit: int 1..200`, optional `refMode: "exact"`, `requestId` (`packages/protocol/src/messages.ts:2627-2635`).
- **Responses:** `checkout_switch_branch_response` — `{ cwd, success, branch: string, source?: "local"|"remote", error, requestId }` (`packages/protocol/src/messages.ts:6187-6197`). `checkout.rename_branch.response` — `{ requestId, success, cwd, currentBranch: string | null, error, }` (`:6199-6207`). `validate_branch_response` — `{ exists: boolean, resolvedRef: string | null, isRemote: boolean, error: string | null, requestId }` (`:6247-6256`). `branch_suggestions_response` — `{ branches: string[], branchDetails?: [{ name, committerDate: number, hasLocal?, hasRemote?, localAhead?, localBehind? }], error: string | null, requestId }` (`:6258-6277`).
- **Live updates:** `checkout_status_update` after switch/rename.
- **Capability gate:** none; semantic permission `workspace.write` (switch/rename), `workspace.read` (validate/suggestions) (`packages/server/src/server/authorization/operation-permissions.ts:72`, `:62`, `:43`).
- **How the app uses it:** branch switcher (`packages/app/src/git/branch-switcher-operations.ts`, `git/use-branch-switcher.ts`); New-workspace base picker uses `getBranchSuggestions` + `validateBranch` (`packages/app/src/screens/new-workspace-screen.tsx`, SDK `packages/client/src/daemon-client.ts:5360-5385`, `:5348-5358`).
- **Gotchas:** `branchDetails` divergence (`localAhead`/`localBehind`) is against the resolved upstream — use `hasLocal`/`hasRemote` to decide whether to render one row or two (same file, `packages/app/src/screens/new-workspace-picker-item.ts:65-113`).

### 5.9 `stash_save_request` / `stash_pop_request` / `stash_list_request` — stash

- **Name/purpose:** save/pop/list git stashes (Paseo-created ones tagged).
- **Requests:** type `stash_save_request { cwd, branch?, requestId }` (`packages/protocol/src/messages.ts:2603-2609`), type `stash_pop_request { cwd, stashIndex: int ≥ 0, requestId }` (`:2611-2617`), type `stash_list_request { cwd, paseoOnly?: boolean (default true), requestId }` (`:2619-2625`).
- **Responses:** `stash_save_response` / `stash_pop_response` — `{ cwd, success, error, requestId }` (`packages/protocol/src/messages.ts:6217-6225`, `6227-6235`); `stash_list_response` — `{ cwd, entries: [{ index, message, branch: string | null, isPaseo: boolean }], error, requestId }` (`:6237-6245`).
- **Live updates:** `checkout_diff_update` after save/pop.
- **Capability gate:** none; `workspace.write` / `workspace.read` (operation-permissions map, stash entries).
- **How the app uses it:** branch switcher stash save/pop/list (`packages/app/src/git/branch-switcher-operations.ts:9-12`); no other call sites in `packages/app/src`.
- **Gotchas:** `stashIndex` is the index from `stash_list_response`, not a stable id — list immediately before pop.

## 6. Forge (GitHub) — PRs, checks, search, clone

All forge RPCs are `cwd`-scoped. The forge is resolved from the repo's remote URL server-side (GitHub, GitLab, Gitea-family); GitHub is the default facts family (`forge ?? "github"`, `packages/protocol/src/messages.ts:5711-5713`). Forge-neutral RPCs use `checkout.forge.*`; GitHub-specific legacy names remain served (`docs/rpc-namespacing.md:67-77`).

### 6.1 `checkout_pr_status_request` — PR/MR status for the branch

- **Name/purpose:** fetch the open PR/MR for the current branch (state, mergeable, checks, review decision, forge auth state).
- **Request:** type `checkout_pr_status_request` — `cwd: string`, `requestId: string` (`packages/protocol/src/messages.ts:2567-2571`).
- **Response:** type `checkout_pr_status_response` — `payload: CheckoutPrStatusPayload` = `{ cwd, status: CheckoutPrStatusSchema | null, githubFeaturesEnabled: boolean, authState?, forge?: string (default "github"), error: CheckoutError | null, requestId }` (`packages/protocol/src/messages.ts:6069-6072`, payload schema `:5766-5779`). `CheckoutPrStatusSchema = { forge? (default github), projectPath?, number?, url, title, state, baseRefName, headRefName, isMerged, isDraft?, mergeable: "MERGEABLE"|"CONFLICTING"|"UNKNOWN" (catch UNKNOWN), checks?: [{ name, status, url: string|null, workflow?, duration?, checkRunId?, workflowRunId?, traits? }], checksStatus?, reviewDecision?: string|null, repoOwner?, repoName?, github?: {...repository policy/autoMerge facts}, forgeSpecific?: unknown }` (`:5708-5764`).
- **Live updates:** also delivered inside `checkout_status_update` as `prStatus` (`packages/protocol/src/messages.ts:5781-5794`, producer `checkout-session.ts:525-543`) — the app does not need to poll.
- **Capability gate:** none for the RPC itself; `forgeSpecific` facts need no gate (open envelope), GitHub-specific auto-merge UI gates on `checkoutForgeSetAutoMerge`/`checkoutGithubSetAutoMerge` (§6.3). Semantic permission `workspace.read` (`packages/server/src/server/authorization/operation-permissions.ts:68`).
- **How the app uses it:** `useCheckoutPrStatusQuery` → `client.checkoutPrStatus(cwd)` (`packages/app/src/git/use-pr-status-query.ts:21-51`); PR panel via `packages/app/src/git/pull-request-connection.tsx:6-23`.
- **Gotchas:** `forgeSpecific` is a facts-family tag, **not** the brand — Gitea/Forgejo/Codeberg all emit `forge: "gitea"`; top-level `status.forge` carries the brand (`docs/forge-providers.md:44-60`). `mergeable` is `.catch("UNKNOWN")` on the wire — never assume it is absent. `githubFeaturesEnabled` is the legacy boolean. The forward-compatible replacement is `authState`, but it is **`z.unknown().optional()` on the wire** (`packages/protocol/src/messages.ts:5764`, `:5773`) — the `"authenticated"|"unauthenticated"|"cli_missing"|"no_remote"|"error"` union is only a TS type. Decode it as an opaque value and treat unrecognised strings as unknown, not as a decode error. Auto-update expectations: PR checks only refresh on git events or `checkout.refresh.request` (§5.5).

### 6.2 `checkout_pr_create_request` / `checkout_pr_merge_request` — open and merge the PR

- **Name/purpose:** open a PR/MR for the current branch; merge an open one.
- **Request (create):** type `checkout_pr_create_request` — `cwd`, optional `title`, optional `body`, optional `baseRef`, `requestId` (`packages/protocol/src/messages.ts:2464-2471`). **Merge:** type `checkout_pr_merge_request` — `cwd`, `mergeMethod: "merge"|"squash"|"rebase"`, `requestId` (`:2473-2478`).
- **Response (create):** type `checkout_pr_create_response` — `{ cwd, url: string | null, number: number | null, error: CheckoutError | null, requestId }` (`packages/protocol/src/messages.ts:5885-5894`). **Merge:** type `checkout_pr_merge_response` — `{ cwd, success: boolean, error, requestId }` (`:5896-5904`).
- **Live updates:** `checkout_status_update` (+ `prStatus`), `checkout_diff_update`.
- **Capability gate:** none; semantic permission `workspace.write` (`packages/server/src/server/authorization/operation-permissions.ts:66-67`).
- **How the app uses it:** `packages/app/src/git/actions-store.ts:271`, `:286` (create/merge); buttons in the changes panel (`packages/app/src/git/use-actions.tsx:739-740`).
- **Gotchas:** create requires the branch to have an upstream or pushes implicitly? (Server implementation pushes before opening; treat any push failure as the error.) Merge waits for forge state, not local git state — `error` set when branch protection blocks; `isInMergeQueue`/`isMergeQueueEnabled` visible only via `github` facts (§6.1).

### 6.3 `checkout.forge.set_auto_merge.request` — enable/disable auto-merge

- **Name/purpose:** toggle forge-side auto-merge on the open PR/MR.
- **Request:** type `checkout.forge.set_auto_merge.request` — `cwd: string`, `enabled: boolean`, optional `mergeMethod: "merge"|"squash"|"rebase"`, `requestId: string` (`packages/protocol/src/messages.ts:2480-2486`).
- **Legacy twin:** type `checkout.github.set_auto_merge.request` — same shape (`packages/protocol/src/messages.ts:2491-2497`; COMPAT(githubAutoMergeRpc), remove after 2027-01-17, `:2488-2490`).
- **Response:** type `checkout.forge.set_auto_merge.response` — `{ cwd, enabled: boolean, success: boolean, error: CheckoutError | null, requestId }` (`packages/protocol/src/messages.ts:5906-5914`); legacy `checkout.github.set_auto_merge.response` identical (`:5916-5929`).
- **Live updates:** `checkout_status_update` (with updated `prStatus.github.autoMergeRequest`).
- **Capability gate:** `server_info.features.checkoutForgeSetAutoMerge` (`packages/protocol/src/messages.ts:3849`); fallback `features.checkoutGithubSetAutoMerge` (`:3853`). Neither set → host too old; hide the control (no fallback path, `docs/protocol-compatibility.md:35-46`). Semantic permission `workspace.write` (`packages/server/src/server/authorization/operation-permissions.ts:58`).
- **How the app uses it:** changes-panel/PR-pane auto-merge toggle (`packages/app/src/git/actions-store.ts:303-334`, feature selection `:50-58`).
- **Gotchas:** do not send `mergeMethod` when disabling (`enabled: false`) — daemons older than the squash-default expect it absent or ignored. `viewerCanEnableAutoMerge`/`repository.autoMergeAllowed` on the PR status tell you whether to show the toggle at all (`packages/protocol/src/messages.ts:5682-5706`).

### 6.4 `checkout.forge.get_check_details.request` — check-run/workflow details

- **Name/purpose:** fetch one check run's output/annotations/failed jobs (or a full pipeline for GitLab-family forges).
- **Request:** type `checkout.forge.get_check_details.request` — `cwd`, optional `repoOwner`/`repoName` (GitHub only), optional `checkRunId: int > 0`, optional `workflowRunId: int > 0`, optional `changeRequestNumber: int > 0` (forge-routing field for GitLab/Gitea), `requestId` (`packages/protocol/src/messages.ts:2534-2558`). Legacy twin `checkout.github.get_check_details.request` (`:2562-2567`).
- **Response:** type `checkout.forge.get_check_details.response` — `{ cwd, success: boolean, details: CheckoutCheckDetailsSchema | null (default null), error: CheckoutError | null, requestId }` (`packages/protocol/src/messages.ts:6044-6052`). CheckoutGithubCheckDetailsSchema at `packages/protocol/src/messages.ts:6019-6042`: `{ checkRunId, workflowRunId?, name, status?, conclusion?, url?, detailsUrl?, output?: { title?, summary?, text? } | null, annotations: [{ path?, startLine?, endLine?, annotationLevel?, message?, title?, rawDetails? }], failedJobs: [{ jobId, name, status?, conclusion?, url?, logTail?, logTruncated? }], truncated: boolean, pipeline?: CheckoutPipelineSchema | null }` (`:5990-6042`).
- **Live updates:** none (one-shot).
- **Capability gate:** `server_info.features.forgeCheckDetails` (`packages/protocol/src/messages.ts:3861`); fallback `features.githubCheckDetails` (`:3857`). Semantic permission `workspace.read` (`:57`).
- **How the app uses it:** check-details sheet in the PR panel (`packages/app/src/git/pull-request-panel/checks-section.tsx`).
- **Gotchas:** at least one of `checkRunId`/`workflowRunId` is expected per forge (Gitea runs carry no check-run id); `changeRequestNumber` required by GitLab/Gitea adapters to locate the head pipeline/SHA — nothing enforces it on the wire, the forge adapter errors in-band instead (`packages/protocol/src/messages.ts:2534-2552`). `rawStatus` on pipeline jobs is a COMPAT peer field, optional to emit after v0.2.0 (`:6009-6013`).

### 6.5 `forge.search.request` — search issues/change requests

- **Name/purpose:** search the forge for issues and change requests (used for `@`-mentioning PRs in the composer and the PR checkout picker).
- **Request:** type `forge.search.request` — `cwd`, `query: string`, optional `limit: int 1..50`, optional `kinds: ForgeSearchKind[]` where `ForgeSearchKind = "issue"|"change_request"|"github-issue"|"github-pr"|"pr"` (legacy aliases retained), `requestId` (`packages/protocol/src/messages.ts:2668-2675`, kinds enum `:2658-2664`).
- **Legacy twin:** type `github_search_request` — same shape (`packages/protocol/src/messages.ts:2680-2688`; COMPAT(githubSearchRpc), remove after 2027-01-17).
- **Response:** type `forge.search.response` — `payload: { items: unknown[] (ForgeSearchItem-ish, see below), authState?: unknown, error: string | null, requestId }` (`packages/protocol/src/messages.ts:6295-6302`, payload `:6279-6284`). Items parse as `ForgeSearchItem = { kind: "issue"|"change_request", forge?, number, title, url, state, body: string | null, labels: string[], projectPath?, baseRefName?, headRefName?, updatedAt? }` (`:2636-2655`). Legacy `github_search_response` carries `featuresEnabled`/`githubFeaturesEnabled` booleans instead of `authState` (`:6286-6308`).
- **Live updates:** none.
- **Capability gate:** `server_info.features.forgeSearch` (`packages/protocol/src/messages.ts:3865`); fallback: send `github_search_request` with mapped kinds `github-issue`/`github-pr` (`packages/app/src/git/use-forge-search-query.ts:85-110`). Semantic permission `workspace.read` (`packages/server/src/server/authorization/operation-permissions.ts:101`).
- **How the app uses it:** `useForgeSearchQuery` → `client.searchForge` (`packages/client/src/daemon-client.ts:5376-5395`), legacy `.searchGitHub` at `:5397-5414`; call sites: composer `@`-mention (`packages/app/src/composer/index.tsx:168`, `:2142`), New-workspace PR picker (`packages/app/src/screens/new-workspace-screen.tsx:1068`, gate `:886`).
- **Gotchas:** items are typed `z.unknown()` at the response boundary by design — parse with `ForgeSearchItemSchema`-compatible guards client-side; the legacy twin maps `change_request → github-pr` (`packages/app/src/git/use-forge-search-query.ts:152-160`). Rate limit: `gh` CLI's own token; `authState` tells you why results are empty (`gh_missing`/`unauthenticated`).

### 6.6 `pull_request_timeline_request` — PR timeline (reviews/comments)

- **Name/purpose:** fetch review/comment timeline for one PR.
- **Request:** type `pull_request_timeline_request` — `cwd`, `prNumber: number`, `repoOwner: string`, `repoName: string`, `requestId` (`packages/protocol/src/messages.ts:2573-2580`).
- **Response:** type `pull_request_timeline_response` — payload with `items: PullRequestTimelineItem[]` (discriminated `kind: "review"|"comment"|"commit"?` …) plus `error` (`packages/protocol/src/messages.ts:6167-6244` — discriminated union `PullRequestTimelineKnownErrorSchema` at `:6074-6089`, items `:6098-6165`).
- **Live updates:** none (refetch on demand).
- **Capability gate:** none; semantic permission `workspace.read` (`packages/server/src/server/authorization/operation-permissions.ts:167`).
- **How the app uses it:** PR panel timeline (`packages/app/src/git/pull-request-panel/timeline.ts`).
- **Gotchas:** error kinds are `not_found|forbidden|unknown`, anything else maps to `unknown` via preprocess (`packages/protocol/src/messages.ts:6089-6098`). `reviewId` nests inline comments under a review — absent on daemons that predate it and on issue comments (`:6126-6130`).

### 6.7 The clone flow, end to end

1. App checks `features.workspaceGithubRepositorySearch` → query search: `workspace.github.search_repositories.request` (§1.8).
2. App checks `features.projectGithubClone` → `project.github.clone.request` (§1.9) with `targetDirectory` = chosen parent path; daemon clones via `git clone` in a staging dir, renames into place, registers the project (`packages/server/src/server/session.ts:7548-7611`).
3. Response's `project` descriptor is accepted into the host store (`packages/app/src/hooks/open-project.ts:142-150`); the app then navigates to New workspace with that project selected (`packages/app/src/components/add-project-flow.tsx:566-577`).
4. Creating a workspace from a PR: pick the PR in the New-workspace picker → `action: "checkout"` + `checkoutSource` (+ `githubPrNumber` COMPAT) → `workspace.create.request` §2.2 — the daemon cuts the worktree and checks the PR head out.

## 7. Files (fs.*)

File RPCs are `cwd`-scoped; paths may be relative (resolved against `cwd`) or absolute. Reads/writes go through `file_explorer_request` and the `fs.file.*` family. Directory listing and inline file reads are one RPC with a `mode` switch.

### 7.1 `file_explorer_request` — list a directory or read a file

- **Name/purpose:** one-shot directory listing (`mode: "list"`) or file read (`mode: "file"`).
- **Request:** type `file_explorer_request` — `cwd: string`, optional `path: string` (default: root of `cwd`), `mode: "list"|"file"`, `requestId: string`, optional `acceptBinary: boolean`, optional `maxBytes: int > 0` (`packages/protocol/src/messages.ts:2961-2969`).
- **Response:** type `file_explorer_response` — `payload: { cwd, path: string, mode, directory: FileExplorerDirectorySchema | null, file: FileExplorerFileSchema | null, error: string | null, requestId }` (`packages/protocol/src/messages.ts:6364-6375`). `FileExplorerEntry = { name, path, kind: "file"|"directory", size: number, modifiedAt: string }` (`:2937-2943`); `FileExplorerDirectory = { path, entries: FileExplorerEntry[] }` (`:2956-2960`); `FileExplorerFile = { path, kind: "text"|"image"|"binary", encoding: "utf-8"|"base64"|"none", content?: string, mimeType?, size, modifiedAt, revision? }` (`:2945-2954`).
- **Live updates:** none — for watching use §7.2.
- **Capability gate:** none; semantic permission `workspace.read` (`packages/server/src/server/authorization/operation-permissions.ts:100`).
- **How the app uses it:** `client.listDirectory(cwd, path)` (throws on error) and `client.readFile(cwd, path, undefined, maxBytes, timeout)` (`packages/client/src/daemon-client.ts:5471-5489`, `:5491-5534`); call sites `packages/app/src/hooks/use-file-explorer-actions.ts:104-110`, `:163`; file pane via `file-panels/file/daemon-session.ts:58-64`.
- **Gotchas:** large files: pass `maxBytes`; with `acceptBinary` the daemon streams **binary frames** — opcodes `0x10 FileBegin`, `0x11 FileChunk`, `0x12 FileEnd`, each `opcode | requestIdLen | requestId | …` (FileBegin then carries a `uint16` metadata length and a JSON `{mime, size, encoding: "utf-8"|"binary", modifiedAt, revision?, fileName?}`), correlated by **`requestId`, not slot** — before/instead of inline JSON (`packages/protocol/src/binary-frames/file-transfer.ts:5-9`, `:58-88`; `docs/architecture.md` §Binary frames). The client SDK reassembles transparently when you call `readFile` — direct `file_explorer_request` users must handle both paths. Without a binary channel, files arrive inline as base64/`encoding: "base64"`.

### 7.2 `fs.file.subscribe.request` / `fs.file.unsubscribe.request` — watch a file

- **Name/purpose:** observe one file; get the current stat and pushed versions on change.
- **Request:** type `fs.file.subscribe.request` — `cwd`, `path`, optional `subscriptionId` (host assigns if omitted), `requestId: string` (`packages/protocol/src/messages.ts:2997-3004`). **Unsubscribe:** type `fs.file.unsubscribe.request` — `subscriptionId: string`, `requestId: string` (`:3005-3010`).
- **Response:** type `fs.file.subscribe.response` — `payload: { subscriptionId, initial: FileVersionSchema, requestId }` (`packages/protocol/src/messages.ts:6377-6384`). `FileVersion` = discriminated union on `status`: `ready { cwd, path, size (int ≥ 0), modifiedAt, revision?, kind?: "text"|"image"|"binary", mimeType? }` | `missing { cwd, path }` | `error { cwd, path, error }` (`:2971-2995`). Unsubscribe response: `fs.file.unsubscribe.response { subscriptionId, requestId }` (`:6386-6393`).
- **Live updates:** `fs.file.update` — `payload: { subscriptionId, version: FileVersion }` (`packages/protocol/src/messages.ts:6460-6467`). Release: `fs.file.unsubscribe.request` (legacy) or `subscription.release.request` (modern, §4.4).
- **Capability gate:** none on the wire; the app only uses it when `features.workspaceFileEditing` is set (else the app falls back to stat-on-read, no watcher) — gate and COMPAT comments live in that file (`:22-38`).
- **How the app uses it:** `client.subscribeFile({ cwd, path, signal? }, onUpdate)` (`packages/client/src/daemon-client.ts:5540-5568`); session wrapper `packages/app/src/file-panels/file/daemon-session.ts:17-52`; file pane subscribes while visible.
- **Gotchas:** the file-observer is the recursive-capable daemon watcher with strict teardown invariants — `unsubscribe()` is an awaited barrier after which no callback may fire; Linux is directory-watch based, not recursive `fs.watch` (`docs/file-observation.md:3-13`). Workspace archive can delete the watched worktree mid-watch — treat `missing`/`error` versions as normal (`docs/file-observation.md:7`). `initial` + subsequent `fs.file.update`s may race; client SDK handles reconnect replay (`packages/client/src/daemon-client.ts:5547-5562`).

### 7.3 `fs.file.write.request` — write a file (conflict-checked)

- **Name/purpose:** write text (or bytes) to a file with optimistic-concurrency check.
- **Request:** type `fs.file.write.request` — `cwd`, `path`, `content: string`, optional `contentEncoding: "utf-8"|"base64"` (bytes; daemons without the feature write `content` as text — COMPAT(fileByteWrites)), `expectedModifiedAt: string`, optional `expectedRevision: string`, `requestId` (`packages/protocol/src/messages.ts:3011-3022`).
- **Response:** type `fs.file.write.response` — `payload: { result: FileWriteResultSchema, requestId }`, result = `written { modifiedAt, size, revision? }` | `conflict { version: FileVersion }` | `error { error }` (`packages/protocol/src/messages.ts:6394-6403`, `6405-6411`).
- **Live updates:** `fs.file.update` for subscribers of that path (§7.2).
- **Capability gate:** text writes → `features.workspaceFileEditing` (`packages/protocol/src/messages.ts:3931`); binary (`contentEncoding: "base64"`) → `features.fileByteWrites` (`:3933`); app gates at `packages/app/src/file-panels/file/daemon-session.ts:12-16`, `:49-56`. Semantic permission `workspace.write` (`packages/server/src/server/authorization/operation-permissions.ts:108`).
- **How the app uses it:** `client.writeFile(...)` from the file pane save path (`packages/app/src/file-panels/file/daemon-session.ts:48-56`).
- **Gotchas:** `expectedModifiedAt` is mandatory — no blind overwrite; on mismatch you get `conflict` with the current `FileVersion` (re-read, merge, retry). mtime comparison is string-based on the wire.

### 7.4 `fs.entry.create` / `fs.entry.rename` / `fs.entry.duplicate` / `fs.entry.delete` — entry mutations

- **Name/purpose:** create (file or directory), rename, duplicate, delete a filesystem entry.
- **Requests:** `fs.entry.create.request { cwd, parentPath, name, kind: "file"|"directory", requestId }` (`packages/protocol/src/messages.ts:3023-3031`); `fs.entry.rename.request { cwd, path, name, requestId }` (`:3032-3039`); `fs.entry.duplicate.request { cwd, path, requestId }` (`:3040-3046`); `fs.entry.delete.request { cwd, path, requestId }` (`:3047-3053`).
- **Responses:** `fs.entry.create.response { cwd, parentPath, path: string|null, success, error, requestId }` (`packages/protocol/src/messages.ts:6413-6423`); `fs.entry.rename.response { cwd, path, renamedPath: string|null, success, error, requestId }` (`:6425-6435`); `fs.entry.duplicate.response { cwd, path, duplicatedPath: string|null, success, error, requestId }` (`:6437-6447`); `fs.entry.delete.response { cwd, path, success, error, requestId }` (`:6449-6458`).
- **Live updates:** directory subscribers get `fs.file.update`-adjacent signals only via the workspace git observer / file explorer refetch — there is **no directory-watch wire event**; the app re-lists on mutation.
- **Capability gate:** `features.fsEntryOps` (`packages/protocol/src/messages.ts:4018`) for create/rename/delete; `features.fsEntryDuplicate` (`:4020`) for duplicate; semantic permission `workspace.write` (`packages/server/src/server/authorization/operation-permissions.ts:102-105`).
- **How the app uses it:** file explorer context menu (`packages/app/src/components/file-explorer-pane.tsx:449-470`) via `packages/app/src/hooks/use-file-explorer-actions.ts`.
- **Gotchas:** name collisions return `success: false` with `error` set, not `rpc_error`. `duplicate` copies server-side (no client bytes round-trip). Delete is unlink/rmdir only — no trash.

## 8. Capability gate cheat sheet

| Feature key (`server_info.features.*`) | Gates | messages.ts |
|---|---|---|
| `projectList` | project.list.request | :3977 |
| `projectAdd` | project.add.request | :3923 |
| `projectRemove` | project.remove.request | :3921 |
| `projectCreateDirectory` | project.create_directory.request | :3975 |
| `projectGithubClone` | project.github.clone.request | :3971 |
| `workspaceGithubRepositorySearch` | workspace.github.search_repositories.request | :3973 |
| `stableProjectIdentity` | app's Add-project gate for §1.3 | :4012 |
| `backgroundWorkspaces` | fetch_workspaces(includeBackground), background workspace.create | :3824 |
| `workspaceMultiplicity` | worktree workspace.create source; app's New-workspace screen | :3919 |
| `directorySync` | `sync` cursors on project.list/fetch_workspaces | :3836 |
| `ownedSubscriptions` | subscription.release.request; modern subscription path | :4000 |
| `explicitEventSubscriptions` | observeEvents(["checkout_status_update", …]) | :3999 |
| `diffSubscription` | binary diff.subscribe.request | :4001 |
| `checkoutDiffAll` | compare.mode = "all" | :4023 |
| `checkoutRefresh` | checkout.refresh.request | :3917 |
| `checkoutDiscardChanges` | checkout.discard_changes.request | :4022 |
| `commitsList` | checkout.commits.list.request | :3981 |
| `commitBaseClassification` | isOnBase field | :3983 |
| `checkoutForgeSetAutoMerge` | checkout.forge.set_auto_merge.request | :3849 |
| `checkoutGithubSetAutoMerge` | legacy twin | :3853 |
| `forgeCheckDetails` / `githubCheckDetails` | checkout.forge.get_check_details.request | :3861 / :3857 |
| `forgeSearch` | forge.search.request | :3865 |
| `workspaceFileEditing` | fs.file.subscribe, fs.file.write (text) | :3931 |
| `fileByteWrites` | fs.file.write with base64 contentEncoding | :3933 |
| `fsEntryOps` | fs.entry.create/rename/delete | :4018 |
| `fsEntryDuplicate` | fs.entry.duplicate.request | :4020 |
| `workspacePinning` | workspace.pin.set.request | :3962 |
| `workspaceMarkUnread` | workspace.mark_unread.request | :3964 |
| `workspaceBaseBranch` | workspace.base_branch.set.request | :3841 |
| `workspaceArchiveUndo` | workspace.archive.undo.request | :3929 |
| `workspaceRecovery` | workspace.recovery.* | :3927 |
| `workspaceSetupObservation` / `workspaceSetupRun` | workspace.setup.subscribe/run | :4003 / :3843 |
| `projectCustomIcon` | project.icon.set.request | :4016 |

## 9. Minimal set for a v1 client

Must-have (read path for everything the sidebar shows + the diff view + file preview):

1. `hello` handshake + `server_info` parsing (`packages/protocol/src/messages.ts:3796-3810`) — without it nothing else parses. Remember `server_info.features` is `optional` and every flag inside it is optional: absent means "old host", never `false`-but-present.
2. `fetch_workspaces_request` with `subscribe: {}` once per host (+ `workspace_update` handling) — sidebar directory (§2.1); pair with `project.list.request` when `features.projectList` (§1.1).
3. `project.add.request` (§1.3) — registering an existing folder is the Add-project CTA; `workspace.create.request` does **not** dedupe by directory and is the wrong RPC for "open this folder".
4. `workspace.create.request` — both `source` kinds; without it the client can't cut worktrees (§2.2).
5. `archive_workspace_request` (§2.4) and `workspace.title.set.request` (§2.5) — rename/archive.
6. `checkout_status_request` + `checkout_status_update` (§5.1/5.1a) — branch/dirty/ahead-behind/PR badge everywhere.
7. `subscribe_checkout_diff_request` + `checkout_diff_update` + `unsubscribe_checkout_diff_request` (§4.2) — the legacy baseline works on every daemon; add §4.1 (`diff.subscribe.request`, binary) when `features.diffSubscription`.
8. `checkout.diff.get.request` (§4.3) as the one-shot fallback.
9. `checkout_pr_status_request` (§6.1) — PR panel; it rides on `checkout_status_update.prStatus` too, so a minimal client can skip the poll and read the push payload.
10. `file_explorer_request` (list + file, §7.1) — file explorer and file preview; add `fs.file.subscribe.request` (§7.2) for live reload when `workspaceFileEditing`.
11. `checkout_commit_request`, `checkout_push_request` (§5.2/5.3) — the two write actions every changes view needs.
12. `project.github.clone.request` (§1.9) — clone-into-workspace flow; gate on `projectGithubClone`.
13. `subscription.release.request` (§4.4) — required to tear down 2/7/10 cleanly on modern hosts.

Revision of this list against the stated v1 features: nothing above is missing except that (a) `checkout.discard_changes.request` (§5.6) and `workspace.pin.set.request` (§2.5) are cheap “expected in a git client” additions, and (b) if the changes view shows a “switch branch” control you also need `branch_suggestions_request` / `checkout_switch_branch_request` (§5.8), which this list defers.

Nice-to-have after v1: everything else — forge search/auto-merge/check-details, commits list, branch management RPCs, `fs.entry.*`, `checkout.refresh.request`, worktree archive/list, pin/base-branch, setup observation.

Explicitly NOT needed for v1: workspace labels, archive undo/recovery, stash, `project.suggestions.request`, `directory_suggestions_request`, binary chunking negotiation details, terminals, agents.

## Verification

Audited in place: protocol facts re-derived from `packages/protocol/src/messages.ts`, `binary-frames/*.ts`, `packages/client/src/**` and the cited app call sites. 158 facts checked, 21 corrected.
