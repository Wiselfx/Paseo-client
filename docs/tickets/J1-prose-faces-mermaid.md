# J1 — Bold/italic/heading faces and Mermaid rendering

Read `_J-common.md` first. Branch: `j1-prose`. Commit messages start with `J1:`.

## 1. Bold, italic and headings render as plain regular text

**Symptom (device):** `**bold**` and `*italic*` in assistant prose look identical to body text.
Headings (`#`, `##`) also look regular weight.

**Root cause (lead):** the prose serif is `AnthropicSerifWebVariable-TextRegular`
(`DesignSystem/ClaudeFontResources.swift:10`), registered from `Resources/AnthropicSerifWebText.ttf`.
That file is a **single static Regular face** (`fc-scan`: one face, `var=False`). There is no bold
and no italic face, so `Font.custom(name…).weight(.semibold)` (`Typography.swift:323`,
`ClaudeMarkdownView.swift:665`, heading fonts at `ClaudeMarkdownView.swift:36–38`) and
`.italic()` (`ClaudeMarkdownView.swift:666`) are no-ops. The same is true of the sans
(`AnthropicSansWebText.ttf`, one Regular face).

The bundled Newsreader files do have real faces (registered in `ClaudeFontResources`):
`Newsreader.ttf` → `NewsreaderRoman-Medium`, `NewsreaderRoman-SemiBold`, `NewsreaderRoman-Bold`;
`Newsreader-Italic.ttf` → `Newsreader16pt-Italic`, `NewsreaderItalic-Medium`,
`NewsreaderItalic-SemiBold`, `NewsreaderItalic-Bold`.

**Build:**
- In `ProseFonts` (`Typography.swift`), resolve a *real* face for the serif when the requested
  weight is above regular or italic is requested: weight ≥ `.semibold` → `NewsreaderRoman-SemiBold`
  (`.bold`/`.heavy`/`.black` → `NewsreaderRoman-Bold`), `.medium` → `NewsreaderRoman-Medium`;
  italic → the matching `NewsreaderItalic-*` / `Newsreader16pt-Italic`. Add an `italic: Bool = false`
  parameter to `ProseFonts.serif(size:relativeTo:weight:)` (internal API; keep existing call sites
  compiling). Regular, non-italic keeps the current face exactly. Use
  `ClaudeFontResources.isAvailable(_:)` once per face (cache the answer) and fall back to the
  current behaviour if a face is missing. Keep the per-key font cache.
- In `ClaudeMarkdownView.swift`, `attributed(...)` and `inlineText(...)`: stop calling
  `.weight(.semibold)` / `.italic()` on the theme font; ask `ProseFonts` for the face instead
  (the body size is `theme` dependent: add the needed size/role to the theme, or a theme helper
  `func face(bold: Bool, italic: Bool, base: Font)` — keep it O(1) and cached). Strong is 600
  (semibold) as the existing comment says. Inline code is untouched.
- Headings: the theme's heading fonts (`ClaudeMarkdownView.swift:36–38`) get the real semibold/bold
  face through the same helper.
- Sans weights: **do not change** them in this ticket. List under "Found, not fixed" every place
  that asks the Anthropic sans for a non-regular weight (count is enough, plus 3 examples).

**Verify:** a small pure helper that maps (weight, italic) → PostScript name lives in a new file
and is the single source of truth; list its table in your report. `swiftc -parse` the touched files.

## 2. Mermaid diagrams always show "Couldn't render diagram"

**Symptom:** both diagrams in the showcase chat show the red "Couldn't render diagram" title, the
source, and then a second mono line "Couldn't render diagram".

**Root cause (lead):** `RichWebContent.swift:163–166` looks the runtime up with
`Bundle.module.url(forResource: "mermaid.min", withExtension: "js", subdirectory: "mermaid")`.
`PaseoUI/Package.swift:27` uses `resources: [.process("Resources")]`, which flattens folders in the
built bundle, so the lookup returns nil → `runtimeScript()` nil → `.unavailable` →
`ClaudeRichBlocks.swift:1895–1896` sets `errorMessage = "Couldn't render diagram"`.

**Build:**
- `runtimeScript()`: look up with `subdirectory: "mermaid"` and fall back to no subdirectory (same
  pattern as `ClaudeCrabView.swift:129–131`). Keep the detached read.
- If the runtime is still missing, log once with `os.Logger` (subsystem as used elsewhere in
  PaseoUI, category `mermaid`) so the next device run tells us.
- Error stage (`ClaudeRichBlocks.swift:1818–1830`): never print the same sentence twice. For
  `.unavailable` show the title + source only (no footer line); for `.error(message:)` keep the
  renderer's message as the footer. Do not invent new copy.
- Check the rest of the mermaid path for anything else that would return `.unavailable` on a
  healthy run (e.g. `callAsyncJavaScript` returning numbers as `Int` vs `Double` — `NSNumber`
  cast is fine; the `width`/`height` > 0 guard; snapshot nil). Report what you checked.

## Final message

As in `_H-common.md`, plus: the (weight, italic) → face table, and every Apple API you were not
100 % sure of.
