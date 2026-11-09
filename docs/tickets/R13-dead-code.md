# R13: remove dead ClaudeUI demo code

Branch `r13-dead-code`. PaseoUI started as a copy of the ClaudeUI demo; many files are no longer
reachable from the app (e.g. candidates: `ClaudeCodeView`, `ClaudeCodeDraftView`,
`ClaudeCodeConnectorsView`, `ClaudeCodeConfigurationSheets`, `ClaudeCodeContextSheet`,
`ClaudeRoutinesView`, `ClaudeProjectsView`, `ClaudeProjectEditorView`, `CodeState`,
`CodeDraftState`, `CodeConnectorState`, `ConnectorCatalogState`, `ProjectState`, `MediaState`, …:
**verify each, don't trust this list**).

Method: build the reachability graph from the roots `App/Sources/*` and every type/func/extension
the app actually instantiates (`PaseoShellView`, `ConnectView`, `ClaudeChatView`, sidebar, panel,
settings, mascot, etc.). A file is dead only if no symbol it declares is referenced from a live
file (grep each declared type/func/static name across the package and App; watch for
extensions, `@Environment` keys, `PreferenceKey`s, font registration, asset names in strings,
`#Preview`s don't count as uses). Iterate until fixed point. Delete dead files whole; inside live
files, remove only clearly unused private/internal members you can prove unused. Keep fonts,
assets and anything referenced by name in strings.

Prove it: list every deleted file with the evidence (declared symbols → 0 live references),
`swiftc -parse` the package, and grep that no deleted symbol name remains referenced anywhere.
Also update `ARCHITECTURE.md`/`docs/PARITY.md` source paths that pointed at deleted files. Do not
touch PaseoCore. Other workers are editing `Settings/*`, `Sidebar/*`, `Conversation/*` and
`Chat/ClaudeNewAgentSheet.swift`, `Chat/PaseoSettingsView.swift` right now: don't edit those files
(deleting an entirely dead file elsewhere is fine). Commit "R13: remove dead demo code", don't
push. Final message: deleted files with line counts, kept-on-doubt list, total lines removed.
