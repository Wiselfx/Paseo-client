# M4g: welcome screen, help & support, chat settings

Branch `m4g-welcome-help`. Rules: top of `docs/tickets/M3-workspace-panel.md`. Update rows in
`docs/PARITY.md` (Connection & hosts, Settings, App-level) in the same commit, and re-check that
section's rows against the code (e.g. App diagnostic report vs M4e Diagnostics; fix proven stale
rows). You may edit `Settings/*`, the app's startup/root host-selection code, and new files.
Reference: doc 01 lines ~109, 272-275, 367 and upstream `components/welcome-screen.tsx`,
i18n `en.ts` (`onboarding.*`, `pairing.connectionMethods.*`, help menu) — reuse its wording.

1. **Welcome screen**: first run with no saved host (M1b's saved hosts) shows "Welcome to
   Paseo" with the connection-method tiles iOS can offer today (Direct connection → M1b's
   add-host form; omit Scan QR / Paste pairing link / Remote SSH, which need relay or SSH this
   client lacks) and a Settings entry. Settings → General gets
   **Show setup again**. (The desktop onboarding modal never opens on phones upstream: mark it
   n/a in PARITY.)
2. **Help & support**: a menu in Settings (or the sidebar footer, matching where the app keeps
   its footer actions) with upstream's items that make sense on iOS: Run diagnostics (M4e page),
   Report an issue / GitHub issue / Discord / What's new as links (upstream URLs), community links.
3. **Chat settings** page: Always expand reasoning, chat display mode (Full / Collapse tool calls
   / Collapse turns: reuse M7f's stored setting, don't fork it), chat outline toggle if M7i lands
   a turn rail (else omit).

swiftc -parse every touched file. Commit "M4g: welcome, help, chat settings", don't push. Final
message: what changed, gaps, unsure-compile spots.
