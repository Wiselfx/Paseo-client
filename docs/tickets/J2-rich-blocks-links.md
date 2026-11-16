# J2 — Image paragraphs, file-link lines, bare URLs, numbers that look like files

Read `_J-common.md` first. Branch: `j2-rich`. Commit messages start with `J2:`.

All detection logic goes in **PaseoCore** (pure, Linux-tested, new test files); PaseoUI only
calls it. Detection is memoized per unit like `RichContentCache` — never per render.

## 1. Several images in one paragraph render as "▧ one ▧ two ▧ three ▧ remote"

**Symptom:** the agent wrote, on one line,
`![one](/abs/media/one.png) ![two](/abs/media/two.png) ![three](/abs/media/three.png) ![remote](https://…/x.png)`.
The app showed four blue "▧ alt" text links instead of a gallery.

**Root cause:** `ClaudeRichSplice.swift` only groups units that hold **one** image each
(`soleRemote`/`soleLocal`, lines ~157–180); `ClaudeMarkdownView.swift:214` only renders a paragraph
as an image when it has exactly one inline child that is an image. Anything else falls through to
the text fallback `"▧ " + alt` (`ClaudeMarkdownView.swift:656`).

**Build:**
- New PaseoCore helper (e.g. `RichImageGrouping.imagesOnly(unit: String) -> [RichImage]?`):
  returns the images when the unit's text, after trimming, consists **only** of markdown images
  `![alt](src)` (optionally with a title) separated by whitespace/line breaks; local sources
  (absolute paths, `~/`, `./`, relative paths with an image extension) → `.local(path:)`, `http(s)`
  → `.remote(url:)`; anything else (text, links, a non-image) → nil.
- In `richPieces`, before the single-image logic: if `imagesOnly` returns ≥ 2 images, emit one
  gallery block for the unit (`RichImageGrouping.group(images:range:)`) — the same block a run of
  single images produces; exactly 1 → the existing single-image block. Galleries may mix local and
  remote images (the gallery card already handles both; confirm by reading `RichGalleryCard.swift`
  and say so).
- Tests: images-only lines (1, 2, 4, mixed local/remote, with line breaks), and negatives (text
  before/after, a link among them, an empty alt, a code span).

## 2. Lines that are only links to files render as one blue sentence

**Symptom:** four lines, each `[clip.mp4](/abs/media/clip.mp4)` /
`[tone.m4a](…)` / `[doc.pdf](…)` / `[stats.py](…)`, rendered as one wrapped line of blue
underlined names. No video player, audio row or file cards. Tapping them likely does nothing:
the destination is a bare path, not a URL the app opens.

**Root cause:** markdown joins soft-broken lines into one paragraph; `RichStandaloneFile.path`
(`RichStandaloneFile.swift:17`) and `RichStandaloneMedia.match` only accept a unit that is exactly
**one bare path**. Authored links `[name](path)` are never considered.

**Build:**
- New PaseoCore helper (e.g. `RichStandaloneFile.linkLines(unit: String) -> [String]?`): when every
  non-blank line of the unit is either a bare local path or a single authored link whose
  destination is a local path (absolute, `~/`, `./`, `../`, or relative with an extension; not
  `http(s)`, not `#anchor`, not `mailto:`), return the paths in order; else nil. One line counts
  too (a single `[name](path)` line becomes a card like a bare path does).
- In `richPieces`: for such a unit, emit one piece per path in order — playable media →
  `.localMedia` block (same kind rules as `RichStandaloneMedia`), image extensions →
  `.localImage` block, anything else → `.file(path:utf16Length:)`. The `utf16Length` of the pieces
  must sum to the unit's length (give the whole length to the first piece and 0 to the rest, or
  split by lines — read how `utf16Length` is used before choosing, and say which).
- Inline authored links to local paths inside sentences: in `MarkdownDocumentModel`'s inline
  conversion, a `Markdown.Link` whose destination is a local path is rewritten to the
  `paseo-file://` URL `FilePathLinks.url(forPath:)` makes, so a tap opens the file viewer like a
  linkified bare path does. (Read `FilePathLinks.swift:39–53` and
  `ChatController.fileLinkAction` first; reuse, don't duplicate.)
- Tests for `linkLines` (bare paths, authored links, mixed, a URL among them → nil, prose → nil).

## 3. Bare URLs are plain text

**Symptom:** `- https://github.com/swiftlang/swift/pull/94239` in a list rendered as black,
non-tappable text. Same for `https://www.swift.org/blog/`.

**Root cause:** swift-markdown does not autolink bare URLs (no GFM autolink extension), and
`MarkdownInline.convert` (`MarkdownDocumentModel.swift`, `case let n as Markdown.Text`) keeps them
as `.text`. (Cards are deliberately vetoed inside list items — `RichContentDetector.swift` §1.1,
upstream parity — so a link is what the reader should get there.)

**Build:**
- New PaseoCore `BareURLScanner.ranges(in text: String) -> [Range<String.Index>]`: `http://` and
  `https://` URLs, stopping at whitespace and `<>"`; trailing `.,;:!?` and an unbalanced trailing
  `)` / `]` are not part of the URL. Pure; tests (trailing punctuation, parentheses in Wikipedia
  URLs, query strings, two URLs in one text, none).
- In `MarkdownInline.convert`, a `.text` node that contains URLs becomes `.text` + `.link(destination:
  url, children: [.text(url)])` pieces. Text already inside a link stays as is. This runs once per
  parse (the document cache), so it is not per render.
- Do **not** autolink in the raw source before detection (that would turn standalone URL lines into
  authored links and kill link cards / YouTube players — see the detector's purity exclusions).

## 4. Inline YouTube player splits its list item

**Symptom:** in a bulleted list, the item `- https://www.youtube.com/watch?v=…` rendered as an
empty bullet with the video card *below* it, outside the list.

**Root cause:** the detector emits `.youTubeInline` for a URL inside a list unit
(`RichContentDetector.swift:1475–1486`), and `spliceUnit` (`ClaudeRichSplice.swift:105–121`) cuts
the unit's markdown at the block's range, so the list item's text is removed and the list is
broken in two.

**Build:** in `richPieces`, when the unit is a list (first non-blank line starts with a list
marker: `-`, `*`, `+`, or `\d+[.)]`, after optional indentation), do not splice: emit the whole
unit as `.markdown(linked)` (the URL now renders as a link through item 3), then the unit's
`.youTubeInline` blocks as players **after** it, in order. Put the "is this unit a list" test in
PaseoCore with tests. Other block kinds in list units keep today's behaviour.

## 5. Table numbers render as blue links

**Symptom:** a table's `score` column (`98.5`, `87.2`, …) rendered as blue underlined links.

**Root cause:** `FilePathLinks.swift:18–19`: `[A-Za-z0-9_.-]+\.[A-Za-z0-9]{1,8}` accepts `98.5` as
name `98` + extension `5`.

**Build:** the extension must start with a letter: `\.[A-Za-z][A-Za-z0-9]{0,7}`. Also reject a
match whose whole text is a version/number (`1.2.3`, `v2.0`) — the letter rule already covers
these; confirm in the report. No other change to the pattern. If there is no test for this
pattern, add the same pattern + cases to a PaseoCore test file only if the pattern can be shared
from PaseoCore without moving `FilePathLinks` (otherwise list the cases you checked by hand with
`NSRegularExpression` in a scratch Swift script and paste the output).

## Final message

As in `_H-common.md`. Include the PaseoCore test counts.
