# M4f: appearance themes and fonts

Branch `m4f-appearance`. Rules: top of `docs/tickets/M3-workspace-panel.md`. Update Settings rows in
`docs/PARITY.md` in the same commit. You may edit `Settings/*`, `Chat/PaseoSettingsView.swift`
(rows only), `ClaudeAppearance.swift`, the palette/typography files (`ClaudePalette`,
`ClaudeTypography` or wherever they live), `App/Sources/RootView.swift`, new files.
Reference: `docs/research/01-app-features.md` appearance rows; DSH theme tokens in
`docs/research/08-dsh-live*` (the Claude theme is the default and must stay pixel-identical).

1. **Themes**: keep Light / Dark / System with the Claude palette as is; add **Pure black** (OLED
   dark variant: background #000, surfaces stepped up slightly) only if it can be expressed as a
   palette swap without touching views. Live preview tiles like the current appearance picker.
2. **Fonts**: content text size (S / M / L / XL relative steps on top of Dynamic Type) and code font
   size for code blocks, diffs and the terminal; applied live through the existing typography
   environment. No new font files.

swiftc -parse every touched file. Commit "M4f: appearance", don't push. Final message: what
changed, unsure-compile spots.
