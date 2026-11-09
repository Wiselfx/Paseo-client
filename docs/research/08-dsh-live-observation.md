# DSH live observation — measured values, light and dark

**What this is.** The numbers a SwiftUI developer can copy, taken from the live DSH web UI
with the Claude-style plugin installed (the `dsh web` instance on the LAN), not from reading
the plugin's source. Every value below was measured in the running page and then traced back
to the line in the reference repo that writes it, so the citation is the thing to trust if the
live build and the source ever disagree — and where they *do* disagree, this document says so.

- **Measured on:** 2026-11-09, Chromium 150 headless (same engine family as the Electron app
  the user runs), viewport 1440 × 857 CSS px, DPR 1 (so a CSS `0.5px` reports as `1px` in
  computed style; the source value is quoted instead). Both themes via
  `prefers-color-scheme`; the app follows it (`color-scheme` flips, every `--dsw-*` token
  changes).
- **Driven via:** raw CDP (Node 24 `WebSocket`, no puppeteer): `Runtime.evaluate` for
  computed styles / DOM, `Page.captureScreenshot` for evidence, `Input.*` for typing and
  hover/press states, `Emulation.setEmulatedMedia` for the theme.
- **Screenshots:** kept in `/tmp/dsh-shots` only. Nothing from the live instance (token,
  host, images) is in this repo.
- **Paths:** all `file:line` citations are relative to `/home/paseo/dev/dsh-claude-style-reference`
  unless they start with `Packages/`, which are ours.
- **Session used:** the free default model in a fresh chat, with prompts that force reasoning
  + tool calls ("list the files… then read one… explain"). One turn produced 3 thoughts /
  2 tool calls; another 6 thoughts / 12 tool calls.

Selector shorthand used below: `[data-step-process]` = the process group root,
`[data-step-process-body]` = the open card, `[data-step-process-content]` = the rows,
`[data-process-activity]` = the counted header button, `[data-composer-card]` = the composer.

**Not observed** (called out again where it matters, and never presented as measured):

- The **hover colour change** on summary rows and step rows. The app runs its chat-reveal
  feature (`data-dsh-claude-chat-reveal`), which paints text through `::highlight()` from a
  per-element colour, so hovering a row did **not** repaint it in the live page. The
  tertiary→secondary hover values below come from the stylesheet rules, and were confirmed
  with the reveal attribute temporarily removed for measurement.
- Loader **lanes B and C in motion**: only lane A (bounce) and lane C (orbit) were caught as
  the active lane; the walk lane's numbers are source-only.
- Mascot **hover bubble** contents and **facing per frame** (see §7).
- The **hero** composer in dark, and dark-theme hover/pressed states generally.
- Anything outside the chat page (sidebar running dots, status-badge colours).

---

## 1. Work-group summary rows and the step rows

### 1.1 Geometry, measured

| Part | Measured | Source |
|---|---|---|
| Summary row height | 17.5 px (14 px × 1.25) | `theme/typography.css:74-78` |
| Summary row → card gap | 8 px | `features/chat-fold/fold.css:113-119` |
| Card radius | 8 px | `features/process-column/process-column.css:16-17` |
| Card border | 1 px `--dsw-alias-border-l1` | same, `process-column.css:16` |
| Card fill | **transparent** — the canvas (`#FFFFFF` / `#191919`) shows through | measured; source paints no fill (`process-column.css:13-22`) |
| Row horizontal inset | 12 px each side | `process-column.css:27-31` |
| Row divider | 0.5 px, `--dsh-claude-divider`, between rows only (never above the first) | `process-column.css:33-36` |
| Gap between row boxes | **4 px** (host's `--dsh-chat-flow-gap`, default 4 px) | host rule `.O_Ebla_content > … { margin-top: var(--dsh-chat-flow-gap,4px) }`, measured 4 px |
| Thought row height | 36 px (`min-height: 36px`, `padding-block: 6px`) | `process-column.css:50-54` |
| File row height | 36 px (same rule) | same |
| Shell/tool row height | **24 px** — the skin's 36 px rule only reaches `[data-disclosure-row]`, and the shell row's button is not one | `process-column.css:50`; measured 24 px |
| Header `padding-bottom` while open | 0 (the 8 px lives on the body's `margin-top`) | `fold.css:113-119` |
| Expanded-row detail bottom pad | 10 px | `process-column.css:63-65` |

The open card was 196 px tall for 3 thoughts + 2 tool calls: the measured row boxes were
36 + 25 + 37 + 37 + 43 px with 4 × 4 px gaps = 194 px, plus the two 1 px borders. The host
still caps a group at `min(400px, 50vh)` where it caps
(`process-column.css:1-14`, `docs/STYLE.md:800-803`).

**Correction to doc 06 §1.4:** the rows are *not* uniformly 36 px, and a shell call row is
24 px. The 36 px is the skin's restatement for disclosure rows only.

### 1.2 The counted summary row (header)

- The host's own words ("Ran commands and read files") are hidden
  (`fold.css:12-14`). The skin's span carries the sentence.
- Text is **14 px serif, weight 500, line-height 17.5 px (1.25), letter-spacing −0.14 px
  (−0.01 em), colour `--dsw-alias-label-tertiary`** — light `#91888A`, dark `#9C9395`.
  The serif/500/−0.01 em/1.25 comes from the shared rule
  `typography.css:74-78` matching the button's `data-dsh-claude-part="text-title"`; the
  colour is `.O_Ebla_title` (host CSS, measured).
- Background: none. Border: none. No padding.
- Hover: `color` → `--dsw-alias-label-secondary` (`#70686A` / `#BEB6B8`), transition
  `color .1s` (host `.O_Ebla_title:hover`; measured).
- Pressed: **no rule at all.** There is no `:active` style anywhere in the app for this
  control (searched every stylesheet: the only `:active` rules are the host's generic ghost
  buttons and card links). The only press feedback is the expansion itself.
- Wording: full form `{n} thought(s)` / `{n} tool call(s)` (and output/record figures),
  separator `, `; compact form `Thinking×{n}` / `Tools×{n}` with ` · ` when the sentence
  does not fit the header's room (`features/chat-fold/chat-fold.copy.json:2-14`,
  `process-summary.ts:114-128`). Live: `3 thoughts, 2 tool calls`, `6 thoughts, 12 tool
  calls`.
- Digits roll in place, 160 ms, `cubic-bezier(0.4,0,0.2,1)` (`fold.css:51-88`,
  `tokens.json:1083-1084,1305`).
- Leading seat: 16 × 16 box, 14 × 14 icon, 6 px gap (`host .O_Ebla_leading`, measured). The
  seat holds **two absolutely stacked glyphs that swap on hover**:
  - resting: the group's activity icon (a sparkle/`browse`/`api` glyph depending on content),
    opacity 1;
  - hover/focus: a 14 × 14 `chevron-down` glyph, opacity 0 → 1, `transition: opacity .1s`;
  - expanded: `chevron-up`, opacity 1.
  (host rules `.O_Ebla_activityIcon` / `.O_Ebla_chevron`; measured the `use href` swap:
  `#dsw-icon-chevron-down-outline-regular` when collapsed, `…chevron-up…` when expanded.)
- **There is no trailing chevron on the summary row.** The chevron lives in the leading seat.

### 1.3 The three row kinds inside the card

The card mixes three row implementations, and they do not share one style. This is the part
that is easiest to get wrong.

**(a) Thought row — collapsed** (`[data-variant="think"]`, skin's cap on the body):

- No leading icon at all: the skin hides the host's leading seat outright
  (`process-column.css:69-72`).
- One line of preview text: **13 px / 20 px, sans (`Anthropic Sans Web Text`), weight 400,
  tertiary**, ellipsised (host `.lcKema_summary`: 13 px / 20 px; measured).
- Trailing chevron: the skin's own **12 × 12 mask**, `margin-inline-start: 6px`, painted with
  `currentColor`, SVG `viewBox 0 0 16 16`, path `M6 4l4 4-4 4`, stroke 1.5, round caps,
  `transform: rotate(90deg)` when open, `transition: transform .12s` (the feedback token)
  (`process-column.css:84-99`; `tokens.json:1011-1013`).
- Row ink tertiary; hover ink secondary on the *host* row, but see §1.5 — with the reveal
  feature on, the painted colour does not follow hover.

**(b) Thought row — expanded:**

- The header now reads **"Think"**, 13 px / 16.25 px **serif**, weight 500, tertiary, with the
  same trailing chevron rotated down (measured; `typography.css:74-78` gives the serif/500).
- Body: `padding: 4px 0 10px 22px` (10 px is the skin's, `process-column.css:63-65`;
  22 px is the host's `.lcKema_thinkBody`).
- Paragraphs: **13 px / 23 px serif, tertiary**, `margin: 4px 0`
  (`typography.css:103-105` for the compact variant; measured 13/23).
- Inline code inside: 12 px mono, colour `#161616`, background `rgba(6,6,6,0.05)`, radius 4 px,
  padding 1 px, line-height 14.4 px (measured).

**(c) File row (Read / Edit / Write):**

- Leading seat hidden by the skin (same rule); trailing 12 × 12 chevron (same rule).
- Verb `Read` — **13 px / 24 px sans, weight 400, secondary** (`#70686A` / `#BEB6B8`)
  (`process-column.css` companion `.dsh-claude-file-title`, measured).
- 2 × 2 px round separator, **caption** `#B2ACAD` (`#776F71`), margin 0 8 px
  (`.dsh-claude-file-sep`, host `.lcKema_separator`).
- File name — 13 px sans secondary, **dotted underline 1 px in tertiary, offset 3 px**
  (it is a button, `.dsh-claude-file-link`).
- Hover: verb and file name go to **primary** (`#161616` / `#FDFDFD`)
  (`.dsh-claude-file-row:hover .dsh-claude-file-title`, `…-link`).

**(d) Shell / generic tool row (`Bash`, `api` variant):**

- **Keeps a leading icon**: 16 × 16 seat, 14 × 14 glyph, tertiary, `margin-right: 6px`
  (host `.CY-8Ka_leading`). For `bash` the glyph is `dsw-icon-api-outline-regular`:
  `M3 4L7 8L3 12` + `M9 12H13`, stroke 1 — the `>-` prompt you see in the screenshots.
- On hover the icon fades out and the **same 14 × 14 `chevron-down`** fades in, in place
  (host `.CY-8Ka_root:hover .CY-8Ka_iconIdle {opacity:0}` /
  `.CY-8Ka_chevronHover{opacity:1}`). No trailing chevron for these rows.
- Verb — 13 px serif 500 (`text-title` rule again), tertiary. Description after the 2 × 2 dot
  separator — 13 px / 24 px sans 400, tertiary (measured).
- Row ink hover: tertiary → secondary (host rule).

**Correction to doc 06 §1.4** ("No icon leads a row"): that is true for thought and file rows
only. The shell/tool row leads with the tool's icon and swaps it for a chevron on hover,
in the leading seat. It also has no trailing chevron, and is 24 px tall, not 36.

### 1.4 Icons and the chevron spec

All icons are 14 × 14 in a 16 × 16 seat, drawn from a 16-unit viewBox with `stroke-width: 1`
(1.5 for the skin's chevron mask, whose caps are round), `stroke: currentColor`. Glyphs seen
live:

- `dsw-icon-think-outline-regular` — a bow-tie/atom outline (thought),
  `M10.2854 5.71481C…Z` twice + a filled 1.7 px dot at centre.
- `dsw-icon-api-outline-regular` — terminal prompt, two paths (`M3 4L7 8L3 12`, `M9 12H13`).
- `dsw-icon-browse-outline-regular` — a page outline with two lines.
- `dsw-icon-chevron-down-outline-regular` — `M4 6L7.29 9.29a1 1 0 0 0 1.41 0L12 6`.
- The skin's trailing chevron is not an icon font at all: a 12 × 12 `currentColor` mask of
  `M6 4l4 4-4 4` (see (a)) — so it is the row's own colour, i.e. tertiary at rest.

### 1.5 Why ours looks reddish-pink, and what to change

Live DSH says the tint is **not** in the palette: every process-row colour there is a warm
neutral (`#91888A`, `#9C9395`) and the only warm thing near a running row is the accent
`#D97757` in the *loader dots*. Our tint comes from three separate places in our code:

1. **The running header's sweep band is an orange wash.** `ClaudeChatView.swift:667`
   attaches `ClaudeSweepBand()` behind the summary `HStack`, and that band is
   `ClaudePalette.orange.opacity(0.18)` (`ClaudeChatView.swift:816`) —
   `#CC5C3B` at 18 % painted *behind* grey text. On DSH the sweep is never a wash behind the
   words: it is a masked **copy of the glyphs themselves**, tinted
   `--dsw-alias-label-shimmer` = `#161616` light / `#FDFDFD` dark
   (`shared/motion.css:158-178`), with the mask `linear-gradient(105deg, transparent 0,
   #000 40% 60%, transparent 100%)` (`shared/motion.css:26`) moving
   `translateX(-100% → 100%)` while the glyph copy moves `+100% → -100%`
   (`shared/motion.css:108-116`). A neutral ink band, not orange, and it never recolours the
   row's background.
2. **The summary text is a step too dark/warm.** Ours is `secondaryInk` (`#70686A`)
   (`ClaudeChatView.swift:665`, palette at `ClaudeStyle.swift:34-40`), where DSH's summary is
   **tertiary** (`#91888A` / `#9C9395`). `#70686A` is the darkest of the warm greys and, at
   14 px next to an orange band, is what reads mauve/pink.
3. **Our row labels are darker and bolder than any DSH row.** `ClaudeStepRow` prefixes every
   thought with `"Thought"` at weight `.medium` in `secondaryInk`
   (`ClaudeChatView.swift:751-753`), and every tool call title in `ClaudePalette.ink`
   (`ClaudeChatView.swift:764-766`). DSH has no "Thought" label at all (the collapsed row is
   just the preview sentence), and its tool verbs are tertiary.

Two more small colour drifts in the same family: our accent is `#CC5C3B`
(`ClaudeStyle.swift:29`) where DSH's is `#D97757` (`tokens.json:81`, live measured), and our
dark card fill is `panel = 0.13` (`#212121`, `ClaudeStyle.swift:19`) where DSH's card is
transparent over a `#191919` canvas.

Everything else in the same area matches closely (0.5 pt dividers, 8–10 pt radius, 400-weight
row ink); it is the band and the two shades that carry the tint.

---

## 2. The loader next to the status line

### 2.1 Box and colour

- Container `.dsh-claude-chat-wait-loader`: **18 × 14 px**, `display: inline-flex`,
  `margin-right: 6 px`, `position: relative` (`features/chat-wait/chat-wait.css:118-125`;
  measured 18 × 14 at x=0 of the row).
- Each lane is `position:absolute; inset:0` (`chat-wait.css:133-136`).
- Each dot: **4 × 4 px, `border-radius: 50%`, `background: var(--dsw-alias-brand-primary)` =
  `#D97757`**, `transform-origin: 50% 100%`, `opacity: 0` unless its lane is
  `is-active`/`is-leaving` (`chat-wait.css:148-175`; live measured `rgb(217,119,87)`).
- There is **no SVG**. It is three `<span>` lanes of 3, 3 and 4 dots each; only one lane is
  mounted at a time (`is-resting` → `display:none`, `chat-wait.css:138-140`).
- `bottom: 0` for the bounce/line lanes, so dots sit on the loader's floor (the text's
  baseline-ish line), not centred.

### 2.2 Lane A — bounce (3 dots, the classic)

`chat-wait.css:329-345` (delays), `chat-wait.css:424-444` (keyframes).

- Dots at `left: 0 / 7 / 14 px`, `bottom: 0`.
- Keyframes of `dsh-claude-wait-dot`, **500 ms**, `ease`, `infinite alternate`:
  - `0%`  `translate: 0 0; scale: 1.7 0.25` (squashed flat on the floor)
  - `40%` `translate: 0 -3.2px; scale: 1` (`-2 × 8px / 5`)
  - `60%` `translate: 0 -4.8px` (`-3 × 8px / 5`)
  - `100%` `translate: 0 -8px` (the whole `--dsh-claude-distance-travel`)
  - the 0→40 % and 40→60 % segments carry `linear`; the 60→100 % segment uses the
    animation's own `ease` (the "ball leaves the floor fast, slows at the top" read).
- Delays (negative, so the wave is already in progress at mount):
  dot 1 `-500 ms`, dot 2 `-300 ms` (`-3/5`), dot 3 `-200 ms` (`-2/5`).
- Rebuild in SwiftUI: three 4 pt circles anchored bottom-leading at x = 0/7/14, in an
  18 × 14 box; animate `offset(y)` and `scale(y)` with a 0.5 s autoreversing curve; stagger
  phases by 0.4 and 0.2 of the period.

### 2.3 Lane B — line (3 dots, harmonic)

`chat-wait.css:358-380`, `chat-wait.css:446-462`.

- Dots at `left: 0 / 7 / 14`, each walking a line through one common point, 120° apart
  (up; down-left; down-right), each shrinking to **0.55× at the middle**
  (`--dsh-claude-scale-dot-mid`, `tokens.json:1408`).
- **1250 ms**, `cubic-bezier(0.37,0,0.63,1)` (`--dsh-claude-ease-harmonic`,
  `tokens.json:1335`), infinite; delays `-1/4`, `-7/12`, `-11/12` of the period.
- Travel: `2 × --dsh-claude-distance-travel` (16 px) end to end; the dot's own size shrinks to 55 % as it crosses the middle.

### 2.4 Lane C — orbit (4 dots, corner swap)

`chat-wait.css:218-260` + keyframes `241-319`.

- 4 dots centred on the box, offsets generated by `top/left: 50%; margin: -2px 0 0 -2px`.
- Corners at `±4.75 px, ±5.8 px` (a 9.5 × 11.6 box, the 45 : 55 rectangle), each arc walked
  on `cubic-bezier(0.16,0.75,0.29,0.97)`, **2400 ms linear** per full turn: 400 ms A-run
  (dots 1 & 4 swap), 200 ms rest, 400 ms B-run (dots 2 & 3), 200 ms rest, then back.
- This is the lane the screenshots caught: four dots in a diamond, swapping corners.

### 2.5 Rotation and hand-over

- The lane in play **rotates on a 10 s clock** (`--dsh-claude-period-dot-rotate`,
  `tokens.json:1149`).
- Each dot is handed over at a still moment of its own motion, with a **480 ms** morph
  (`--dsh-claude-duration-dot-morph`, `tokens.json:1154`); the arriving lane's dots fade in,
  the leaving lane's fade out, and a lane out of play is unmounted
  (`features/chat-wait/wait-loader.ts`, `chat-wait.css:192-222`).
- Reduced motion: every dot's animation is `animation-play-state: paused`, so the wave is
  frozen at its three heights and the walk at its three places
  (`chat-wait.css:410-412`).

### 2.5b A SwiftUI rebuild that matches the numbers

One `Canvas` (or a `TimelineView` over three `Circle`s) in an **18 × 14** frame with the box
bottom-aligned to the label's 24 px line. Dot diameter 4; in a 14 px-tall box the resting
centre is y = 12 (dot bottom on y = 14).

- **Bounce lane.** Centres at x = 2, 9, 16. One period T = 0.5 s, autoreversing, ease; phases
  0, 0.4, 0.6 of T (dot 1 already at the top, dot 2 climbing, dot 3 climbing from lower).
  `y(t) = 12 − 8 · hop(t)` where `hop` runs 0 → 1 over the first half; height is
  `4 · (1 − 0.75 · squash)` with `squash = 1` (i.e. scaleY 0.25, scaleX 1.7) exactly at the
  floor and 0 from 40 % of the hop onward.
- **Line lane.** Same three x centres. For dot k with unit direction `(dx, dy)` from
  `(0,-1)`, `(-0.866,-0.5)`, `(-0.866,0.5)`: `p(t, k) = start + (end − start) · (1 − cos(2πt))/2`
  with `end − start = 16 · (dx, dy)`; `scale = 1 − 0.45 · sin²(2πt)` (0.55 at the middle).
  Period 1.25 s, `cubic-bezier(0.37,0,0.63,1)`, phases 0, 5/12, 1/12 (i.e. −1/4, −7/12,
  −11/12 of the period).
- **Orbit lane.** Four dots, corners at `(±4.75, ±5.8)` from the box centre `(9, 8)`,
  period 2.4 s linear: 0–16.67 % the A pair (1 & 4) swaps along its quarter-ellipse arc,
  16.67–25 % rest, 25–41.67 % the B pair (2 & 3), 41.67–50 % rest, then back over the second
  half. Sample the arc positions at the keyframe percentages in `chat-wait.css:241-319` if you
  need frame-exact parity; a plain elliptical interpolation over each run reads identical at
  this size.
- Cross-fade lanes over 0.48 s every 10 s. Pause everything under Reduce Motion.

### 2.6 The rest of the line (for composition)

Measured on `.dsh-claude-chat-wait` (height 24 px):

| Element | Measured | Source |
|---|---|---|
| Label | 14 px / 24 px sans 400 `--dsw-alias-label-secondary` (`#70686A` / `#BEB6B8`) | `chat-wait.css:485-487` |
| Label box | `padding: 8px 0; margin: -8px 0` — room for the swap's 8 px travel | `shared/swapping-text.css:27-40` |
| Clock | 13 px, `font-variant-numeric: tabular-nums`, `--dsw-alias-label-caption`, `margin-left: 8px` | `chat-wait.css:497-501` |
| Overtime badge | 11 px / 16 px, `--dsw-alias-state-warn-label` on 16 % of it, radius 5 px, `padding: 0 6px`, `margin-left: 8px` | `chat-wait.css:504-517` |
| Loader → label gap | 6 px (loader's `margin-right`) | `chat-wait.css:124` |

Live warn colour is **`#DD8629`** (`rgb(221,134,41)`), not `#FAB219` as doc 06 §1.8 and §2
state; the 16 % wash is `color(srgb .8667 .5255 .1608 / .16)`. Doc 06's `#fab219` is stale
for this build.

**What ours does differently.** `ClaudeStatusLine.swift:193-224` builds three 4 pt dots with
`.orange` (`#CC5C3B`), `HStack(spacing: 3)` in an 18 × 14 frame, a 0.5 s `sin` lift of 7 pt
and a y-squash of 0.35 — a reasonable bounce, but: wrong colour, wrong stagger (constant
0.4 of a period instead of 2/5 and 3/5), only one lane (no line/orbit rotation), and the dots
are in an `HStack` so their x positions are 0/7/14 by layout rather than the exact
`left:` values. `ClaudeStatusLine.swift:117-124` puts the label 6 pt after the loader (right)
and the clock at 13 pt monospaced with 2 pt leading padding and `captionInk` (right), but the
clock should be **13 pt tabular sans with an 8 pt leading margin** — our
`.monospaced` also changes the face, which DSH does not do.

---

## 3. Status-line wording, timing and sweep

### 3.1 The strings

The complete set the line can say (`features/chat-wait/chat-wait.copy.json:2-9`):

| key | EN | ZH |
|---|---|---|
| `chatWaitThinking` | `Thinking…` | 正在思考 |
| `chatWaitWriting` | `Writing…` | 正在写回答 |
| `chatWaitToolCall` | `Preparing a tool call…` | 正在准备工具调用 |
| `chatWaitTools` | `Running tools…` | 正在调用工具 |
| `chatWaitReading` | `Reading {file}` | 正在读取 {file} |
| `chatWaitEditing` | `Editing {file}` | 正在编辑 {file} |
| `chatWaitWritingFile` | `Writing {file}` | 正在写入 {file} |
| `chatWaitOvertime` | `No response yet` | 暂未响应 |

There is **no** whimsical verb list. Doc 06 §2 is correct here. What doc 06 underplays is the
**precise** mode, which this instance has on: the line then also writes *the model's own
words*, not just the fixed copy (`shared/turn-activity.ts:85-99,120-137`):

- a started file call → `Reading <file>` / `Editing <file>` / `Writing <file>`, where `<file>`
  is the tool's path (`shared/turn-activity.ts:70-75,122-124`; `shared/file-tool.ts`);
- a started shell call → the call's own `description` argument, first line, whitespace
  collapsed, **first letter capitalised** (`shared/turn-activity.ts:111-119`);
- reasoning → the clause the model is on, e.g. "I am checking the file is true", read off the
  tail of the newest reasoning block (`shared/activity-phrase.ts:20,160-173`).

Observed live in one turn (in order): `Thinking…` → `Preparing a tool call…` →
`List files in the current working directory` → `Reading build.js` →
`List contents of the project directories` → `Reading package.json` → `Thinking…` →
`Inspect the start of file.html to understand its purpose` → `Writing…`.

Which state wins (`shared/turn-activity.ts:85-99`): newest block is reasoning → thinking (or
the clause); newest block is a tool call being drawn up → preparing; calls running with
nothing of their own → running tools; anything else readable → writing; nothing readable →
null, and the line falls back to the host's word — which under the Claude brand is the skin's
`Thinking…` (`shared/turn-activity.ts:55-68`).

### 3.2 Timing

- A wording that gets written is **locked for 1000 ms** (`WORD_LOCK_MS`,
  `features/chat-wait/wait-state.ts:37-45,92-105`).
- The pass runs at most every **250 ms**, plus on host publishes (`TICK_MS`,
  `features/chat-wait/chat-wait.ts:72`).
- A call's own words ("Reading build.js") may not be lost to the lock; they wait for it and
  are written first when it ends (`wait-state.ts:75-105`).
- The model's own clause is held across the gaps between clauses (`wait-state.ts:96-100`).
- Clock: `Math.max(1000, now − start)` ticked every 250 ms; the wait counts from the moment
  the move went back to the model, not from the turn's first message
  (`features/chat-wait/wait-state.ts:10-25`).
- `No response yet` after **10 000 ms** with no readable activity (`WAIT_OVERTIME_MS`,
  `wait-state.ts:10-11`).

### 3.3 Wording swap

Old words leave upward through a 2 px blur, new words enter from below:
**150 ms per half, 50 ms gap, 8 px travel, 2 px blur, `ease-in-out`**, applied as a
transition on `transform / filter / opacity` (`shared/motion.css:10-17`,
`shared/swapping-text.css:61-90`, `tokens.json:1356,1366`). The label's *width* is pinned and
animated on the slide token (240 ms, `ease-glide`) wherever the swap changes the width
(`swapping-text.css:27-40`).

### 3.4 The highlight sweep (confirmed, with the real numbers)

Measured off the live band element inside the label:

```
animation: 1.5s steps(48, end) 0.3s infinite dsh-claude-sweep-window
mask-image: linear-gradient(105deg, transparent 0%, #000 40% 60%, transparent 100%)
color: #161616            /* light; #FDFDFD dark — the band's tint */
transform: translateX(-69.02px)   /* one label width, then back */
```

The glyph copy on top runs the opposite way and carries the same text, so the tinted letters
stand exactly over the real ones and only the mask moves (`shared/motion.css:102-116,
158-178`; band tint = `--dsw-alias-label-shimmer`, `tokens.json:827-834`). The keyframes rest
over the last third of each pass (`66.6667% → 100%` hold), which is the visible pause between
sweeps. Reduced motion removes the band entirely (`shared/motion.css:225-227`).

Doc 06 §2's "1500 ms, `steps(48, end)`, 300 ms delay" is confirmed. What doc 06 does not say,
and what matters for a rebuild: **the band paints a duplicated glyph run, not the original
text's background**, and its tint is the *ink* colour, not the accent.

**What ours does differently.** `ClaudeStatusLine.swift:162-190` (`ClaudeSweepText`) overlays
`ClaudePalette.ink.opacity(0.85)` through a mask of the same `Text`, using a symmetric
`linear-gradient` with stops at `phase ± 0.25` and a raw 1.5 s linear phase — no `steps(48)`,
no 300 ms delay, no last-third rest, and no second counter-moving layer. Visually it reads as
a soft blob crossing the words rather than DSH's stepped shimmer. The wording model itself
(`ClaudeStatusLine.swift:8-70,143-160`) matches the eight states and the 1 s lock/tick well,
but it never produces the precise-mode strings (file names, command descriptions, reasoning
clauses) — it maps every reasoning row to `Thinking…` and every unknown call to
`Running tools…` (`ClaudeStatusLine.swift:30-70`).

---

## 4. Composer

Two variants exist. On a new-session/home page it is the "hero" card; inside a conversation
it is the "inline" bar, and **they are different components with different paint**. Ours is
modelled on the hero card, so the conversation view is the one to fix.

### 4.1 In-conversation (inline) — measured

| Part | Light | Dark | Source |
|---|---|---|---|
| Outer card `[data-composer-card]` | transparent, no border, no shadow, radius 18 | transparent, no border, no shadow, radius 18 | `composer/inline.css:14-35` — measured |
| The painted bar (`[data-input-scroll]`) | `background: #FFFFFF`, `1px solid #E9E9E9`, `border-radius: 14px`, `box-shadow: 0 1px 3px rgba(20,20,19,0.03)` | `#141414`, `1px solid rgba(255,255,255,0.09)`, `0 1px 3px rgba(0,0,0,0.15)` | `composer/inline.css:204-225,235-244`; measured |
| Bar padding | `7px 36px 7px 14px` | same | measured (the 36 px right is the send button's lane) |
| Bar min / max height | 38 px / 180 px | same | `inline.css:209-211` |
| Focus ring | border `rgba(20,20,19,0.18)`, shadow `0 0 0 1px rgba(20,20,19,0.065), 0 4px 12px rgba(20,20,19,0.025)` | border `rgba(250,249,245,0.22)`, shadow `0 0 0 1px rgba(250,249,245,0.09), 0 4px 16px rgba(0,0,0,0.20)` | `inline.css:267-277`; measured |
| Input text | 14 px / 24 px sans, `#161616` | 14 / 24, `#FDFDFD` | measured |
| Placeholder | `Type / for commands`, `--dsw-alias-label-caption` (`#B2ACAD` / `#776F71`), 14 px / 24 px, inset `4px 8px auto 14px` | same | copy `composer/composer.copy.json:8`; host `.uV2eYG_placeholder`; measured |
| Toolbar row | on the canvas under the bar, no plate: `Accept edits` 13 px ink, `+` 24 × 24 7 px radius, model/effort 14 px ink at `opacity: 0.72`, context ring 14 px | same, ink `#FDFDFD` | measured; `composer/card.css:156-159,218-222` for the 7 px / 14 px trigger face |
| Send | 26 × 26, radius 6 px, transparent, no border; glyph = 16 × 16 mask `M8 3.75h5.25v7H3M6 7.75l-3 3 3 3` in `currentColor` | same | `composer/inline.css:333-398`; measured |
| Send, empty draft | ink **caption** `#B2ACAD` (dark `#776F71`), no plate, `opacity` on the host control 0.4 | same | measured; host `.uV2eYG_primary:disabled{opacity:.4}` |
| Send, with text | ink **primary** `#161616` / `#FDFDFD`, still no plate, no fill | same | `inline.css:393-398` |
| Send, hover | plate `--dsh-claude-hover-bg` = `rgba(6,6,6,0.08)` / `rgba(255,255,255,0.08)`, ink primary | same | `inline.css:388-392` |
| Stop (while running) | bare ink ring + filled square, transparent plate, hover plate 8 % | same | `inline.css:399-445` |

The conversation composer is **flat**: a 14 px-radius white/barely-dark bar with a hairline
and a whisper of a shadow, sitting on the canvas with its toolbar underneath, no second tray,
no 27 px capsule.

### 4.2 Hero card (home page only) — for contrast

- `border-radius: 18px`, `1px solid --dsw-alias-border-l1`, `background:
  --dsw-specific-input-major` (`#FFFFFF` / `#141414`), `padding: 8px 0 2px`, gap 8
  (`composer/card.css:10-21,82-90`).
- Shadow light `0 4px 12px rgba(20,20,19,0.04), 0 1px 3px rgba(20,20,19,0.02)`; dark
  `0 4px 12px rgba(0,0,0,0.30), 0 1px 3px rgba(0,0,0,0.15)` (`card.css:82-90`).
- Field `min-height: 86px`, placeholder "How can I help you today?"
  (`card.css:23-32`, `composer.copy.json:7`).
- Focus: border `rgba(20,20,19,0.18)` + `0 0 0 1px rgba(20,20,19,0.065), 0 6px 18px
  rgba(20,20,19,0.03), 0 2px 6px rgba(20,20,19,0.015)`; dark inverts to a bright ivory rim
  `rgba(250,249,245,0.22)` + `0 0 0 1px rgba(250,249,245,0.09)` (`card.css:99-107`).

### 4.3 "How typed text appears smoothly": the drawn caret

Typed characters appear instantly; there is **no per-character animation in the composer.**
The smoothness is a **custom 2 px caret** the skin draws and drives:

- The native caret is made transparent on the input (`caret-color: transparent`,
  `features/caret/caret.css:9-14`), and a `<div data-dsh-claude-caret-layer>` is positioned
  absolutely over the field (`caret.css:26-54`).
- **2 px wide**, `background: var(--dsh-claude-caret-color, …)`, and the live value is the
  brand accent **`#D97757`** (`caret.css:32,44`; measured
  `--dsh-claude-caret-color: rgb(217,119,87)`).
- Height is the measured line box of the caret's break (17 px at 14 px / 24 px text), set
  inline as `height: 17px` (`features/caret/caret-measure.ts:334-343`,
  `features/caret/caret.ts:332`).
- Position: `transform: translate(x, y)` with **`transition: transform 80 ms ease`** — the
  caret *glides* between insertion points instead of jumping
  (`--dsh-claude-duration-instant` 80 ms, `tokens.json:1005-1008`; `--dsh-claude-ease-standard`
  `ease`, `tokens.json:1275`; `caret.css:45`).
- Blink: `animation: dsh-claude-caret-blink 1s step-end infinite` with `50% { opacity: 0 }`,
  i.e. 500 ms lit / 500 ms dark (`--dsh-claude-period-blink`, `tokens.json:1238-1240`;
  `caret.css:49,56-58`), restarted on each keystroke so the caret is always lit while you
  type.
- Reduced motion: no glide, no blink (`caret.css:60-68`).
- (The only other text-reveal animation in the product is on incoming *assistant* prose: a
  24-step per-character fade over 120 ms with a ~2.4 ms stagger, painted through CSS
  `::highlight()` ranges — `features/chat-reveal/reveal-params.ts:10-20`,
  `constants.ts:279-283`. It is not on the composer.)

**What ours does differently.** `ClaudeChatView.swift:352-417` uses a stock `TextField` with
`.font(.system(size: 18))` (DSH: 14 sans), `.tint(ClaudePalette.ink)` — so the caret is
near-black and system-drawn, not the 2 px accent caret with an 80 ms glide. The card is a
27 pt-radius capsule filled with `ClaudePalette.composer` (0.99 / 0.19) and a 0.7 pt border
(`ClaudeChatView.swift:408-414`), where DSH's conversation bar is a 14 pt-radius white /
`#141414` bar with a 1 px hairline and `0 1px 3px` shadow; there is no focus rim in ours
beyond the border colour. The placeholder is "Message the agent, tag @files…" in
`secondaryInk` (`ClaudeChatView.swift:363`); DSH says **"Type / for commands"** in caption
ink. The send button is a filled orange circle with a white `arrow.up`
(`ClaudeChatView.swift:396-405`) — DSH's is a bordered-less 26 pt transparent square with a
16 pt return-arrow glyph in caption ink (empty) / primary ink (typed) and an 8 % plate only on
hover. No caret animation exists on our side at all.

---

## 5. The palette actually used on the chat page

All values read from computed custom properties and from computed element colours in each
theme, then matched to the reference. Chat page only; the sidebar tokens are omitted.

| Role | Light | Dark | Source |
|---|---|---|---|
| Canvas / body | `#FFFFFF` | `#191919` | `tokens.json:82-85`; `typography.css:71-73` |
| Prose ink | `#161616` | `#FDFDFD` | `--dsw-alias-label-primary`, `docs/STYLE.md:160-164` |
| Secondary ink | `#70686A` | `#BEB6B8` | `--dsw-alias-label-secondary` |
| Tertiary ink | `#91888A` | `#9C9395` | `--dsw-alias-label-tertiary` |
| Caption ink | `#B2ACAD` | `#776F71` | `--dsw-alias-label-caption` |
| Shimmer band tint | `#161616` | `#FDFDFD` | `--dsw-alias-label-shimmer`, `tokens.json:827-834` |
| User bubble | `#F4F2F3` | `rgba(255,255,255,0.06)` | `tokens.json:90-93` |
| Card / code-block surface | `#FFFFFF` | `#212121` | `--dsw-alias-markdown-code-block` (computed) |
| Composer bar | `#FFFFFF` | `#141414` | `--dsw-specific-input-major` |
| Border l1 (cards, composer) | `#E9E9E9` | `rgba(255,255,255,0.09)` | `--dsw-alias-border-l1` |
| Border l2 (ghost send, chips) | `#DEDEDE` | `rgba(255,255,255,0.18)` | `--dsw-alias-border-l2` |
| Border l3 | `#CFCFCF` | `rgba(255,255,255,0.30)` | `--dsw-alias-border-l3` |
| Divider (0.5 px) | `rgba(22,22,22,0.05)` | `rgba(255,255,255,0.06)` | `--dsh-claude-divider` |
| Accent / brand | `#D97757` | `#D97757` | `tokens.json:81` |
| Hover plate | `rgba(6,6,6,0.08)` | `rgba(255,255,255,0.08)` | `--dsh-claude-hover-bg` (computed) |
| Hover plate, solid | `#F4F4F4` | `#323232` | `--dsw-alias-interactive-bg-hover-solid` |
| Active plate | `rgba(246,136,98,0.26)` | `rgba(217,119,87,0.30)` | `--dsw-alias-interactive-bg-active` |
| Warn label (overtime badge) | `#DD8629` | `#DD8629` | `--dsw-alias-state-warn-label` (computed) |
| Error | `#EC1313` | `#F25A5A` | `--dsw-alias-state-error-primary` |
| Prose link | `#184F95` | `#8AB4F8` | `tokens.json:94-97`; measured |
| Inline code fill | `rgba(6,6,6,0.05)` | `rgba(255,255,255,0.05)` | `--dsh-claude-inline-code-bg` (measured) |

Notes that bit us:

- **Canvas is pure white / `#191919`.** Not `#FAFAFA`; that is the *sidebar* (`tokens.json:86-89`).
- **`--dsw-alias-link` (`#BF6446` / `#EAA088`) is not the prose link colour.** Markdown anchors
  use the palette card's `link` (`#184F95` / `#8AB4F8`) through `--dsh-claude-link`
  (`tokens.json:776-780`; `typography.css:255-294`). Two different "links" exist; the warm one
  is UI chrome.
- **The warn label is `#DD8629`**, not doc 06's `#FAB219`.
- The dark card is *not* a lighter panel: it is the canvas with a 1 px translucent-white
  border. There is no `#212121` card fill in the process group (that token is for code blocks).

**What ours does differently.** `ClaudeStyle.swift:15-88` is close but off on the values a
user actually sees side by side: canvas light `0.976,0.976,0.969` (`#F9F9F7`, slightly
green-yellow) vs `#FFFFFF` (`ClaudeStyle.swift:16-19`); dark canvas `#141414` vs `#191919`
(same lines); ink `0.13`/`0.93` (`#212121`/`#EDEDED`) vs `#161616`/`#FDFDFD`
(`ClaudeStyle.swift:22`); user bubble `0.92`/`0.165` (`#EBEBEB`/`#2A2A2A`) vs
`#F4F2F3`/`rgba(255,255,255,0.06)` (`ClaudeStyle.swift:71`); panel `#FFFFFF`/`#212121`
(`ClaudeStyle.swift:19`), where DSH's card is transparent; warning `#FAB219`
(`ClaudeStyle.swift:76`) vs `#DD8629`; accent `#CC5C3B` (`ClaudeStyle.swift:29`) vs
`#D97757`. The four ink tokens, the divider and `cardBorder` (`ClaudeStyle.swift:34-68`) are
correct.

---

## 6. Assistant prose typography

Measured in a real answer and on freshly injected headings inside the live markdown container
(inject → read computed → remove).

| Role | Family | Size / line-height | Weight | Other |
|---|---|---|---|---|
| Markdown container | `Anthropic Serif Web Text` (fallback: Noto Serif, Georgia) | 14 / 23 px | 400 | `--dsh-claude-font-prose`, `typography.css:90-93`; citations `docs/STYLE.md:160-164` |
| Paragraph | serif | 14 / 23 | 400 | `margin: 12px 0` (`typography.css:97-99`) |
| h1 | serif | 21 / 30 | 700 (display 500 for skin headlines) | `margin: 24px 0 12px`, letter-spacing −0.015 em |
| h2 | serif | 18 / 26 | 700 | `margin: 8px 0 12px`, −0.01 em (live answer used this) |
| h3 | serif | 16 / 24 | 700 | `margin: 8px 0 12px`, −0.01 em |
| h4 | serif | 14 / 24 | 600 | `margin: 16px 0 8px` |
| List item | serif | 14 / 23 | 400 | `ul/ol`: `margin: 16px 0`, `padding-left: 18px` |
| `strong` | serif | 14 / 23 | 600 | |
| `em` | serif | 14 / 23 | 400 italic | |
| Blockquote | serif | 14 / 23, `#70686A` / `#BEB6B8` | 400 | wash `rgba(20,20,19,0.04)` light / `rgba(250,249,245,0.06)` dark, `padding: .6em 1em`, radius `0 8px 8px 0` |
| Inline code (prose) | `Anthropic Mono Web` | 13 / 15.6 | 400 | fill `rgba(6,6,6,0.05)`, radius 4, padding 1 px |
| Inline code (inside a thought) | mono | 12 / 14.4 | 400 | same fill/radius, smaller |
| Code block `pre > code` | mono | 13 / 23 | 500 | `margin: 16px 0`, `overflow-x: auto`; block surface `#FFFFFF` / `#212121` |
| `hr` | — | — | — | 1 px `rgba(22,22,22,0.05)`, `margin: 22.4px 0` |
| Link | serif | 14 / 23 | 500 | `#184F95` / `#8AB4F8`, underline, `margin: 0 -3px`, 2 px transparent border (hover plate) |
| Table th / td | serif | 14 / 23 | 700 / 400 | 1 px cell padding |

Paragraph spacing is **12 px between blocks** in conversation prose and **4 px between
paragraphs inside a thought** (`typography.css:97-105`) — a difference worth keeping, because
a thought must read denser than the answer. There is no first-line indent and no drop cap.

Where the serif appears in UI chrome: exactly where an element carries
`data-dsh-claude-part="text-title"` — the counted summary, the "Think" header of an opened
thought, and a shell call's verb. Everything else in the chrome (composer, clock, badge,
sidebar, "Completed in 7s") is **`Anthropic Sans Web Text`** at 13–15 px. Code is
`Anthropic Mono Web`.

**What ours does differently.** `ClaudeChatComponents.swift:148-171` renders prose with
`ClaudeMarkdownTheme(serifName:bodySize: 18)` — **18 pt body at ~6 pt line spacing** where DSH
is 14 px with a 23 px line (i.e. ~1.64). `blockSpacing = 14` vs DSH's 12. The user bubble is
18 pt with 14 pt vertical padding and a 28 pt radius
(`ClaudeChatComponents.swift:130-142`), where DSH's is **14 px / 22 px, `padding: 10px 16px`,
radius 20 px** (host `._bubble_1sgyj_1`; measured). Links are `ClaudePalette.orange`
(`ClaudeChatComponents.swift:164`) instead of the blue palette link. Inline code uses
`codeBackground = 0.98/0.04` (`ClaudeStyle.swift:18`) rather than the 5 % ink wash.

---

## 7. The mascot (Clawd crab)

### 7.1 Where it shows, and how big

- One `<span class="dsh-claude-crab">` mounted in the composer's anchor
  (`[data-dsh-claude-crab-anchor]`), `position: absolute`, `z-index: 1`,
  **104 × 72 px**, `right: 0`, `bottom: 100%` — feet on the top edge of the composer card
  (`features/mascot/crab.css:14-26`).
- In a conversation the anchor is the whole column, so the crab is set in from the card's
  right edge: `right: max(16px, (100% − card-max-width) / 2)` (`crab.css:32-34`).
- Measured at 1440 px: frame at `x 1137.2, y 695, 104 × 72`, i.e. its right edge exactly on the
  composer card's right edge (1241.2) and its bottom exactly on the card's top (767). In the
  dark screenshot the feet sit on the rounded 14 px corner's top edge.
- Sprite window: `left: var(--x) * 2px; top: var(--y) * 2px; width: var(--w) * 2px;
  height: var(--h) * 2px`, `overflow: hidden` (`mascot-frame.css:43-50`). Live for `idle`:
  window 48 × 32 at (48, 40) inside the 104 × 72 frame.
- Strip: `image-rendering: pixelated`, width `cell-w × columns × 2`, background-image = the
  sheet as a **data URI** (`mascot-frame.css:56-63`; `scripts/build.mjs:411-420`). Live `idle`:
  `--dsh-claude-mascot-cell-w: 26`, `columns: 8`, so a 416 px strip, and the frame is chosen by
  translating the strip in −52 px steps (`transform: matrix(1,0,0,1,-54,-2)` … `-106` …
  `-210` sampled at 120 ms intervals).
- Pointer window (only the resting body takes it): `left: 48px; top: 40px; width: 48px;
  height: 32px` (`crab.css:58-67`). Other states are inert.
- Hidden (`visibility: hidden`) until the first sheet frame is ready (`mascot-frame.css:10-14`).

### 7.2 Assets

`packages/assets/src/mascot/crab/` — one colour sheet and one ink-mask sheet per animation,
both inlined as data URIs at build time:

`idle`, `idle-look`, `idle-wave`, `idle-laptop`, `thinking`, `typing`, `music`, `conducting`,
`building`, `error`, `happy`, `notification`, `compacting`, `sleeping`, `waking`, `poke-left`,
`poke-right`, `tickle`, `drag`, plus `crab-laptop-body.png` / `crab-laptop-ink.png`
(`features/mascot/sheets.ts:60-110`; `LICENSE:49-56`).

- The colour sheet is drawn on a **52 × 36 cell grid, 2 px per cell**. Palette, sampled from
  `thinking.png`: shell **`#D97757`**, shaded side **`#B9603F`**, eyes **`#141413`**. The ink
  mask is filled with `--dsw-alias-label-tertiary` (`#91888A` / `#9C9395`) so props (the sign,
  the wand, the "Z"s, the laptop) stay a quiet grey on either canvas
  (`crab.css:48-56`; measured pixels).
- Frame pace: **80 ms** (`CRAB_FRAME_MS`, `sheets.ts:75`). Crop boxes per animation:
  `sheets.ts:84-110` — e.g. `idle [24,20,24,16]`, `thinking [20,0,30,36]`,
  `typing [15,22,28,14]`, `happy [18,6,34,30]`, `sleeping [18,1,31,35]`. Each has a `still`
  frame index for reduced motion.
- Facing: at rest the crab faces the reader; in a state with something to look at it turns
  toward it (`docs/STYLE.md:938-947`) — not something the live screenshots can prove per
  frame, so treat it as source-only.

### 7.3 State → animation, observed live

One turn, sampled every 250 ms while the crab was on screen (each line is a transition):

```
sleeping → thinking → typing → thinking → typing → thinking → typing → thinking → typing
→ thinking → typing → … → happy → idle
```

- `thinking` ↔ `typing` alternated as the turn moved between reasoning (phase `thinking`) and
  tool calls (phase `working`), exactly as `mascot-signals.ts:94-96` + `working()`
  (`mascot-signals.ts:59-61`) say; `MIN_SHOW_MS = 1000` is what keeps it from flickering
  (`mascot-stage.ts:50`).
- At the end of the turn: **`happy`** for 5.2 s (`MOMENTS.attention.holdMs`,
  `mascot-stage.ts:57-60`) and then **`idle`**.
- The first sample of that turn was already `thinking`: the crab had been `sleeping` before
  the prompt, and going from `sleeping` to work is a direct switch (the `waking` animation
  belongs to the *idle* path only: `mascot-stage.ts:133-144`).
- Left alone, the crab went `sleeping` again: the quiet spell is **60 s** (`SLEEP_AFTER_MS`,
  `mascot-stage.ts:52`), and idle extras are picked every **20–40 s** from
  `idle-look`/`idle-wave`/`idle-laptop` (`EXTRA_MIN_MS`/`EXTRA_SPAN_MS`,
  `mascot-stage.ts:54-56,139-143`).
- Crop boxes matched the table live: `thinking` window 60 × 72 at (40, 0) — `[20,0,30,36]`;
  `typing` 56 × 28 at (30, 44) — `[15,22,28,14]`; `happy` 68 × 60 at (36, 12) — `[18,6,34,30]`;
  `idle` 48 × 32 at (48, 40) — `[24,20,24,16]`; `sleeping` 62 × 70 at (36, 2) — `[18,1,31,35]`.
- The full priority table in doc 06 §3.2 is confirmed by `mascot-signals.ts:69-97`,
  `mascot-stage.ts:57-62`: reaction 10, error 8 (4.8 s), notification 7, compacting 6,
  happy/attention 5 (5.2 s), subagents 4 (`music` / `conducting`), working 3 (`typing` /
  `music` / `building` by busy count), thinking 2, idle 1.
- Mascot hover bubble: 250 ms to open, pixel face, DeepSeek balance + conversation cost
  (`features/mascot/mascot-bubble.ts:16`). It did **not** open while the crab was `sleeping`,
  which is consistent with "only the resting body takes the pointer" (`crab.css:58-67`); not
  re-tested in `idle`, so that one stays source-only.

### 7.4 What our code has

Nothing in `Packages/PaseoUI/Sources/PaseoUI/Chat/`. The only mascot-shaped thing in the repo
is a static `SleepingCodeMascot` Canvas in `ClaudeCodeDraftView.swift:171-198` — a 64 × 60
hand-drawn sleeping crab in `Color(red: 0.82, green: 0.45, blue: 0.32)` and
`Color(white: 0.54)`, no animation, no state machine, not on the chat page, and not driven by
the turn at all. If we want the mascot, everything above is new work; the geometry in §7.1 is
enough to place it, and the crop boxes in §7.2 are enough to drive a strip player.

**Licensing note (unchanged from doc 06 §4):** the crab is Anthropic's character and the
plugin grants no right to reuse its frames; reimplementing the geometry/state machine is fine,
copying the PNGs is not.

---

## 8. Corrections this pass makes to doc 06

1. **§1.4, "No icon leads a row":** false for shell/tool rows. They keep a 14 × 14 tool icon in
   a 16 × 16 leading seat and swap it for a 14 × 14 chevron on hover; they have no trailing
   chevron, and they are **24 px** tall, not 36.
2. **§1.4/§1.2 row heights:** only disclosure rows (thought/file) are 36 px; the card mixes
   36 px and 24 px rows.
3. **Row gap:** there is a **4 px gap** between row boxes (host `--dsh-chat-flow-gap`) on top
   of the 0.5 px divider; the skin's `margin-top: 0` loses the cascade (measured 4 px).
4. **§1.4 "the header with its counted line stays above the card":** the collapsed summary's
   leading glyph is the *activity icon*, not a chevron; the chevron appears on hover, and is
   `chevron-up` when the group is open. There is no trailing chevron on the summary.
5. **§1.9/§2 warn colour:** `#DD8629`, not `#FAB219`.
6. **§2 missing:** the precise-status mode (file names, command descriptions, reasoning
   clauses) is on in this instance; the line is not limited to the eight fixed strings.
7. **§1.9 dark canvas:** `#191919` (right); but the *card* in the process group is
   transparent, not `#212121` — the light `#FFFFFF` canvas is what the card sits on.
8. **§5.1:** the 18 px, shadowed, white composer card is the **home/hero** variant. In a
   conversation the composer is a 14 px-radius bar (`#FFFFFF` / `#141414`, 1 px hairline,
   `0 1px 3px`) with the toolbar on the canvas underneath, and the send button is a bare
   return-arrow glyph, not a filled circle.
9. **§5.4/§1.7 aspect:** the drawn caret (2 px, accent, 80 ms glide, 1 s step-end blink) is a
   visible part of "typing feels smooth" and was not in doc 06 at all.
10. **§2 swap:** add the label's pinned-width transition (240 ms, `ease-glide`) and the
    `--dsh-claude-label-shimmer` tint on the band (ink, not accent).
