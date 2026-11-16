# Shared rules for the J-round (device feedback 4, 2026-11-12)

The user installed IPA `cacde34` (G-round complete) on an iPhone, opened a showcase chat that
contains every kind of rich content, and pasted screenshots. This round fixes what they saw. The
lead already traced every root cause; each ticket gives it with `file:line`. Your job is to
**implement the fix as specified, cleanly**, verify it and report. Do not redesign.

Read `AGENTS.md` (UI rules R-1…R-6) and `docs/tickets/_H-common.md` first. Everything in
`_H-common.md` applies (mission-critical rules, hard rules, proof, final-message format) **except**
its "Report what you see — and fix it" section: in this round you **only** fix your ticket's items.
Anything else you notice goes under "Found, not fixed" with `file:line` and the exact fix.

## Mission-critical (short form, from `G-rich-ui.md` §0)

1. Nothing per frame, keystroke or stream token beyond O(1). Parsing/detection happens once per
   unit and is memoized (`RichContentCache`, `MarkdownDocumentCache`); never in `body` per render.
2. Nothing jumps. Seed caches in the first body pass, never in `.task`. Hidden chrome keeps its
   space.
3. Main actor free: no file reads, decodes or regexes over whole transcripts on main per render.
4. Tokens only (Palette, `.paseo()` / `ProseFonts`, Space, Radius, `Motion.resolved`, Haptics,
   Metrics). `Tools/style-lint/style-lint.sh` clean on your files.
5. Swift 6 strict concurrency, no warnings. No force unwraps, no `fatalError`.

## Workers

Three DeepSeek workers run in parallel on separate branches from `foundation`. Owns lists do not
overlap; do not edit a file you don't own.

| Ticket | Owns |
|---|---|
| J1 prose faces + Mermaid | `DesignSystem/Typography.swift` (ProseFonts only), `Conversation/Prose/ClaudeMarkdownView.swift` (inline runs only: `inlineText`, `attributed`), `Conversation/Prose/Rich/RichWebContent.swift`, `Conversation/Prose/Rich/ClaudeRichBlocks.swift` (the Mermaid card only), new files |
| J2 rich blocks + links | `Conversation/Prose/Rich/ClaudeRichSplice.swift`, `Conversation/Prose/FilePathLinks.swift`, `Conversation/Prose/MarkdownDocumentModel.swift`, `PaseoCore/Sources/PaseoStore/Rich/RichStandaloneFile.swift`, `RichImageGrouping.swift`, new PaseoCore files + tests |
| J3 composer + back-to-end | `Conversation/Composer/ComposerAttachments.swift`, `Conversation/Screen/ChatScreen.swift`, `Conversation/Transcript/ChatTranscript.swift` (the back-to-end decision + button only), new files |

Paths under `Packages/PaseoUI/Sources/PaseoUI/` unless they start with `PaseoCore/`.

## Apple traps the lead's gate keeps catching (check before you report)

- Main-actor statics/helpers called from `Task.detached` need `nonisolated`.
- Nested types used at file scope must be qualified.
- `Font.custom(...).weight(_:)` / `.italic()` do **nothing** when the font file has no such face
  (that is J1's bug — do not rely on them for custom faces).
- `Bundle.module` with `resources: [.process("Resources")]` **flattens** subdirectories in the
  built bundle: look up by name without `subdirectory:` (fall back both ways, like
  `ClaudeCrabView.swift:129–131`).
- Mixed `switch` returns need explicit `return`; exhaustive switches on enums you extend.
- Never park on a continuation that is never resumed.
