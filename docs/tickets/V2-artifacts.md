# V2: html and svg artifacts from ordinary fences, and mermaid robustness

Read `AGENTS.md`, `docs/tickets/_V-common.md`, then this file. Items in order, one commit each.

## Owner decision
Models should not have to learn a special fence. Today an HTML page needs a ```visualize fence (a convention from the DSH style plugin) and a raw `<svg>` must be a standalone block; otherwise the app shows source.
Change it so that what models already produce renders as an artifact:
- a ```html fence (also `htm`) whose body is an HTML document or fragment,
- a ```svg fence, and a raw `<svg ...>...</svg>` block (existing detector rule),
- a ```xml fence only when its body is an `<svg` document,
each draws as a rendered artifact card with a **View source** button (and Copy source), in the same reserved-size card family. ```visualize keeps working as an alias.
Keep every existing safety rule: offline only (`OfflineContentRules`, the always-injected CSP, the content rule list), sandboxed web view, no network, no script that can reach the app, size cap
(`RichContentDetector.rawSVGMaxLength` and the artifact limits), closed fences only while streaming (an open ```html fence stays a code block until it closes, so a half-written page never flashes).
A fence the user wants as code, not a page: keep an easy way: a card always has View source, and a fence with a `title` or `source` word in its info string (for example ```html source) stays a plain code block.

## Items
1. **Detector (Core, Linux-testable).** In `Packages/PaseoCore/Sources/PaseoStore/Rich/RichContentDetector.swift` add the cases above (reuse `.visualize`/`.rawSVG` block kinds or add an `.htmlArtifact`
   kind if cleaner; keep `RichContentBlock` exhaustive switches compiling everywhere: grep the UI). Update the old tests that asserted these fences are NOT detected and list them; add new tests in new files
   (closed vs streaming fence, `html source`, svg fence, raw svg, xml-with-svg, xml-without-svg, empty body, oversize).
2. **Cards.** The UI that draws a visualize or raw SVG card (`Conversation/Prose/Rich/ClaudeRichBlocks.swift` web/svg cards, `RichWebContent.swift`, `ArtifactPage.swift`, `SandboxedHTMLView.swift`) must render the page,
   not its source. The owner's screenshots show the "Visualization" card drawing the HTML as TEXT (and clipping the long lines at the right edge with no scrolling) and raw SVG not drawn at all:
   find out why (is the web view never created? is a policy forcing the source view? did the model's text arrive HTML-escaped (`&lt;svg`, see below)?) and fix. Rules for the card: reserved height from the
   content's own size where it can be known (SVG: viewBox ratio; HTML: measured once after load, then fixed, never re-flowing on later frames), maximum height with a clear "Open" affordance to the artifact page for tall
   pages, the web view pooled (`WebViewSlotPool`/shared host, at most 2 live) and replaced by a snapshot when scrolled away, no flash on a second visit (snapshot cache), dark and light correct, Reduce Motion respected.
   View source shows the code in the code-block style with horizontal scrolling or wrapping (no silent clipping).
3. **HTML entities.** The test model (and some real models/providers) emit `&gt;`, `&lt;`, `&quot;`, `&amp;` inside fences and inline SVG: look at the evidence
   (`paseo --host localhost:6768 logs 9972fe65` shows `-&gt;`). Decide with evidence where the escaping comes from (the model text itself; our markdown parser; our store). If it is in the text we receive, add one narrow, well-tested
   decode step for the **artifact and diagram bodies only** (mermaid, svg, html artifact sources): decode the five basic entities when the body contains no raw `<`/`>` but contains entity forms, never for ordinary prose
   or code blocks. If it is our own double-escaping, fix it at the source.
4. **Mermaid.** Both diagrams in the test conversation fail with "A JavaScript exception occurred". After item 3 they must render. Also make the error useful: show the renderer's message (trimmed, one line) plus
   View source; never the bare "A JavaScript exception occurred". Keep the one-shared-renderer and snapshot-cache design.
5. **Docs.** Update the parity/plan docs where the visualize fence is described (`docs/PARITY.md`, `docs/research/14-rich-ui-plan-full.md` C8/§4.8 as an addendum line).
6. **Smoothness pass** over what you touched, listed in the final message.

## Owns
`Packages/PaseoCore/Sources/PaseoStore/Rich/RichContentDetector.swift` and new Rich Core files and tests; `Conversation/Prose/Rich/ClaudeRichBlocks.swift` ONLY the web/svg/visualize/mermaid cards
(another worker edits the image/video/audio cards in the same file: keep your edits inside those cards and run `git diff` to confirm no other hunk), `RichWebContent.swift`, `ArtifactPage.swift`,
`SandboxedHTMLView.swift`, `OfflineContentRules.swift`, mermaid files, `ClaudeRichSplice.swift` only for the new block kinds.
Commits: `V2.1 detector`, `V2.2 artifact cards`, `V2.3 entities`, `V2.4 mermaid`, `V2.5 docs`, `V2.6 smoothness`.
