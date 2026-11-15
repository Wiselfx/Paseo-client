# T2: ship the open fonts DSH ships, as the default faces

Read `AGENTS.md`, then `docs/tickets/_P-common.md` (no invention, never push, one commit per part), then this file.

## Why
The DSH Claude-style package ships only open-licence faces by default and treats Anthropic's faces as an optional local extra
(`/home/paseo/dev/dsh-claude-style-reference/README.en.md` "Fonts"; files in `packages/assets/src/fonts/`): Inter (sans), Noto Serif (serif),
JetBrains Mono with an italic (mono), plus a tiny pixel font for its mascot, all SIL OFL (`OFL.txt` there). Our app prefers Anthropic's single-weight
faces and falls back to system fonts, which is the cause of our weight and italic trouble (`DesignSystem/ProseFaceTable.swift` header). We ship the
open set instead so sans, serif and mono each have real weights and real italics.

## Owns
`Packages/PaseoUI/Sources/PaseoUI/DesignSystem/Typography.swift`, `ClaudeFontResources.swift`, `ProseFaceTable.swift`, and
`Packages/PaseoUI/Sources/PaseoUI/Resources/` (new font files and licence text). Do NOT delete, move or edit the existing Anthropic font files
(`Anthropic*.ttf`): the owner decided to keep them for now; leave their registration as is.

## Steps
1. **Sans = Inter.** Add the Inter variable TTF and its italic (`InterVariable.ttf`, `InterVariable-Italic.ttf`) from the official release
   (https://github.com/rsms/inter/releases, SIL OFL). DSH only carries a `.woff2`, which iOS cannot load. Verify the downloaded file is a TTF.
2. **Mono = JetBrains Mono.** Copy `JetBrainsMonoVariable.ttf` and `JetBrainsMonoItalicVariable.ttf` from DSH's `packages/assets/src/fonts/`.
3. **Serif = Newsreader**, which we already bundle with real weights and a real italic (`Newsreader.ttf`, `Newsreader-Italic.ttf`, OFL). DSH uses Noto
   Serif Variable, but it ships no italic file, so keep Newsreader for serif; do not add Noto Serif. Say so in your final message.
4. **Licences.** Put the SIL OFL text for the added families under `Resources/` next to the other licence files and mention them in the same place
   the other third-party notices live (find where `HighlightJS-LICENSE.txt` is referenced).
5. **Make the open faces the default.** In `ClaudeFontResources`: register the new files, add PostScript names read from the files themselves
   (`fc-scan` or fonttools if present; never guess). In `Typography`: sans resolves to Inter, mono to JetBrains Mono, serif to Newsreader, with the system
   font as the only fallback. The Anthropic faces are no longer chosen (leave the files and constants in place, unused).
6. **Weights and italics.** Variable fonts and SwiftUI's `.weight(_:)` do not always agree: follow the pattern in `ProseFaceTable.swift` (ask for a real
   face by name) so semibold/bold/italic map to real faces or named instances for Inter and JetBrains Mono as they do for Newsreader. Extend
   `ProseFaceTable` for sans/mono only as far as the app uses weights and italics today (grep `.paseo(` with `weight:` and `.italic`).
7. Keep sizes and roles unchanged (`TextRole` table). No layout change.

## Done
`swiftc -parse` on every edited Swift file; list every font file added with its size and licence, and the PostScript names you resolved.
You cannot compile or render: say what must be eyeballed on the simulator (weights, italics, line heights, code blocks).
Commits: `T2.1 add open fonts`, `T2.2 open fonts as default`.
