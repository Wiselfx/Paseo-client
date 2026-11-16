# H5: image links that always show the image (or say why not)

Branch `h5-images`, from `foundation`. Read `_H-common.md` first.

User: **"Some image links don't work and don't show images."** No example URLs were given, so
your first job is to find *which* links fail and *why*, across the realistic population of image
links an agent writes.

**Owns:**
- `Conversation/Prose/Rich/ClaudeRichBlocks.swift` (`RichRemoteImage` and its viewer/share only)
- `Conversation/Prose/Rich/ProseMarkdownImage.swift`
- New file(s) under `Conversation/Prose/Rich/` for a shared remote image loader
- `Conversation/Prose/ClaudeMediaView.swift` (the full-screen viewer's remote path only)
- PaseoCore `Rich/RichContentDetector.swift` (image detection only) + new test files

## 1. Find the failing classes (required before code)

Build a corpus of ≥ 25 real-world image URL shapes and run each through the whole path:
detection (`RichContentDetector.isRemoteImageURL` / markdown `![]()` parsing / bare-link and
`[text](url)` handling) → the view that renders it → the fetch → the decode. At least:

- plain `https://…/a.png`, `.JPG` uppercase, with `?w=800&fm=webp`, with `#frag`;
- extensionless image URLs: Unsplash `images.unsplash.com/photo-…?w=…`, GitHub
  `github.com/user-attachments/assets/<uuid>`, `raw.githubusercontent.com`, `i.imgur.com`,
  `placehold.co/600x400`, `picsum.photos/…`, Google/Gravatar avatars;
- Wikimedia `upload.wikimedia.org/…` (**rejects requests without a descriptive User-Agent with
  403**), sites that check `Referer`;
- `http://` (ATS is open in `App/project.yml`, confirm), URLs with spaces/unicode/`(`/`)` that
  `URL(string:)` rejects or that markdown splits;
- formats: PNG, JPEG, GIF (animated), WebP, HEIC, **SVG** (`UIImage` can't decode it), AVIF;
- `data:image/png;base64,…`;
- markdown `![alt](url "title")`, `![alt](<url with spaces>)`, a bare image URL on its own line,
  an image URL inside a sentence, `[click](https://…/a.png)` (a *link* to an image).

For each: does it render today? If not, the exact reason (`file:line`). Put the table in your
final message. Use the live network from this box to check status codes/headers
(`curl -sI -A …`), not guesses.

**Lead's suspects (confirm or reject each):**
- `RichRemoteImage` uses `AsyncImage` (`ClaudeRichBlocks.swift:518`): default `URLSession`
  request with no `User-Agent` app identity, no shared cache (every scroll back re-downloads and
  re-flashes the placeholder), and in a `LazyVStack` a row scrolled away mid-load cancels the
  task and `AsyncImage` lands in `.failure` → the broken card stays.
- SVG and AVIF can't be decoded by `UIImage`.
- Extensionless image URLs are never detected as images (`hasImageExtension`,
  `RichContentDetector.swift:466`) — decide whether bare extensionless links should become images
  (only via a content-type check that costs nothing per frame and is cached), or stay link
  previews. Markdown `![]()` should always attempt an image regardless of extension.
- `ActivityView(items: [URL(string: urlString) as Any])` (`:556`) shares `Optional.none` when the
  URL doesn't parse.

## 2. Build one remote image path

- **One shared loader** (`RemoteImageLoader`, an actor or a `Sendable` service): `URLSession` with
  a sized `URLCache` (memory + disk), a proper `User-Agent` (`Paseo/<version> (iOS)` style — no
  user data), redirects followed, a timeout, de-duplicated in-flight requests per URL, and an
  in-memory decoded-image cache (`NSCache`) keyed by URL + target pixel width.
- **Decode off the main actor with downsampling** (ImageIO `CGImageSourceCreateThumbnailAtIndex`
  at the transcript width × display scale) so a 4000 px photo never decodes full size on main.
  Animated GIF: first frame is fine for now (say so); don't decode all frames.
- **SVG:** route to the existing SVG snapshot renderer (`RichWebContent.swift`, the shared
  offscreen `WKWebView`) instead of failing; respect its size rules.
- **The row survives recycling:** a row that disappears mid-load doesn't turn into a failure; when
  it reappears it gets the cached image instantly (no placeholder flash).
- **Layout stability:** reserve the image's box before it loads when the aspect ratio is known
  (cache it with the image; for unknown sizes use the existing placeholder height and animate the
  single change with a `Motion` token). Images above the viewport must not shift the reader
  (the transcript has a history anchor — don't break it).
- **Failure is honest and useful:** the broken card says what happened in one line where it can
  (e.g. "Couldn't load image" + host), offers Retry, and keeps "Open link" so the user can still
  get to it in Safari. Use existing copy where it exists.
- Viewer + share use the same loaded image (share the image, not just the URL; fall back to the
  URL only when the image isn't loaded).

## Mission-critical constraints

- Nothing per scroll frame: no fetch/decode/state write triggered by scrolling except the row's
  own appear/disappear.
- All network + decode off main; one main-actor hop to publish the result.
- Memory: caches are bounded; a long transcript of images doesn't grow memory without limit.

## Acceptance

- The corpus table (before / after, with reasons).
- PaseoCore tests for detection changes (new test file; don't edit existing tests).
- Walk: a reply with 6 images; scroll past while loading; scroll back (instant, no flash);
  airplane mode → failure card → Retry after reconnect.
