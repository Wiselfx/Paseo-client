# M16: several hosts in the UI

Branch `m16-multi-host`. Read `AGENTS.md`, `ARCHITECTURE.md`, shared UI rules at the top of
`docs/tickets/M3-workspace-panel.md`. Builds on M1b saved hosts (Keychain per host, footer host
switcher, Settings → Hosts). Update `docs/PARITY.md` rows (Connection & hosts, Sidebar) and recount.
Reference: doc 01 lines ~102, 110, 295-297; upstream sidebar host groups/badges, host settings
Connections + Danger zone, i18n wording.

1. **Host identity in the sidebar**: a quiet host badge (name + per-host color/appearance as
   upstream does) where it helps tell hosts apart, only when more than one host is saved; the
   footer switcher stays the one place to switch (no second switcher), unless upstream's phone
   layout clearly does otherwise: then follow upstream and remove ours.
2. **Host settings → Connections**: if the protocol exposes a connections list (check
   `messages.ts`; doc 01:297), list them (label, live latency, remove). If it's only the app's own
   saved endpoints for that host, show those from SavedHosts. Cite which.
3. **Danger zone**: Remove this host (forget saved endpoint + Keychain secret, confirmation with
   upstream wording, then switch to another saved host or the welcome/connect screen).
4. **Add-provider catalog** (PARITY row "Add-provider catalog with Install buttons"): only if the
   daemon exposes the catalog/install RPCs; otherwise mark it with the reason.

Note for later (don't build): relay pairing will change SavedHosts identity from URL to
`serverId` + key (`docs/research/11` §R18); keep your changes compatible (key by whatever
SavedHosts uses today through its API, not by raw URL strings in new code).

Live checks read-only; never remove the real saved host or touch other agents. Done = PaseoCore
tests green (if touched), `swiftc -parse` on every touched UI/App file, `Tools/api-audit` no new
real findings. No background tasks or subagents; don't end your turn while waiting. Commit
"M16: multi-host", don't push. Final message: what changed, wire citations, gaps, unsure-compile spots.
