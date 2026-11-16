# T7: Workspaces, git and files

The sidebar's workspaces and projects, worktrees, the git state of a checkout, its diff, browsing
files, commit/push, and cloning a GitHub repo. Read `PHASE2-CONVENTIONS.md`.

Spec: `docs/research/02-protocol-workspaces-git-files.md`, especially §1 (projects), §2
(workspaces), §4 (diffs), §5 (checkout status/commit/push), §7 (files), §1.9 (GitHub clone),
§4.4 (subscription release) and §9 "Minimal set for a v1 client".

## What the UI will need (design the API to serve this)

1. **Directory.** A live list of projects and their workspaces (name, kind, branch, status
   bucket, diff stat, scripts), kept current by the daemon's subscription. A `WorkspaceDirectory`
   store owned by `HostSession`.
2. **Add a project** from a folder path on the host, and **create a workspace**: local, or a
   worktree in each mode (new branch off a base, existing branch, PR). Rename, archive.
3. **Checkout** (one store per open workspace): branch, dirty state, ahead/behind, PR badge;
   the **diff** as files with hunks and +/- lines (use the legacy JSON pipeline,
   `subscribe_checkout_diff_request`, which works on every daemon; release it when closed);
   **commit** with a message and **push**.
4. **Files**: list a directory and read a file (text, with size limits respected) in a workspace.
5. **Clone**: search the user's GitHub repos (gated on its feature flag; needs `gh` on the host)
   and clone one into a new project.

## Live fixtures

Only `/tmp/fixture-sandbox` (already a Paseo workspace and a git repo with commits) and new dirs
under `/tmp/fixture-git`. Make a change there to get a non-empty diff, create and archive a
worktree workspace from it, list files, read one. For commit/push, use a scratch repo under
`/tmp/fixture-git` with a local bare repo as its remote (`git init --bare`), never GitHub. For
clone, capture only the repository search (read-only); do not clone anything unless it's a tiny
public repo into `/tmp/fixture-git`, and archive/remove the project afterwards.

## Probe

`paseo-probe workspaces`: prints projects/workspaces; `paseo-probe checkout <workspaceId>`:
status and diff summary; `paseo-probe files <workspaceId> [path]`: a listing.
