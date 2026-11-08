# Rich media in the Paseo iOS chat — behavioral spec

Scope: the fork-only rich-media work in `github.com/Wiselfx/paseo`, as checked out at
`/home/paseo/dev/paseo-reference` (fork tip = merge commit `a64626aa1`). This document
specifies **behavior** for a native iOS reimplementation. It is not code. Everything
about *how* the fork implements a rule is cited to `path:line` or to a fork commit sha
(from `gh api repos/getpaseo/paseo/compare/main...Wiselfx:paseo:main`).

Conventions:

- `path:line` citations are relative to the fork repo root.
- "At tip" means the fork tip checkout above.
- Fork commit shas are short forms from the compare API, e.g. `e83cedfc1`.
- The fork's media features live in the assistant/chat markdown pipeline
  (`packages/app/src/components/markdown/`) and only apply to surfaces that use it
  (assistant messages and file previews). Nothing here touches the daemon.

## 0. The pipeline at a glance

Rendering an assistant message runs two independent stages:

1. **Source pre-passes** (string edits before parsing), in `useMarkdownSource`
   (`packages/app/src/components/markdown/images.ts:48-63`):
   `hoistRawSvgToImages(text)` → `hoistBareRemoteImages(...)` → `linkifyLocalPaths(...)`
   → `prepareMarkdownSource(...)` (mdast). Each rewrites the raw text so that the raw
   content rides the stock image pipeline.
2. **Hosted-segment split** after markdown preparation
   (`packages/app/src/components/markdown/hosted-segments.ts:24-40`): fence kinds the app
   hosts outside the markdown library are cut out in order — **mermaid (native only) →
   YouTube → link cards → visualize** — and the remainder is handed to the library in
   document order. `renderer.tsx` renders the resulting segment list
   (`packages/app/src/components/markdown/renderer.tsx:139-192`).

The split stages never overlap by construction: each stage claims its blocks (code fences,
or pure-text paragraphs whose lines are bare URLs), and everything left goes to the next
stage. Library segments carry no special rendering.

Two renderer-level notes that apply to everything below:

- The **markdown library at fork tip is `react-native-enriched-markdown`** (the upstream
  engine). The old `markdown-it`-based "old engine" was replaced during the upstream
  merge; fork media was re-expressed as source pre-passes + hosted segments. Where a
  behavior below says "old engine", the work exists in git history but is not the path at
  tip.
- `isSoleBlockContent` in `media-links.ts:65-81` and the `imageFrame`/`imageSurface`/
  `imageState`/`imageErrorText` styles in `components/message.tsx:787-822` are **leftovers
  from the old engine and are unreferenced at tip** (see §6).

---

## 1. Content kinds

### 1.1 Link card (standalone bare links)

**What it is.** A favicon + domain + trimmed-URL card for a bare link sitting alone on its
line. Embedded links and authored `[text](url)` links never become cards.

**Detection (at tip)** — `splitLinkCards`,
`packages/app/src/components/markdown/link-card-segments.ts:20-64`:

- Quick reject: no `https?:` substring anywhere → whole input is markdown.
- mdast parse; every **paragraph with `position`** whose children are **all `text`
  nodes** is walked **line by line** (soft breaks do not split mdast paragraphs).
- A line becomes a card iff, after `trim()`:
  - it matches `^https?:\S+$` (`link-card-segments.ts:12`), and
  - it is **not** a remote image URL (§1.4, `isRemoteImageUrl`), and
  - it is **not** a YouTube URL/ID (`youtubeIdForUrl`, §1.2).
- Nesting: paragraphs inside `listItem` or `heading` (any depth) are never card
  candidates (`link-card-segments.ts:50-53`). Blockquotes are **not** excluded.
- Lines that don't qualify stay markdown (one segment, contiguously).

**Detection (old engine, still present in file but unused at tip)** —
`isSoleBlockContent` (`media-links.ts:65-81`): a link is a card iff its nearest
paragraph-like container (`paragraph` or the assistant-block `textgroup` wrapper) holds
only the link plus blank-text/`softbreak`/`hardbreak` siblings, **and** the ancestor chain
contains no `list_item` and no `heading*`. This fixed two placement bugs: the assistant
block pipeline tops out at `textgroup` so a naive `paragraph` lookup never matched
(`fd2ef8964`), and a trailing line break parses as a `softbreak` sibling that must count
as whitespace, or a standalone link never qualified (`1081b7638`); links in list items and
headings must stay links (`fd2ef8964`).

**Placement.** Standalone line only. A bare URL inside a sentence renders as a link;
an authored link `[t](u)` alone in a block stays a link (paragraph children include a
`link` node, failing the all-`text` test). Bare image URLs stay images (§1.4). Bare
YouTube URLs stay players (§1.2). Cards and images and players keep document order via
the hosted-segment table (`hosted-segments.ts:24-29`).

**Rendering** (`AssistantLinkCard`, `packages/app/src/components/markdown/link-card.tsx:13-65`):

- Card container: `borderWidth: 1`, `borderColor: theme.colors.border`, **borderRadius 12**,
  `padding: 12`, `gap: 10`, `backgroundColor: theme.colors.surface1`.
- Row: 10px gap, items centered.
- Favicon: 32×32, **borderRadius 8**, loaded from
  `https://www.google.com/s2/favicons?domain=<host>&sz=64` (`link-card.tsx:48`) where
  `<host>` is the scheme/userinfo/port-stripped host. On image error the favicon is
  dropped entirely (`iconGone`); there is no fallback glyph.
- Domain line: 13px, `fontWeight: "600"`, foreground, `numberOfLines={1}`, tail ellipsis.
- URL line: 12px, foregroundMuted, `numberOfLines={1}`, **middle** ellipsis. Text is
  `displayUrl(url)` (`media-links.ts:88-93`): scheme, userinfo, query string, fragment and
  trailing slashes are stripped; host + path remain (secrets in userinfo/query never
  display; loading always uses the full URL). `domainForUrl` (`media-links.ts:96-98`)
  strips scheme and port.
- Pressed state: `opacity: 0.85` (`link-card.tsx:22`).

**Interactions.** Tap anywhere on the card → `onPress(url)` → in `renderer.tsx` the card
is wired to `pressCardLink` → `pressLink({ url, sourceType: "text" })`
(`renderer.tsx:143,153-155`), i.e. the **same open path as any markdown link**:
non-file URLs open externally (or via the host's `onLinkPress`); no lightbox, no share.
Accessibility: role `button`, label `Open <domain>`; favicon has label `<domain> icon`.

**Bugs/edges addressed:**

- `55ca8ad98` — native classifiers ported from the media-cards plugin **without the
  plugin's gates**: the plugin capped at 5 cards, vetoed long prose, and replaced the
  whole message or nothing; native cards are pure per-token classifiers.
- `0e663411b` — card added for the old engine (`link` rule branch; bare remote image URLs
  rendered as previews there — later removed in `897ff3f0d`).
- `1081b7638` — line breaks accepted as whitespace in card placement (see above).
- `fd2ef8964` — placement matched to the real AST shape (`textgroup`, heading/list veto);
  also stopped cards inside list items and headings.
- `145caaca5` — card extraction reimplemented for the new renderer as
  `splitLinkCards`; excludes image URLs and YouTube URLs so those keep their own
  pipelines.
- `8cf72d785` — docs: card paths covered (`docs/agents/docs.md`).

Note: at tip, `isSoleBlockContent` (used only by the old engine's link rule) is unused;
`splitLinkCards` is the live detector.

### 1.2 YouTube (fence, standalone bare URL, and in-sentence prose player)

**What it is.** Three placements of the same embed:

1. The `youtube` code fence (fence body = a watch URL or bare 11-char video ID) → full-width player.
2. A bare YouTube URL **alone on its line**, or a paragraph that is **solely one authored
   link** to YouTube → full-width player.
3. A YouTube URL **anywhere else** — inside a sentence, or an authored link inside a
   larger block → small "prose" player at the exact source range.

**Detection** — `packages/app/src/components/markdown/fence/youtube/urls.ts:1-57`,
`packages/app/src/components/markdown/fence/youtube/segments.ts`:

- ID regex `YOUTUBE_ID_RE` (`urls.ts:1-2`): `https?://(sub.)?(youtube(-nocookie)?.com/(watch?…v=|shorts/|live/|embed/)|youtu.be/)<11 chars>` with a `(?![A-Za-z0-9_-])` tail guard —
  matches watch (any position of `v=`), `shorts/`, `live/`, `embed/`, `youtu.be/`, and
  `youtube-nocookie.com`. `m.youtube.com` etc. via the optional subdomain group.
- Bare ID: `^[A-Za-z0-9_-]{11}$` (`urls.ts:3`). `youtubeIdForUrl` (`urls.ts:10-14`) trims
  and returns the ID or null. **Streaming-safe**: a partial ID never matches.
- `findYouTubeUrls` (`urls.ts:31-45`) for in-prose detection: after the ID match, keeps
  consuming while the next char is URL-ish (`[^\s"'<>*]`), then strips trailing
  `.,;:!?)]}>"'` — so `?t=30` rides along, a sentence period or closing paren stays prose.
- Segment split (`splitYouTubeFences`, `segments.ts:99-126`):
  - `code` block with lang `youtube` (case-insensitive) → `youtube` segment with the raw
    fence value (which `YouTubeFence` re-validates as a URL or bare ID, `index.tsx:10-15`).
  - Paragraph that is exactly one authored link whose URL yields an ID → `youtube`
    segment spanning the paragraph (`segments.ts:36-43`).
  - Paragraph whose children are all `text`: each line is checked with
    `isStandaloneYouTubeLine` — trimmed line matches a URL or bare ID and the whole line
    is the URL (`^https?:\S+$` or bare ID, `segments.ts:12-16`) → `youtube` segment for
    that line; any other line is scanned with `findYouTubeUrls` → `youtube-inline` cuts.
  - Mixed paragraphs (links/images/code mixed with text): `link` children with a
    YouTube URL → `youtube-inline` cut spanning the link; `text` children scanned in
    place → `youtube-inline` cuts (`segments.ts:85-99`).
  - Quick reject: no `youtu.?be` substring anywhere → markdown.
- **Placement rules to carry over**: standalone ⇒ full player; sentence ⇒ prose player;
  sole-authored-link block ⇒ full player. Soft breaks never split a paragraph, hence the
  line-by-line walk for pure-text paragraphs.

**Rendering.**

Full player — `YouTubeInlinePlayer`
(`packages/app/src/components/markdown/fence/youtube/player.tsx`):

- Screen box: full width, **aspectRatio 4/3** (deliberately not 16:9 — `9072201eb`),
  **borderRadius 8**, `overflow: hidden`, `backgroundColor: theme.colors.surface2` while
  loading (`player.tsx:12-19`).
- Inner surface (`YouTubePlayerScreen`, `player.tsx:52-67`): WebView of
  `https://www.youtube-nocookie.com/embed/<id>?rel=0` (`urls.ts:51-53`),
  `javaScriptEnabled`, `allowsInlineMediaPlayback`, `allowsFullscreenVideo`,
  `scrollEnabled={false}`. Web counterpart (`player.web.tsx`) uses an `<iframe>` instead —
  react-native-webview is a stub on web — same URLs, `referrerPolicy="strict-origin-when-cross-origin"` (`player.web.tsx:73`, added by `486373d03`) plus
  `allow="accelerometer; autoplay; …" allowFullScreen`.
- Meta row under the screen: 12px muted `Play` icon + `youtube.com · <videoId>` text;
  tappable, opens `https://www.youtube.com/watch?v=<id>` externally
  (`openExternalUrl`, `player.tsx:28-49`). Accessibility: role `link`, label
  `Open YouTube video <id>`.

Prose player — `YouTubeMiniPlayer`
(`packages/app/src/components/markdown/fence/youtube/mini.tsx`):

- Frame: full width, **maxWidth 320**, **aspectRatio 16/9** (16:9, unlike the full player),
  **borderRadius 12** (like images and cards), `overflow: hidden`, surface2 bg
  (`mini.tsx:15-23`).
- Poster: `https://i.ytimg.com/vi/<id>/hqdefault.jpg` (`urls.ts:47-49`),
  `resizeMode="cover"`, `accessibilityIgnoresInvertColors` — hqdefault letterboxes 16:9
  inside 4:3, hence `cover`.
- Overlay: centered 34px circle, `rgba(0, 0, 0, 0.55)`, white 16px `Play` glyph; the
  overlay carries `pointerEvents="none"` so the poster receives the tap.
- Tap → swaps the poster for the real embed (`YouTubePlayerScreen`) in place; no network
  happens until tap (`mini.tsx:44-76`). Accessibility: role `button`, label
  `Play YouTube video <id>`. White glyph in both themes (sits on the dark scrim).
- No meta row in the prose player.

**Referrer handling (the saga, in order):**

1. `1681665e6` — the daemon web UI served the app with `Referrer-Policy: no-referrer`
   (`packages/server/src/server/web-ui.ts`) because hotlink-gated image hosts answer a
   Referer with a 307 to an HTML page, so chat images never decoded.
2. `486373d03` — YouTube answered the now referrer-less embed with **error 153**;
   the iframe got `referrerPolicy="strict-origin-when-cross-origin"` (a document-wide
   `no-referrer` cannot be overridden per-document, so this was a per-embed override).
3. `3a5e76431` — final fix: `no-referrer` scoped **to chat images only**, document keeps
   the browser default. Web image size probe: `image-size.web.ts` (a `window.Image` with
   `referrerPolicy = "no-referrer"`); renderer `<img>`: the fork's enriched-markdown patch
   adds `referrerPolicy="no-referrer"` to the library's `<img>`s
   (`patches/react-native-enriched-markdown+1.2.0-nightly-20261014-766fc0e67.patch:1434,1443,1483,1491`);
   the server header was **removed** (`Referrer-Policy` no longer set). Iframe keeps
   `strict-origin-when-cross-origin`. Native: `Image.getSize` is used as-is
   (`image-size.ts:1-8`).
4. If you reimplement on iOS: WKWebView gives no per-navigation referrer override, and an
   image request's referrer cannot be stripped via `URLRequest` public API. Decide for
   yourself whether hotlink-gated hosts matter (they do for Apple News-ish hosts, and the
   picture loads never fail silently: undecodable → alt text, see §1.3).

**Interactions.** Full player: inline WebView playback (inline + fullscreen, inline media
playback allowed); meta row opens the watch URL externally. Prose player: poster → tap →
embed. Fence ` ```youtube ` code value: watch URL or bare 11-char ID (both accepted).

**Bugs/edges addressed:**

- `5ea8379f5` — YouTube playback added (fence registration; old `SharedMarkdownLink`
  swapped any `Link` whose href parsed as YouTube for the player).
- `896a210b5` — player split into native (`player.tsx`) and web (`player.web.tsx`)
  implementations; web iframe, native WebView; `urls.ts` shared.
- `0cf3d465e` — re-embedded on the new segment pipeline: fences, standalone bare-URL
  lines, and sole-authored-link blocks all host the player between library segments;
  streaming-safe partial IDs; embedded links stayed links at that point.
- `17fa0049e` — in-sentence detection (`findYouTubeUrls` + `youtube-inline` cut +
  `YouTubeMiniPlayer`): links inside prose get the mention-sized poster instead of the
  full player; query strings and trailing punctuation handled; `mini.tsx` documented.
- `9072201eb` — full player scaled to 4:3 (was 16:9).
- `572f4c5b2` — `withUnistyles(…, (theme) => ({ theme }))`: the player's `StyleSheet.create`
  factory reads theme colors, so the wrapper had to inject it explicitly.
- `486373d03` / `1681665e6` / `3a5e76431` — the referrer saga (above).
- Old engine (`5ea8379f5`, `0e44c7860`) routed *all* assistant-chat links through
  `SharedMarkdownLink`/`AssistantMarkdownLink` to the player. **Removed at tip** — at tip
  the hosted-segment split owns YouTube; there is no link-renderer YouTube hook
  (`assistant-file-links/link.tsx` no longer exists, and its YouTube path with it;
  `docs/agents/docs.md` item 3 is stale on this point).

### 1.3 Inline images (authored `![alt](url)`, plus all image placements)

**Detection.** Authored Markdown images — mdast `image`/`imageReference` — plus anything
the pre-passes rewrite into image markdown (§1.4–1.6). Reference-style images resolve
through definitions (`source.ts:171-197`). Everything funnels into `prepared.images` →
`useMarkdownSource` (`images.ts:64`).

**The paragraph rule (the big one).** Every image gets **a paragraph of its own**, even
one that shares its line with text (`packages/app/src/components/markdown/image-paragraphs.ts`,
called from `source.ts:202`):

- Line boundary at/near the image → the source is edited so a blank line lands before and
  after the image (`split`). Continuation lines re-open quote markers (`> `) via the
  `blank` prefix computed from the line's prefix (`image-paragraphs.ts:44-60`).
- Mid-line sharing → the break is **recorded on the image** (`imageBreaks`, keyed by the
  image's own start offset) and inserted only when the image box actually renders
  (`breaksFor`, `source.ts:278`); the whitespace the break eats is excluded from text
  escaping (`clip`, `image-paragraphs.ts:87-96`).
- **Exception 1 — list items**: an image inside a list item keeps inline/tile placement;
  a blank line would end the list and a mid-line break would de-indent the tail of the
  item (`image-paragraphs.ts:10-23`).
- **Exception 2 — collapsed image**: if the image collapses to alt text (acquisition or
  decode failed, or an SVG on native), no paragraph split is applied — it stays inline
  where it was (`source.ts:268-288`; breaks are applied only when `url !== undefined`).
- A trailing `\` (hard break) at a split boundary is dropped so it doesn't render
  literally (`image-paragraphs.ts:54-59`).
- A link wrapping an image owns the breaks, keyed by its innermost image
  (`innermostImageStart`, `image-paragraphs.ts:97-104`).
- Fork commit history: `e83cedfc1` (introduced the rule — a text-sharing image was sized
  by the library as one text-line-height square, reading as a broken tile), `22a5703ea`
  (moved the rule into its own module `image-paragraphs.ts`), `e83cedfc1` docs note the
  upstream engine fork (`#7240`) moves this rule into C++ and deletes the app call.

**Sizing & radius (at tip)** — `packages/app/src/components/markdown/styles.ts:105`:

- Block image: `height: 320`, **`maxHeight: 1200`**, `resizeMode: "contain"`,
  **`borderRadius: 12`**, shared block gap margins. Inline (text-sharing) images:
  `inlineImage.size = paragraph.lineHeight` (`styles.ts:103`).
- The radius is a deliberate fork deviation pinned by `styles.fork.test.ts`
  (`image.borderRadius: 12`, `maxHeight: 1200`, `height: 320`) — upstream resets radius
  to 8; the fork keeps 12. `ed74573a4` restored 12px after an upstream merge reset it.
- Sizing saga: `876e808bc` introduced `maxHeight: 320` atop fixed `height: 320`;
  `9e86ea4d1` raised maxHeight to **1200** "so screenshots round"; `96674bb22` capped the
  old-engine styled image frames (520 max width) — later superseded; `ed74573a4` radius
  8→12.
- Effective behavior at tip: a block image box is 320 high with `contain`, never taller
  than 1200, corners rounded 12, full content width. Screenshots (tall) render at 320 high
  — the "screenful" cap is the point.

**Loading / pending / error frames:**

- Pending: the image is replaced by an opaque gray placeholder PNG (640×640, Lucide
  "image" icon at 60% opacity) — `PENDING_MARKDOWN_IMAGE`, `source.ts:115-116`,
  generated by `packages/app/scripts/generate-markdown-image-placeholder.mjs`. It reserves
  the box so layout doesn't jump; the press handler ignores taps on the placeholder
  (`renderer.tsx:134-136`).
- Pending set = every resolved-but-undecoded remote image (`getMarkdownImageStatus`,
  `image-decoding.ts:28-34`: `unavailable` if `!canAcquire && !url || acquisitionFailed ||
  decodeFailed`; else `ready` iff decoded, else `pending`).
- Unavailable (or SVG-on-native): the image node is rewritten to **escaped alt text** —
  there is no error frame, the image simply reads as its alt text (`source.ts:282-288`,
  `escapeMarkdownText`).
- The old engine had explicit loading/error frames (`components/message.tsx:787-822`,
  `imageLoadingOverlay`, `imageState` with `backgroundColor: surface2` added by
  `c1c9c854e` "tint image loading and error frames", `imageErrorText`). **At tip these
  styles are unused** — during the new-renderer merge the pipeline moved to the
  placeholder/alt-text model and the `imageFrame`/`imageSurface`/`imageState` leftovers
  were kept but lost their consumers. `96674bb22`'s `maxWidth: 520` on `imageSurface` and
  `alignItems: center` on `imageFrame` are likewise absent at tip. If you want visible
  shimmer/error UI on iOS, you're designing it fresh, not porting it.
- Decode probe sends no referrer on web (§1.2); native uses `Image.getSize`.

**Resolution details** (`useMarkdownSource`, `images.ts:64-152`):

- Remote (`https?:|data:|blob:`) → used as-is.
- Local/daemon paths → `resolveMarkdownPreviewImageSource`
  (`image-source.ts`): absolute/`~/` paths pass through; relative paths resolve against
  the markdown file's directory (workspaceRoot join); then acquired via daemon
  `readFile` → `persistAttachmentFromBytes` → preview URL, cached (500-entry acquisition
  cache) and GC-retained.
- All sources decoded once to check they're renderable; failures flip the image to
  unavailable (alt text) rather than leaving a spinner.
- One decode failure poisons nothing else: each source is independent.
- Tap → full-screen lightbox (`AttachmentLightbox`, `renderer.tsx:12,134-138,193`); the
  lightbox receives the resolved preview URL.

**Interactions.** Tap → lightbox. No long-press actions, no save button in chat, no
share (the old-engine lightbox is the same component).

### 1.4 Bare image URLs (linkifying `https://…png` lines)

**What it is.** A bare `https://host/pic.png` — line or mid-sentence — renders as an
image, not a link.

**Detection** — `hoistBareRemoteImages`,
`packages/app/src/utils/markdown-image-links.ts`:

- Source string pre-pass (runs before mdast), wired in `images.ts:48-54`.
- Protected zones (theme/code never touched): fenced blocks (` ``` `/`~~~`, including
  unclosed), inline code (`` ` `` runs), authored links `![…](…)` / `[…](…)`, autolinks
  `<…>` (`PROTECTED_RE`, `markdown-image-links.ts:13-14`).
- Bare URL scan in prose: `https?://<url-ish>` (`BARE_URL_RE`,
  `markdown-image-links.ts:15`): allowed chars `[^\s<>)\]]+`, then **trailing
  `.,;:!?` stripped** (`trimTrailingPunctuation`, `media-links.ts:50-52`, with
  `TRAILING_PUNCT_RE` `[.,;:!?]+$`).
- Kept iff `isRemoteImageUrl(url)` (`media-links.ts:33-35`): scheme matches
  `https?:|data:|blob:` **and** the part before `#` ends with
  `.png|.jpe?g|.gif|.webp|.svg` (case-insensitive) with optional `?query`/`#fragment`.
  Query strings are allowed on the image URL (`https://x.test/a.JPEG?w=2` qualifies;
  `.png.exe` does not).
- Rewritten to `![](<url>)`, i.e. indistinguishable from an authored image from there on.
- `71a3f1775` pins the design decision: bare remote images *are* images, by design.

**Placement.** Wherever the bare URL sits, including mid-sentence — the image then takes
a paragraph of its own per §1.3 (`e83cedfc1`). A bare image URL **line** never reaches the
link-card splitter because the pre-pass already made it an image node
(`link-card-segments.ts:35`). A bare image URL *link* (authored, `[t](…png)`) stays a
link.

**Rendering / interactions.** Identical to §1.3 (block image or own-paragraph inline
split, 320/1200/12px, lightbox, placeholder/alt-text gating).

**History.** `897ff3f0d` converted bare image URLs to image *nodes* inside a
markdown-it core rule (old engine); `9681d5620` dropped the parser rules when the engine
changed; `1339dc932` restored the behavior as a source pre-pass; `c118c180e` added
`.svg` to the image extensions (bare SVG URLs/paths preview); `71a3f1775` pinned tests.

### 1.5 Local image paths (and other bare absolute paths)

**What it is.** A bare `/abs/path/to/shot.png` (or `~/pics/shot.png`) in assistant text:
image paths render as images (resolved via the daemon), other paths render as `file://`
links that open the file preview.

**Detection** — `linkifyLocalPaths`,
`packages/app/src/utils/markdown-local-paths.ts`:

- Source pre-pass, last of the three, wired in `images.ts:54`.
- Protected zones: same `PROTECTED_RE` as §1.4 (code, fences, authored links, autolinks).
- Path scan: `(~?\/[^\s`'"[\]()<>]*)` (`markdown-local-paths.ts:16`) — absolute or
  home-relative only; **relative paths never match**; **Windows drive paths never match**
  this pre-pass (the engine's own `linkRecognition` text pattern in `source.ts` does
  match `C:\…` for plain text links — a separate, upstream mechanism).
- **Boundary rule**: the char before the match must be start-of-text, space, `\n`, `\t`,
  `(`, `[`, `"`, or `'` (`isPathStart`, `markdown-local-paths.ts:18-30`) — so `a/b` and
  `x(y/z)` don't linkify (mid-word slashes don't split).
- Trimmed: trailing `.,;:!?` (`trimTrailingPunctuation`); minimum length 2.
- Image extensions `.png|.jpe?g|.gif|.webp|.svg` (case-insensitive, no query/fragment
  needed for the local check — `isLocalImagePath`, `media-links.ts:38-42`) →
  `![<basename>](<path>)` — note the **basename becomes the alt text**
  (`markdown-local-paths.ts:32-36,47-50`). Otherwise → `[<path>](file://<path>)`
  (`markdown-local-paths.ts:47-51`).
- Streaming-safe: a partial path linkifies and extends on the next pass (file header
  comment).

**Resolution at render time** (`images.ts:65-111`, `image-source.ts`):

- Absolute or `~/` path → as-is; relative path → join against the markdown file's
  directory under the workspace root.
- Local image paths are acquired through the daemon client (`readFile`), persisted as
  attachments, previewed through blob/data URLs, cached (500) and GC-retained.
- Non-image bare paths → `file://<path>` links → same `pressLink` path as other links →
  `classifyAssistantFileLink` → in-app file preview (assistant-file-links machinery).

**Rendering / interactions.** Images: §1.3 rules (own paragraph, 320/1200, 12px radius,
lightbox). File links: accent-colored undecorated text (styles.ts link color), tap opens
the preview.

**History.** `cc1257598` added the markdown-it core rule (old engine); `9681d5620` dropped
it with the engine change; `1339dc932` restored it as a pre-pass; `c118c180e` added SVG
extensions; `71a3f1775` pinned the bare-remote-image-is-an-image design from the same
series.

### 1.6 Raw SVG blocks

**What it is.** A literal `<svg>…</svg>` block in assistant prose renders as an image
(data-URI), not as escaped text.

**Detection** — `hoistRawSvgToImages`,
`packages/app/src/utils/markdown-raw-svg.ts`:

- Source pre-pass, **first** of the three (`images.ts:48-54`).
- Match: `<svg(?:\s[^<>]*)?>…</svg\s*>` (case-insensitive, non-greedy, `RAW_SVG_RE`,
  `markdown-raw-svg.ts:13`). Attributes must not contain `<>`; anything else → no match.
- Size cap: **100 KiB** (`RAW_SVG_MAX_CHARS = 100 * 1024`, `markdown-raw-svg.ts:15`);
  oversized blocks stay text.
- Protected zones: fenced code (incl. unclosed) and inline code (`CODE_SPAN_RE`,
  `markdown-raw-svg.ts:14`).
- Rewritten to `![](data:image/svg+xml,<encodeURIComponent(raw)>)` — rides the stock
  image pipeline (placeholder, lightbox, pending/ready gating).
- **Native collapse**: at tip, `useMarkdownSource` passes `supportsSvg: isWeb`
  (`images.ts:57`); on native (`supportsSvg === false`) any image whose URL is `.svg` or
  `data:image/svg+xml` is rewritten to its escaped alt text — i.e. **raw SVG renders as
  nothing on native at tip** (`source.ts:184-193`). The alt is empty for raw SVG blocks,
  so nothing at all remains. Web renders the image.
- Scripts never execute (image context); no sanitizer needed. xmlns URLs survive because
  the whole tag is percent-encoded en bloc.
- Unclosed `<svg` (streaming) stays text by construction.

**Rendering / interactions.** Same as §1.3 (own paragraph, 320/1200, 12px radius,
lightbox on tap) — on web only. `.svg` *URLs* (remote or local) also classify as images
(`c118c180e`, §1.4/§1.5) and likewise collapse to alt text on native.

**History.** `0009f8701` — old engine: closed inline `<svg>` → data-URI image in
`html-ish.ts` (web-only; native "renders nothing"); `1ac27ae7a` — split a mid-prose svg
out of its surrounding markdown slices; `3f9a7c7fd` — same behavior as a markdown-it core
rule (anchor before linkify so the xmlns URL never linkified first); `589ebccb9` — moved
to a source pre-pass for the new engine; `0009f8701`/`1ac27ae7a`'s module (`html-ish.ts`)
is **gone at tip** (the new engine has no `html-ish.ts`).

### 1.7 The viz panel (` ```visualize ` fence) and viz bridges

Fully specified in §2. In the kinds table: an explicit-only fence (no bare-URL detection)
hosting an interactive HTML stage inline; pairs with a workspace-tab "viz panel" with
export; bridges `sendPrompt`/`saveState`/`loadState`.

### 1.8 Adjacent work worth knowing (not chat rich media, but same pipeline)

- **Hosted-segment stage table** (`hosted-segments.ts:24-40`, `d77ec2b40`, `e7b8c9e66`):
  mermaid (native-only) → youtube → cards → visualize; each stage cuts its
  blocks, the rest flows on; document order preserved; web drops mermaid to the library.
  A new hosted fence kind = one stage entry + one renderer case
  (`renderer.tsx:146-168`).
- **Every chat image a paragraph of its own** — §1.3.
- **Mermaid via the same stage table** — not media, but the reference pattern for any new
  hosted block you add.
- **Prompt-cache/Pi counters** — unrelated to media; explicitly out of scope here.
- **Long-press context menu on touch web** (`3c485a038`,
  `edca208fe`/`2e52cc360` revert+reapply) — file-tree rows only; not chat media.

---

## 2. The viz panel: what it is, what a viz bridge is, the message protocol

**What it is.** A ` ```visualize ` fence in assistant output carrying a **self-contained
HTML fragment** (style first, content, script last; no `<!DOCTYPE>`/`<html>`/`<body>`).
The app hosts the fragment two ways, both sandboxed, **offline** (no network):

- **Inline stage** in the chat (capped at one screenful: 800px max, 80px min, initial
  240px — `components/markdown/fence/visualize/stage.tsx:65,70,89`) — `VisualizeStage`,
  `packages/app/src/components/markdown/fence/visualize/stage.tsx`.
- **Viz panel**: a dedicated workspace tab rendering the same document uncapped
  (100000px), scrollable, with an Export button — `packages/app/src/panels/viz-panel.tsx`.

**A viz bridge** is the small set of JS functions injected *before* the fence's code
inside the stage document (`buildVizDocument`, `document.ts:67-69`; bridges defined before
content by `5e4695eab`, which fixed fence scripts running before `window.sendPrompt`
existed):

| Bridge (inside stage) | Direction | Meaning |
|---|---|---|
| `sendPrompt(text)` | stage → app | Submit a follow-up **into the session that rendered the fence, with the user's voice** (§ below). |
| `saveState(key, value)` | stage → app | Persist a string value, 64 KB cap per key, namespaced to the fence content. |
| `loadState(key)` | stage → app | `Promise` resolving to the stored string (or `null`), via a nonce. |

**Document construction** (`buildVizDocument`, `document.ts`):

- CSP (`document.ts:10-11`): `default-src 'none'; script-src 'unsafe-inline';
  style-src 'unsafe-inline'; img-src data: blob:; font-src data:; connect-src 'none';
  frame-src 'none'; object-src 'none'; base-uri 'none'` — no fetch, no frames, no
  exfiltration by construction.
- Theme: the document gets `color-scheme: light|dark` and three CSS vars —
  `--viz-fg` (`#e6e6e6` dark / `#1a1a1a` light), `--viz-bg` (transparent),
  `--viz-accent` (`#7dd3fc` dark / `#0369a1` light). An iframe cannot read app tokens;
  fence authors must use the vars (`docs/agents/visualize.md`).
- The body is `<bridge script><fence code>`; hostile strings can't escape because the
  code is document **body**, never parent markup (`viz.test.ts` "carries hostile strings").
- Height reporter: `MutationObserver` + `load` → posts `viz:height` with
  `document.documentElement.scrollHeight`.
- Outbound transport, dual-pathed: `parent.postMessage(msg, '*')` (web iframe) and
  `window.ReactNativeWebView.postMessage(JSON.stringify(msg))` (native WebView).

**Message protocol** (all messages shape-validated in `document.ts`):

Stage → app:

| `type` | Payload | Handled by |
|---|---|---|
| `viz:height` | `{ height: number }` (>0) | `setHeight(clamp(height, 80, cap))` — inline cap 800, panel cap 100000 (`stage.tsx:70,89`; `stage.web.tsx:79,96`). |
| `viz:prompt` | `{ text: string }` | `sendVizPrompt(serverId, agentId, text)` — fire-and-forget. |
| `viz:save` | `{ key: string, value: string }` | `vizSetState(`${hash}:${key}`, value)` — 64 KB cap (`VIZ_STATE_CAP_BYTES`, `bridges.ts:15,29-30`), silent failure. |
| `viz:load` | `{ key: string, nonce: number }` | `vizGetState(...)` then reply `viz:state` with the same nonce. |

App → stage:

| `type` | Payload | Transport |
|---|---|---|
| `viz:state` | `{ nonce: number, value: string \| null }` | Web: `contentWindow.postMessage(..., '*')` after validating `event.source === frame.contentWindow` (`stage.web.tsx:85-115`). Native: `injectJavaScript` dispatching a `MessageEvent('message', { data: … })` (`stage.tsx:78-86`). |

Native WebView path: `onMessage(WebViewMessageEvent)` with `event.nativeEvent.data`
JSON-parsed and validated; replies via `webviewRef.injectJavaScript(...)`
(`stage.tsx`). Web: window `message` listener, `event.source` must equal the iframe's
`contentWindow`, `event.data` shape-validated (`stage.web.tsx`).

**State persistence** (`bridges.ts:15-37`, `stage.tsx:43-47`):

- Key namespace: `vizstate:<hash>:<key>` where `<hash>` is the fence-content hash
  (`hashCode` djb2-like: `h = h * 31 + charCodeAt(i) | 0`, base36, `Math.abs`, prefixed
  `v`) — i.e. state is tied to the fence's content, not to a message/occurrence.
  Two fences with identical HTML share state; editing the fence forks its state.
- Storage: AsyncStorage; failures are swallowed (`vizGetState` → `null`, `vizSetState`
  → `false`); 64 KB cap checked against `value.length`.

**`sendPrompt` mechanics** (`bridges.ts:39-61`):

1. Trim; empty text, or missing `serverId`/`agentId`, or missing session/client → noop
   (`"noop"`).
2. Reads the daemon session from `useSessionStore`, checks
   `serverInfo.features.forgeSearch === true` for the attachment submit format.
3. Dispatches through the **stock composer send path** —
   `dispatchComposerAgentMessage` with `attachments: []`,
   `attachmentSubmitFormat` resolved from the forgeSearch flag,
   `createMessageSubmissionWriter(serverId)`, and
   **`activeTurnBehavior: "steer"`** — i.e. it steers (appends to) the running turn when
   one is active, otherwise starts a normal turn. The prompt is displayed as the user's
   message, indistinguishable from something the user typed.
4. Returns `"sent"`.

So: a viz bridge is not an RPC into the agent; it is a **user-voiced send** that flows
through the exact same submission machinery as typing in the composer. The web UI does the
same via the same function (`stage.web.tsx` calls the same `sendVizPrompt`).

**The panel** (`panels/viz-panel.tsx`, `panels/panel-manifest.ts:90-98`,
`workspace-tabs/`):

- Inline stage gets a floating **expand** button (`Maximize2`, absolute bottom-right,
  `right: 8, bottom: 8`, padding 6, radius 12, surface2 @ 92% opacity — `stage.tsx:29-40,
  119-131`; `d664af221` floated it over the visualization rather than a header strip).
  Shown only when `!expanded && serverId && workspaceId` (`stage.tsx:71`).
- Tap → `openVizPanel` (`store.ts:86-114`): builds `vizId = v<base36-hash>` of the code,
  writes a `vizdoc:<vizId>` record (`{ code, title="Visualization", serverId, agentId,
  updatedAt }`) into AsyncStorage + in-memory cache, and opens/reveals a workspace tab
  `{ kind: "viz", vizId }` in the current workspace. **Content-versioned**: the same fence
  reopens the same tab; new fence content ⇒ new tab. Tab target is normalized and compared
  by `vizId` (`workspace-tabs/identity.ts:59-62,142-145` — `9d3099eaa` fixed comparing
  untabs viz targets: trim, empty → null), persisted with the workspace layout
  (`workspace-tabs/model.ts:51`, `viz_${len}_${vizId}` identity at
  `workspace-tabs/identity.ts:239-241`), registered as a `main`-hosted panel with a
  `LayoutDashboard` icon (`panels/panel-manifest.ts:95`).
- The panel renders the **same `VisualizeStage`** with `expanded` (no expand button) and
  `uncapped` (height cap 100000) inside a `ScrollView`; missing doc → "Visualization
  unavailable." (`viz-panel.tsx:115-123`).
- **Export** (`viz-panel.tsx:67-93`): builds `buildVizDocument(code, "dark")` (note:
  **always dark**), slugs the title to `<slug>.html` (`exportFilename`, `viz-panel.tsx:67-74`),
  and either downloads via Blob + anchor (web) or writes to the app cache and shares via
  `expo-sharing` (native, `mimeType: text/html`). The export is the same sandboxed
  document, so it opens standalone with the same CSP — still no network.

**Fence detection recap**: explicit ` ```visualize ` code fences only
(`splitVisualizeFences`, `fence/visualize/segments.ts:19-43`); no URL detection, no
markers; fence value must be non-blank or the fence renders nothing
(`fence/visualize/index.tsx` VisualizeFence). Streaming: an unclosed fence is still
parsed as a `code` node by mdast (EOF-terminated), so it paints partial and settles —
**but** the module doc comment says unclosed fences "stay markdown until complete", which
contradicts the test ("paints unclosed fences partial (streaming)", `viz.test.ts`). The
comment is stale; the test and mdast behavior win. `viz.test.ts` is the spec for this
edge.

**Bridge-ordering fix** (`5e4695eab`): the bridge `<script>` was moved *before* the fence
code in `buildVizDocument`; previously fence scripts ran before `window.sendPrompt` was
defined and taps threw. `b4adabffc` repaired the test file orphaned by that edit.

**Docs**: `docs/agents/visualize.md` (at tip) is the author-facing protocol: one fence per
visualization, fragment only, no network, use the theme vars, inline cap one screenful,
bridges act as the user, keep scripts idempotent (they run on every streaming repaint), say
what each tap does, never exfiltrate.

**sendPrompt worked example**: a button `onclick="sendPrompt('Break this chart down')"`
inside a viz fence → user-voiced `viz:prompt` → app trims, dispatches via the composer
path with `steer` → the agent sees a normal user message "Break this chart down" in the
session that rendered the fence. Toggles/sliders → `saveState`/`loadState` to keep state
across reloads (e.g. selected series) keyed by fence content.

---

## 3. Native iOS mapping (suggestions, not decisions)

| Kind | Fork behavior (recap) | Suggested native component(s) |
|---|---|---|
| Link card | Favicon + domain + trimmed URL; standalone bare links only (§1.1) | **`LPLinkView`** (LinkPresentation) — gets rich metadata (title, icon, image) for free and matches Apple HIG; fallback for no-metadata links: custom row (favicon via `LPMetadataProvider` or Google `s2/favicons` service as in fork, 32pt icon radius 8, domain 13pt semibold, URL 12pt muted middle-ellipsis, radius 12, border). `LPLinkView` also covers **any** bare link, including maps (fork has no map handling). |
| Map links | *(absent in fork — nothing to port)* | `LPLinkView` if you take the row approach; **MapKit** snapshot via `MKMapSnapshotter` if you later want rich map previews — out of fork scope. |
| YouTube full player | `youtube-nocookie` embed, 4:3, radius 8, nocookie + referrer-ish policy, tap-out row (§1.2) | **WKWebView** loading `https://www.youtube-nocookie.com/embed/<id>?rel=0` (parity), or **`YTPlayerView`** (YouTube iOS Helper) for a native player chrome; AVKit cannot play YouTube embeds. Keep a `LPLinkView`-style fallback/tap-out row with `youtube.com · <id>` (watch URL) opening `openURL`. Aspect: fork uses 4:3 — decide deliberately; 16:9 is HIG-friendlier. `allowsInlineMediaPlayback` equivalent: `WKWebViewConfiguration.allowsInlineMediaPlayback = true`. |
| YouTube prose player | 16:9 poster (hqdefault), max 320pt, radius 12, tap to swap in embed (§1.2) | Custom SwiftUI view: `AsyncImage` for `https://i.ytimg.com/vi/<id>/hqdefault.jpg` (`cover`), dark 34pt play scrim, on tap swap in the same WKWebView embed. Must reuse the same embed component as the full player. |
| Inline block images | Own paragraph; height 320, max 1200, radius 12, `contain`; tap → lightbox (§1.3) | SwiftUI `Image`/`AsyncImage` in a rounded (12) frame, `scaledToFit`, fixed 320pt height, max 1200; tap → **QuickLook** or a custom lightbox (fork reuses its attachment lightbox; yours: `QLPreviewController` or an SF-symboled zoom view). For daemon-resolved local files: persist as file URLs and load directly. |
| Bare image URLs | `![](…)` via pre-pass; same as §1.3 (§1.4) | Same image component; no link affordance until tap; do not open in Safari. |
| Local image paths | Daemon `readFile` → preview URL; same rendering (§1.5) | Same image component; resolve via the daemon client into the app's image cache (mirror the acquisition cache, 500 entries, attachment-backed GC retention) — **do not** read arbitrary paths directly; the daemon is the filesystem authority. |
| Local non-image paths | `file://` link → file preview (§1.5) | `file://`-equivalent link on the text; open in the same file preview feature used for daemon file links (fork uses assistant-file-links; the iOS app has its own file opening). |
| Raw SVG blocks | Data-URI `![](data:image/svg+xml,…)`; **renders as nothing on native at tip** (§1.6) | `SVGKit` (Objective-C, mature) or `WKWebView` per block (heavier), or convert via `SwiftSVG`; keep the 100 KB cap, the code-span exclusion, the "unclosed stays text" streaming rule, and give scripts a chance to *never* run (image context only). Do strictly better than the fork here: iOS can render SVG for free-ish. |
| Viz panel (inline) | Sandboxed `loadHTMLString`-ish doc; height 80–800 (inline 800); theme vars; CSP (§2) | **WKWebView** with `loadHTMLString(buildVizDocument(code))` (no base URL, `allowFileAccess=false`); height via `WKScriptMessageHandler` (`viz:height`), clamp [80, 800]; `isInspectable = false`; theme vars inlined same as fork; radius 12, surface background. Navigation: block all loads except the initial document; `decidePolicyFor` → allow only the initial navigation, cancel everything (CSP equivalent of fork's `connect-src 'none'`). |
| Viz panel (expanded tab) | Uncapped (100000) ScrollView tab + export (§2) | Full-screen cover or a detail pane/sheet hosting the same WKWebView; export via a `ShareLink`/`UIActivityViewController` of the built document (`<slug>.html`, always-dark build as in fork — or fix that to match scheme). |
| Viz bridges (`sendPrompt`) | `viz:prompt` → composer dispatch with `steer` | `WKScriptMessageHandler` (`viz:prompt`) → the iOS client's own agent-send path with `activeTurnBehavior: "steer"` — the protocol supports it (same as the app's `DaemonClient` send); no new IPC. Validate message names + shapes like the fork. |
| Viz bridges (`saveState`/`loadState`) | `vizstate:<hash>:<key>` in AsyncStorage, 64 KB cap, nonce load (§2) | Same: namespace `vizstate:<contentHash>:<key>` in `UserDefaults`/file store; 64 KB cap; content hash = same djb2-family or SHA-256 (pick one; document it). |
| Pending image placeholder | 640×640 gray Lucide icon PNG data URI (§1.3) | Your own placeholder asset (e.g. SF Symbol `photo` at 60% opacity on a gray square); the exact PNG is in `source.ts:115-116` if you want byte parity. |
| Image error | Alt text replaces the image (no error frame at tip) (§1.3) | Render alt text inline (mono/muted) or an unobtrusive inline placeholder with an SF Symbol; do not leave a spinner. |

Notes for whoever picks this up:

- **Fork quirks you may want to fix rather than port**: full player is 4:3 but the prose
  player is 16:9; `inline height: 320` fixed with `maxHeight: 1200` effectively never
  applies (height wins) — confirm intended semantics; viz export always builds the
  **dark** document; `.svg` and raw SVG render as *nothing* on the fork's native
  renderer; `isSoleBlockContent` is dead code; the `imageFrame`-family styles are dead
  code (§6).
- **Keep**: streaming-safety everywhere (partial IDs never flip a link into a player);
  protected zones for code; own-paragraph image rule with the two exceptions;
  hosted-segment document order.
- **The referrer saga does not translate 1:1** (§1.2): iOS gives you no per-request
  referrer switch; the failure mode (hotlink 307 → undecodable image → alt text) is only
  partially avoidable via `URLProtocol` hacks. Treat as accepted risk or strip via a
  custom scheme handler.

---

## 4. Commit map (what each commit did, one line each)

Fork-only media commits from the compare API (first-parent merges excluded), in the order
they matter to this spec:

- `55ca8ad98` classifiers without plugin gates · `0e663411b` card + inline bare links (old engine)
- `cc1257598` bare local paths linkified (old engine) · `897ff3f0d` bare image URLs → image nodes (old engine)
- `71a3f1775` test pin: bare remote images are images · `9681d5620` drop parser rules at engine cutover
- `1339dc932` restore bare images/local paths as source pre-passes · `c118c180e` bare `.svg` URLs/paths
- `0009f8701` inline SVG → data-URI image (old engine) · `1ac27ae7a` split mid-prose svg · `3f9a7c7fd` raw SVG pre-pass
- `589ebccb9` hoist SVG into the image pipeline · `3a5e76431` scope no-referrer to images
- `5ea8379f5` YouTube inline player · `896a210b5` native/web player split · `572f4c5b2` inject theme
- `9072201eb` player 4:3 · `0cf3d465e` re-embed on new pipeline · `17fa0049e` prose mini player
- `0e44c7860` route assistant links to player (old, removed at tip) · `1681665e6` drop Referer (server header)
- `486373d03` give embeds a referrer (error 153 fix) · `3a5e76431` scope no-referrer to images only
- `96674bb22` cap frame size + radius 12 · `ed74573a4` keep 12px radius · `876e808bc` cap vs fix height
- `9e86ea4d1` cap images at 1200 · `e83cedfc1` every image its own paragraph · `22a5703ea` image-paragraphs module
- `c1c9c854e` tint loading/error frames (now dead code) · `e83cedfc1`/`7ce9edf4c` docs
- `1081b7638` line breaks count as whitespace · `fd2ef8964` placement matches real AST shape
- `145caaca5` standalone bare links as cards (new pipeline) · `8cf72d785` docs
- `61a12b79e` viz inline stage v1 · `e7f9ad38d` viz bridges + sendPrompt + per-fence state
- `5e4695eab` bridges defined before fence content · `b4adabffc` repair viz order test
- `714c545a6` viz panel tab + export · `9d3099eaa` normalize/compare viz tab targets
- `d664af221` float expand control · `d77ec2b40` one stage table · `e7b8c9e66` explicit web fence gate
- `bc104442e` library-internals test seam · `22a5703ea` image rule module · `7ce9edf4c` docs

## 5. Notable fork docs (author-facing contracts to reuse)

- `docs/agents/visualize.md` (tip) — viz fence protocol: fragment only; no network; use
  `--viz-fg/--viz-bg/--viz-accent`; inline cap one screenful; bridges act as the user;
  scripts must be idempotent (re-run on streaming paints); taps act as the user; no
  exfiltration.
- `docs/agents/docs.md` (tip) — fork maintenance map: media files list, failure map,
  upstream-merge hazards. Stale entries flagged in this document: item 3 (YouTube via
  `assistant-file-links/link.tsx`, gone), item 9 (bare image URLs via the `message.tsx`
  link rule — pre-passes own them now).

## 6. Discrepancies and dead code at tip (for honesty, not for porting)

1. **`imageFrame`, `imageSurface`, `imageLoadingOverlay`, `imageState`, `imageErrorText`**
   in `components/message.tsx:787-822` — unreferenced at tip; leftover from the
   old-engine image component. `c1c9c854e` and `96674bb22` modified these; the new
   pipeline replaced the model (placeholder PNG / alt-text collapse) and dropped the
   consumers.
2. **`isSoleBlockContent`** (`media-links.ts:65-81`) — old-engine card placement helper,
   unreferenced; `splitLinkCards` is the live rule.
3. **`.svg` and raw SVG render as nothing on the fork's native renderer** by design
   (`images.ts:57`, `source.ts:184-193`) — alt text is empty, so no trace remains.
4. **Inline image `height: 320` fixed with `maxHeight: 1200`** — the max never engages
   (fixed height wins); 1200 is aspirational per `styles.fork.test.ts`.
5. **`fence/visualize/segments.ts` doc comment** says unclosed fences "stay markdown until
   complete"; the test requires they paint partial — stale comment, lazy-terminated mdast
   behavior and `viz.test.ts` govern.
6. **`docs/agents/docs.md` items 3 and 9** reference `assistant-file-links/link.tsx` and
   the `components/message.tsx` link rule for bare image URLs, neither of which exists in the
   pipeline at tip — both describe the pre-new-renderer pipeline.
7. **Viz export always builds the dark document** (`viz-panel.tsx:77` passes `"dark"`),
   regardless of reader theme.
8. **Full YouTube player is 4:3** while its prose sibling is 16:9 — deliberate
   (`9072201eb`) but surprising; decide for iOS.
9. **Export/expand require** `serverId && workspaceId` (`stage.tsx:71`,
   `stage.web.tsx:80`); without them the stage renders with no affordance at all.

## 7. Acceptance checklist for the iOS reimplementation

- [ ] Bare URL on its own line → favicon card; same URL inside a sentence → link;
      `[t](u)` → link; image URL → image; YouTube → player.
- [ ] YouTube bare URL line/fence/sole-authored-link → full player; sentence URL →
      16:9 poster, tap → embed; trailing `,` `.` `)` stay in prose; `?t=30` kept.
- [ ] `![...](...)` mid-sentence → image split onto its own paragraph; inside a list item
      → stays inline; alt text shown when undecodable; tap → lightbox; SVG → chosen
      behavior (must be *rendered*, not empty).
- [ ] `/abs/shot.png` and `~/shot.png` → image; `/abs/other.txt` → file-preview link;
      trailing punctuation excluded; code spans untouched.
- [ ] ` ```visualize ` fence → sandboxed stage ≤ 800pt tall; height auto; taps inject
      user-voiced composer messages with steer; `saveState`/`loadState` round-trip with a
      64 KB cap; expand opens a tab; export shares a self-contained HTML file.
- [ ] Referrer/hotlink strategy documented for WKWebView.

Verified: 182 citations checked, 14 corrected
