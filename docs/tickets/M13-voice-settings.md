# M13: host Voice settings and local speech models

Branch `m13-voice-settings`. Read `AGENTS.md`, `ARCHITECTURE.md`, `docs/tickets/PHASE3-BACKEND.md`,
shared UI rules at the top of `docs/tickets/M3-workspace-panel.md`. Cite path:line for wire claims.
Reference: doc 01 lines ~301, 349-354, doc 04 ~:1343 (`speech.local_models.list/download/delete`),
upstream app voice/speech settings components and i18n wording. Update the Voice rows in
`docs/PARITY.md` and recount.

1. **Host → Voice page** in Settings (host group): Dictation switch + speech-to-text provider row,
   Voice mode switch, Listening/Speaking provider rows, read and written through the existing
   host config patch path (`set_daemon_config_request`, deep-partial), gated like upstream.
2. **Speech provider sheets**: Local (model catalog with sizes, recommended mark, download with
   progress, delete; `speech.local_models.*`) and OpenAI (API key / base URL / model / language /
   voice). The API key is a secret: never log it, never echo it back in UI after save (show
   "Saved"), and keep it out of the Diagnostics report.
3. Store work in PaseoStore with FakeDaemonClient tests; scrubbed fixtures only. Any download
   progress push needs an owner subscription under T17's modern socket: read
   `docs/research/09-owned-subscriptions.md` and wire it the same way.
4. Voice mode itself (realtime conversation) is out of scope: note what it would need.

Read-only live checks only (list models, read config). Do NOT download/delete models or change
the host's config live. Never touch other agents. Done = PaseoCore `rm -rf .build && swift build
--build-tests && swift test` green, `swiftc -parse` on touched UI files, `Tools/api-audit` no new
real findings. No background tasks or subagents; don't end your turn while waiting. Commit
"M13: voice settings", don't push. Final message: what changed, wire citations, test totals,
unsure-compile spots, what realtime voice mode would need.
