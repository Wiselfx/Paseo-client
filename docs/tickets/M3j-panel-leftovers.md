# M3j: panel leftovers (files, git, terminal, scripts)

Branch `m3j-panel-leftovers`. Rules as before (top of `docs/tickets/M3-workspace-panel.md`;
backend per `PHASE2-CONVENTIONS.md`: sandbox only, scrubbed fixtures, tests). Update the Files /
Git & changes / Terminals & scripts rows in `docs/PARITY.md` in the same commit. You may edit
`Workspace/*.swift`, new files, new PaseoProtocol/PaseoStore files + minimal wideners. Not
`Conversation/*`, `Sidebar/*`, `Settings/*`, `App/*`.

1. **Save to Files** (the iOS form of Download): file row menu + viewer → `fileExporter` with the
   bytes (reuse M3h's read path; the "download through daemon token" route only if upstream's
   HTTP download endpoint is reachable from the client, else say so). Progress + "Saved" / error.
   **Reveal in Files page** from the viewer (navigates the Files page to the parent, highlights row).
2. **Script URLs**: where the store/protocol exposes more than `preferredURL` (reverse proxy /
   memorable / direct), a "Choose URL" menu on the script row; Copy URL per choice.
3. **Paste a file into the terminal**: terminal key bar gains an attach button → Photos/Files →
   upload via T14 (`file.upload`, 50 MB cap) and type the resulting remote path into the terminal
   (quoted). Progress in the key bar; errors as a toast.
4. **Forge setup callout**: on the Changes/PR section, when the daemon reports `gh` missing or
   unauthenticated (authState from forge search / PR status), a calm callout with the exact
   commands to run on the host (copy buttons). No remote execution.
5. **Side-by-side diff** toggle in Diff options, shown only when the horizontal size class is
   regular (iPad / landscape Plus); pairs removed/added lines per hunk.

Full PaseoCore rebuild+tests if touched; swiftc -parse every touched UI file. Commit "M3j: panel
leftovers", don't push. Final message: what changed, store gaps, unsure-compile spots.
