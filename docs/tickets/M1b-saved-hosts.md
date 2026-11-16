# M1b: saved hosts, SSL/advanced URI, switch host

Branch `m1b-hosts`. UI rules: top of `docs/tickets/M3-workspace-panel.md`. Update the Connection &
hosts rows in `docs/PARITY.md` in the same commit. You may edit `App/Sources/*`,
`Packages/PaseoUI/Sources/PaseoUI/ConnectView.swift`, `Sidebar/PaseoSidebar.swift` footer only,
`Chat/PaseoSettingsView.swift` (one row), new files. PaseoCore only if a URL/TLS option is missing
in `DaemonConnection` (then minimal, tested). Reference: `docs/research/01-app-features.md:355-367`,
upstream `packages/app/src/` host/connection screens (find and cite).

1. **Direct form**: host, port, password, plus an **Use TLS (wss)** switch and an **Advanced**
   disclosure with a full connection URI field (`ws://` / `wss://host:port/ws`) that, when filled,
   overrides host/port/TLS; validate inline.
2. **Saved hosts**: every successful connection is saved (label = host name or user-editable
   label, URL, TLS, last connected); passwords in the Keychain per host (never in UserDefaults,
   never logged). The connect screen lists saved hosts first (tap to connect, swipe to forget,
   rename), then "Add host".
3. **Switch host**: sidebar footer host name → menu of saved hosts + "Add host…"; switching closes
   the current session cleanly and opens the other (one active host at a time; no "All hosts"
   mode). Settings → Hosts row lists them with forget/rename.
4. Startup: auto-connect to the last host; on failure show the connect screen with that host
   preselected and the error inline (calm, with Retry).

Never commit real hostnames, IPs or passwords (public repo); placeholders only. swiftc -parse every
touched file. Commit "M1b: saved hosts", don't push. Final message: what changed, gaps, unsure-compile spots.
