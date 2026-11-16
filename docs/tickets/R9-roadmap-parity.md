# R9: parity checklist (docs only)

Branch `r9-parity`. Produce `docs/PARITY.md`: one checklist of every user-facing feature of
(a) Paseo's app/web client and (b) the DSH Claude-style plugin, with this client's status for
each. No code changes. No background tasks, no subagents, don't end your turn while waiting.

Sources (cite file:line for each feature row):
- Paseo app: `docs/research/01-app-features.md` (inventory), `02`, `03`, `04` (protocol areas),
  and the app source `/home/paseo/dev/paseo-reference/packages/app/src` to fill gaps.
- DSH: `docs/research/06-dsh-ux-spec.md`, `08-dsh-live-observation.md`, and
  `/home/paseo/dev/dsh-claude-style-reference/packages/client/src/features/` (one folder per
  feature: list every folder and what it does).
- This client: `Packages/PaseoCore/Sources` (stores, what's wired), `Packages/PaseoUI/Sources`
  (screens), `docs/STATUS.md`, `docs/tickets/` (M3 is in flight: panel, files, changes, terminal).

Format: sections by area (Connection & hosts, Sidebar & navigation, Workspaces & projects,
Conversation & turns, Composer, Agents & models, Permissions, Files, Git & changes, Terminals &
scripts, Schedules, Settings, Notifications & attention, Rich content, Mascot, Search & history,
Voice, Desktop-only). Each row: `- [ ] Feature: one line` + `Status:` one of
`done` / `store only (no UI)` / `in flight (M3x)` / `missing` / `desktop-only (flag)` /
`not applicable (why)` + `Source:` citation. Mark `done` only if you find the UI code for it.
End with a "Suggested milestones" section grouping the missing items into 4–6 milestones in a
sensible order (dependencies first, highest daily value first), each one sentence.

Commit as "R9: parity checklist". Final message: counts per status and the milestone list.
