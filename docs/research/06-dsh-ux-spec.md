# dsh-claude-style → native iOS: UX and mascot spec

Date: 2026-11-08 · Source repo: `dsh-claude-style` at `/home/paseo/dev/dsh-claude-style-reference` (all paths below are relative to that root; `docs/STYLE.md` is the design-token reference, and the values marked "generated" there come from `packages/client/src/theme/tokens.json`). This is a behavioral specification for reproducing the conversation UX and the mascots in a native SwiftUI client backed by a different backend. It is not code.

Citation note: every claim carries `path:line`. Shorthand resolves within this document as follows: bare `tokens.json` = `packages/client/src/theme/tokens.json`; `STYLE.md` = `docs/STYLE.md`; `LICENSE` = the root `LICENSE`; `dom.ts` = `packages/contracts/src/dom.ts`; §1 files beside marked paths = `packages/client/src/features/chat-fold/` and, where named, `features/process-column/`, `features/message-actions/`, `features/sidebar-status/`, `features/composer/` and `theme/`; §2 = `packages/client/src/features/chat-wait/` and `shared/`; §3 = `packages/client/src/features/mascot/` and `scripts/`; `chat-follow.ts`/`chat-follow.css` = `packages/client/src/features/chat-follow/`; `lane.mjs` = `packages/testing/lane.mjs`. Where the skin leaves a thing to the host app (the DeepSeek Harness web GUI), that is said explicitly: the two implementations are not interchangeable, and reproducing the *host* is out of scope.


## 1. Turn layout

### 1.1 How an assistant turn is structured

A turn's adjacent process content — reasoning, tool calls, commands, file writes — is gathered by the host into one *process group*, opened/closed by the host's own inline control (`[data-step-process]`, header `[data-process-activity]`, body `[data-step-process-body]`, content `[data-step-process-content]`). The skin does not re-architect this; it renames the header's words and restyles the body.

- In the host's "compact" and "standard" detail tiers the group body **starts folded**; in the "detailed" and "fully-expanded" tiers the body is not capped and stays open throughout, and the skin leaves those tiers alone entirely (`packages/client/src/features/chat-fold/process-fold.ts:9-18`).
- The skin reads a group's phase off a `data-shimmer` attribute on its header: present while the process section still runs (`process-fold.ts:20-25`). Body visibility is the host's own `hidden` attribute (`hidden="until-found"` when folded, removed when open, `process-fold.ts:22-23`).
- "Took X seconds" / "Completed in Xs" is the **host's own** control at the end of a turn (`[data-turn-process]`, a button); the skin leaves it alone (`packages/testing/lane.mjs:26`). The skin only excludes its subtree from the chat area's entrance fade (`packages/client/src/features/chat-fold/fold-motion.css:34-43`). The exact wording is the host's locale string, not this repo's, and is not specified here.
- A stopped turn never gets an answer row; the host folds its groups itself at the end, and the skin opens the last one again so the work up to the stop stays on the page (`process-fold.ts:32-36`).
- The turn's final answer is plain prose rows; thinking rows are `[data-variant="think"]` (`packages/contracts/src/dom.ts:47`).

### 1.2 Default collapsed/expanded states, running vs finished

- **A running process group opens by default**; it folds back once the piece of work ends (the final answer is due) (`process-fold.ts:9-10`).
- Only the turn's **newest** group stays open while the model works; a closed group folds once a later group of the same turn or the turn's answer takes its place (`process-fold.ts:32-34`).
- A reader who touched a group keeps it in that phase (folded mid-run stays folded; opened mid-run stays open); the hand-over is per phase (`process-fold.ts:27-30`).
- **Thinking rows arrive collapsed** (the host's `ReasoningRow` pins `useState(false)`); the skin presses the row open while the model reasons and folds it back once the reasoning stops. The reader's own press wins per phase (`packages/client/src/features/chat-fold/reasoning-fold.ts:9-22`).
- A thinking row shows its text in a **replay window** while streaming: the text grows with the reasoning, and steps upward two lines at a time (on the snippet's 500 ms clock) once it reaches the cap (`fold-motion.css:100-109`; `--dsh-claude-reason-window-cap: 400px` at `fold-motion.css:103`; step token `--dsh-claude-duration-step` = 500 ms, `tokens.json:1121`). Edges are a mask, not gradients; fade 28 px (`fold-motion.css:111-114`). Two-line steps with an 840 ms hold between steps (`--dsh-claude-period-hold`, `tokens.json:1258`). Under Reduced motion the window is off entirely (`fold-motion.css:122-135`).
- After the turn ends: the answer row is not part of the process group. Under "next-input collapse" timing the latest turn stays open after it ends; the turn's non-final content gathers under the host's `[data-turn-process]` header (`process-fold.ts:41-46`).
- A too-tall **user message** (pasted logs) is clamped to 320 px with a 40 px bottom fade and gets a skin toggle "Show the whole message / Show less" under it (`packages/client/src/features/chat-fold/message-fold.css:14-30`; `message-fold.ts:38,134-135`; copy `chat-fold.copy.json:15-16`). The host renders user messages whole; no host fold exists.

### 1.3 The "N thoughts, M tool calls" counted header

The host's header shows its own list of activities; the skin replaces it with a counted summary at the end of the same control, and the iOS client should copy the skin's wording:

- English full form, singular/plural: `{count} thought` / `{count} thoughts`, `{count} output` / `{count} outputs`, `{count} tool call` / `{count} tool calls`, `{count} record` / `{count} records` (`chat-fold.copy.json:6-13`). Separator between figures: `, ` (`chat-fold.copy.json:14`; `process-summary.ts:73` `FULL_SEPARATOR`).
- Compact form (narrow header): `Thinking×{count}`, `Output×{count}`, `Tools×{count}`, `Records×{count}` with ` · ` separator (`chat-fold.copy.json:2-5`; `process-summary.ts:75`; order of figures is thinking, output, tool, record — `process-summary.ts:32` `FIGURES`).
- Which form stands is measured, not guessed: the sentence stands while its natural width fits the header's room; otherwise the compact figures stand (`process-summary.ts:127` `summaryForm`). The measurement cache is capped at 512 entries (`process-summary.ts:206`).
- Each count rolls in place: the sizer holds the width; the old digit leaves upward while the new one rises, 160 ms on the roll curve (`fold.css:51-78`; `--dsh-claude-duration-roll: 160ms`, `tokens.json:1083-1084`; `--dsh-claude-ease-roll: cubic-bezier(0.4, 0, 0.2, 1)`, `tokens.json:1305`).
- The summary is `aria-hidden`; the accessible name is the sentence (`process-summary.ts:247,464`).
- While the group still runs, the header sweeps with the host's highlight band (1500 ms period, `steps(48, end)`, 300 ms delay; `tokens.json:1175-1186`), and the figures on the band stand settled (`fold.css:92-103`).
- Under the Reduced choice, digits are set at once and the band stands down (`fold.css:100-110`, `data-dsh-claude-motion="reduced"`).

### 1.4 Individual thinking and tool-call blocks (column layout)

The skin offers two body layouts; the column layout is Claude Code's and is the one to reproduce:

- The open group's body becomes one card: 1 px card border, 8 px radius (ladder), the host's own cap where the host caps it (`min(400px, 50vh)`), and the card grows with its rows otherwise (`docs/STYLE.md:795-802`; `packages/client/src/features/process-column/process-column.css:13-21`).
- Each row is one line, min-height 36 px, inset 12 px horizontally, 0.5 px divider between rows (never above the first) (`process-column.css:26-36,49-53`; `docs/STYLE.md:796-798`).
- No icon leads a row. A row that opens has a 12 × 12 chevron **trailing** its words (mask-drawn, `margin-inline-start: 6px`), rotating 90° (down) while open, transitioning on the feedback timing (`process-column.css:84-99`).
- A folded thinking row is a fixed box the host sizes to its 24 px line; the skin restates the row height as `calc(36px + var(--dsh-content-font-delta, 0px))` (`process-column.css:56-60`).
- A response (output) row has no disclosure; it pads 8 px vertically (`process-column.css:38-41`).
- An opened row's details open inside the card under the row with 10 px padding-bottom (`process-column.css:62-65`).
- A trailing thinking row adds 6 px below its line, keeping room above the card's bottom edge (`process-column.css:43-47`).
- A thought reads as the thought itself; a generic tool call reads as its tool and purpose (kind word and separator set aside); a named call keeps its verb (e.g. `查找文件 · *.md`); a row with no description keeps its title (`docs/STYLE.md:805-808`; selectors `process-column.css:74-82`).
- The header with its counted line stays above the card, outside it (`docs/STYLE.md:808`).

### 1.5 Fold motion and body entrance

- Disclosed bodies fade/rise in on insertion: `@starting-style` gives `opacity: 0; translate: 0 -2px`; the transition is opacity + translate over 120 ms `--dsh-claude-duration-reveal` with `ease-out` (reveal token, `tokens.json:1016`) (`fold-motion.css:48-61`). There is no exit animation; the element unmounts in the same frame (`fold-motion.css:17-19`).
- The fold "door" (height roll) for the process group and thinking rows: 200 ms (`--dsh-claude-duration-move`, `tokens.json:1089-1090`), `ease-out`, driven by WAAPI `height` keyframes; the visible share of the duration is 0.9 and the remainder anchors the end (`fold-glide-parts.ts:18,27`; `fold-glide.ts:155-182`). A collapse is locked for its own 200 ms so two folds cannot pile up (`fold-glide.ts:83`). `!important` holds flex children at natural height only during the roll (`fold-motion.css:79-81`).
- Under Reduced motion, no door and no entrance fade (`fold-motion.css:66-68,127-135`).

### 1.6 Scrolling inside tool output

The skin keeps the host's scroll window rather than adding one of its own: an open group's body stands at `min(400px, 50vh)` where the host caps it, scrolling the group inside the card; where the host's tier lifts the cap, the card grows with its rows (`docs/STYLE.md:800-803`; `process-column.css:1-14`; `fold-motion.css:92-98`, quoting the same 400 px host cap). An opened thought scrolls with the group and holds no scrollbar of its own (`docs/STYLE.md:803`). Code blocks inside a group carry their own `overflow-x` (`chat-follow/process-follow.ts` context — `overflow-x: hidden` on the body, `packages/client/src/features/chat-follow/chat-follow.css:10-12`). Reasoning's own cap is 400 px (`fold-motion.css:103`). A user message taller than the column clamps at 320 px with the 40 px fade (`message-fold.css:14-27`).

### 1.7 Copy buttons

- The message row under a message (clock + copy) is host markup; the skin keeps it and keeps the user's own row's actions hidden until hover/focus (opacity 0 → 1, feedback timing) (`packages/client/src/features/message-actions/message-actions.css:1-17`).
- The skin's own added buttons (Retract, Edit) are 28 × 28 px, 6 px padding, inline-flex centered, `border-radius: var(--dsw-radius-sm)`, no border/background, icon 15 × 15 px, ink `--dsw-alias-label-tertiary`; hover: hover plate + `--dsw-alias-label-secondary` (`message-actions.css:25-47,49-51`).
- The host's copy button itself is retained as-is; there is no skin-specific copy affordance on assistant answers beyond the host's row.

### 1.8 Status dots and the running badge

- Sidebar session row: a running conversation shows a **6 px filled dot in muted neutral `#898781`** (light and dark), breathing opacity 0.3 → 1 → 0.3 once per 1200 ms (`--dsh-claude-period-status-breathe`, `tokens.json:1170-1172`; animation `sidebar-status.css:40-57`). An idle/read session shows nothing decorative; a 10 px ring is an alternate look the reader can pick (`sidebar.css:502-512`; `sidebar-status.css:53-57` for reduced/ring handling).
- Awaiting-input (approvals, plan reviews, questions): **yellow `#fab219`** (`tokens.json:734-737`). Unread/finished-in-background reminder: **blue `#2a78d6`** (`tokens.json:728-731`).
- Running session title shimmer (alternate indicator): a text-only sweep at 3000 ms (`--dsh-claude-period-status-title`, `tokens.json:1165-1167`), `cubic-bezier(0.45, 0, 0.55, 1)` (`--dsh-claude-ease-status-title`, `tokens.json:1290`), background-size 400 % with keyframes at 0 %/15 % → 85 %/100 % (`sidebar-status.css:59-95`); peak colour `--dsh-claude-status-title-peak`: light `color-mix(in srgb, var(--dsw-alias-label-primary) 45%, white)`, dark `#7b7974` (`tokens.json:49-54`).
- Overtime badge on the waiting line: "No response yet" (`chat-wait.copy.json:2`) appears once the model has been silent for 10 s (`packages/client/src/features/chat-wait/wait-state.ts:11`). It enters on a springy slide+pop (open: 250 ms `--dsh-claude-duration-open`, `ease-settle`, overshoot pop 500 ms `--dsh-claude-ease-spring`) and exits at 120 ms `--dsh-claude-duration-exit` (`chat-wait.ts` `syncBadge`; `chat-wait.css:504-551`; tokens `tokens.json:1050,1032`). Colour: host `--dsw-alias-state-warn-label` on a 16 % wash, 11 px type, radius 5 px, padding 0 6 px (`chat-wait.css:504-517`).

### 1.9 Palette and shape tokens (light / dark)

Claude card (default): canvas `#FFFFFF` / `#191919`, sidebar `#FAFAFA` / `#1F1F1F`, bubble `#F4F2F3` / `rgba(255,255,255,0.06)`, accent `#D97757`, link `#184F95` / `#8AB4F8`, code ink `#161616` / `#FDFDFD` (`docs/STYLE.md:78`). DeepSeek card: canvas `#FBFCFF` / `#13161D`, sidebar `#F7F9FF` / `#13161D`, bubble `#ECF0FF` / `#262B36`, accent `#4D6BFE`, link `#3B56D9` / `#8FA4FF`, code ink `#0F1115` / `#EEF1F8` (`docs/STYLE.md:79`).

Ink ladder (light / dark): primary `#161616` / `#FDFDFD`; secondary `--dsw-alias-label-secondary` = `#70686A` / `#BEB6B8`; tertiary `--dsw-alias-label-tertiary` = `#91888A` / `#9C9395`; caption `--dsw-alias-label-caption` = `#B2ACAD` / `#776F71` (`docs/STYLE.md:160-164`).

Borders: 1 px card/panel edges — light `--dsw-alias-border-l1` `#E9E9E9`, dark `rgba(255,255,255,0.09)` (a translucent white highlight, not a colour); l2 `#DEDEDE` / `rgba(255,255,255,0.18)`; l3 `#CFCFCF` / `rgba(255,255,255,0.3)` (`docs/STYLE.md:132-134`). Separators: `--dsh-claude-divider` `rgba(22,22,22,0.05)` / `rgba(255,255,255,0.06)`, drawn at **0.5 px** on lines that only separate (`docs/STYLE.md:135,295`).

Shapes: radius ladder 4 / 8 / 16 px; 12 px popover card with 6 px rows; pills for CTAs; 4 px spacing rhythm; 1 px borders, 0.5 px separators (`docs/STYLE.md:286-300`). Typography: headings serif display at weight 500, tracking −0.01em, line-height 1.25; body prose serif (Markdown) line-height 23 px, block margins 12 px (`docs/STYLE.md:17,278-283`; `typography.css:74-79`). Type sizes in the composer are scaled by the reader's interface-font scale.

Motion tokens that matter for the turn layout (ms): feedback 120; reveal 120; surface 150; exit 120; open 250; swap 150; swap-gap 50; move 200; roll 160; step 500; slide 240; fade 300; ease-glide `cubic-bezier(0.22,0.61,0.36,1)`; ease-out `ease-out`; ease-roll `cubic-bezier(0.4,0,0.2,1)`; ease-settle `cubic-bezier(0.22,1,0.36,1)` (`docs/STYLE.md:323` motion table; `tokens.json:1011-1095,1121,1258,1280-1310,1323-1328`). Reduced choice presses **every** animation/transition to 0.01 ms (`tokens.json:1159`).


## 2. Live status text while the agent works

There is **no whimsical verb list** ("Pondering…", "Frobnicating…" style). The waiting line shows one of a fixed set of states, plus the model's own words where the app can read them:

| State (copy key) | English | Chinese |
|---|---|---|
| `chatWaitThinking` | Thinking… | 正在思考 |
| `chatWaitWriting` | Writing… | 正在写回答 |
| `chatWaitToolCall` | Preparing a tool call… | 正在准备工具调用 |
| `chatWaitTools` | Running tools… | 正在调用工具 |
| `chatWaitReading` | Reading {file} | 正在读取 {file} |
| `chatWaitEditing` | Editing {file} | 正在编辑 {file} |
| `chatWaitWritingFile` | Writing {file} | 正在写入 {file} |
| `chatWaitOvertime` | No response yet | 暂未响应 |

(`packages/client/src/features/chat-wait/chat-wait.copy.json:2-9`.)

- Which state is shown is read off the open turn's newest block: reasoning → thinking; a tool call being drawn up → preparing; tools running → running tools; otherwise writing (`packages/client/src/shared/turn-activity.ts:85` `activityWords`). The precise choice (a "status detail" preference) additionally surfaces the file a call works on, the command call's declared `description`, or the clause the model's own reasoning is on; the simple choice shows the bare states only (`turn-activity.ts` header comment; `chat-wait.ts` `syncRow`).
- Under the DeepSeek brand the wait word is the host's own ("Deep diving", surfaced as a host locale string, `hostChatCopy('chat.deepDiving', …)`); under Claude it is the skin's "Thinking…" (`turn-activity.ts` `waitingWord`, `turn-activity.ts:66`). The brand picks one waiting word so the line never swaps between two words for the same wait.
- Timing: a wording written is **locked for 1000 ms** (`wait-state.ts:45` `WORD_LOCK_MS`); the pass runs at most every 250 ms (`chat-wait.ts:72` `TICK_MS`) and on host publishes; a wording that changed mid-lock waits for the pass after the lock, so a fast turn reads as one line rather than flicker (`wait-state.ts` `wordForPass`).
- **Shimmer**: the words wear either the host's highlight band swept across them (the host's own cadence: 1500 ms, `steps(48, end)`, 300 ms delay, `tokens.json:1175-1186`) or, by reader choice, a colour wash (seven radial washes orbiting the glyph box over a grey ramp; hue rotation 4000 ms, drift 5000 ms; `tokens.json:1211-1222`, `docs/STYLE.md:743-790`). The two paints are swapped via two keyframe paints in `packages/client/src/shared/motion.css:118-140`.
- **Wording swap animation**: old words leave upward through a 2 px blur while the new words enter from below, 150 ms each half, 50 ms gap, `ease-in-out`, travel 8 px (`tokens.json:1056-1063,1356,1366`; `packages/client/src/shared/swapping-text.css:29-72`). Under Reduced, the swap is instant and the band stands down (`packages/client/src/shared/swapping-text.css:95-103` reduced rules; `chat-wait.css:410-413` reduced rules for dots).
- **Loader dots** (Claude brand only; under DeepSeek the host's whale tail stands): three lanes — (a) three dots bounce and flatten against the floor (500 ms per bounce, `--dsh-claude-period-dot-bounce`, staggered 2/5 and 3/5 periods, `tokens.json:1264`); (b) three dots walk three lines through one point, a simple harmonic, shrinking to 55 % at the middle (`--dsh-claude-scale-dot-mid`, `tokens.json:1408`; 1250 ms per round trip); (c) four dots swap the corners of a 45 : 55 rectangle (2400 ms per turn). The lane in play rotates on a 10 s clock (`--dsh-claude-period-dot-rotate`, `tokens.json:1149`), each dot handed over at its own still moment, morph 480 ms (`--dsh-claude-duration-dot-morph`, `tokens.json:1154`) (`chat-wait.css:114-173,221-242,329-345,358-369,410-413`; `wait-loader.ts:420-445`).
- The line composition: loader (18 × 14 px box, 6 px right margin, dots 4 px, `bottom: 0`, accent colour) → wording (14 px, `--dsw-alias-label-secondary`) → clock (13 px, tabular figures, `--dsw-alias-label-caption`, 8 px left margin) → optional overtime badge (`chat-wait.css:114-126,148-156,486-503,504-551`).
- The running row is pinned sticky at the composer's height + 40 px fade band + 16 px transcript padding + 1 px, while the tail is followed and the reader is not scrolling (`chat-wait.css:40-44`).


## 3. The mascots

Three characters share one state machine and one sprite-strip window; they differ in assets, grid, and pacing.

### 3.1 Assets and formats

**Crab (Clawd)** — `packages/assets/src/mascot/crab/*.png`: one colour sheet and one *ink-mask* sheet per animation (e.g. `idle.png` + `idle-ink.png`), plus `crab-laptop-body.png` / `crab-laptop-ink.png`, which are frames of Claude Code's own animation (`LICENSE:49-56`). The mask is filled at runtime with the tertiary-label ink (`crab.css:48-57`). Sheets are **inlined into the bundle as data URIs** (`scripts/build.mjs:411-420`); no network fetch. Drawn after Anthropic's character by `scripts/draw-crab.py` (`LICENSE:49-56`; `scripts/draw-crab.py` header).

**Deepy** — `packages/assets/src/mascot/deepy/*.png`: one sheet per animation, e.g. `idle.png`, 48 frames on a 52 × 52 grid of logical pixels at five device pixels per logical pixel (8 frames per row). The build **vectorizes the sheets to SVG** ("rebuilt as vectors"), served from the host's assets route and fetched the first time each animation plays (`packages/client/src/features/mascot/sheets.ts:10-26`; `scripts/build.mjs:389-430`; `packages/client/src/features/mascot/whale.ts:10-21`; `packages/client/src/features/mascot/routed-sheets.ts:8-14`).

**Whalegirl** — `packages/assets/src/mascot/whalegirl/*.png`: 22 strips, one per animation, each a single long row (e.g. `idle.png`, 21 frames, 69 × 66 each); routed, not inlined, fetched on first play (`packages/client/src/features/mascot/sheets.ts:110-126`; `scripts/build.mjs:397-400,432-441`; `packages/assets/assets.mjs:32-36`; `packages/client/src/features/mascot/whale-girl.ts:8-18`; `packages/client/src/features/mascot/routed-sheets.ts:8-14`).

**GIF previews** — `docs/gifs/*.gif` (20 animations: idle, idle-look, idle-spout, thinking, typing, music, conducting, building, error, happy, notification, compacting, sleeping, waking, poke-left/right, tickle, drag). These are the author's GIFs for the README; they are **not shipped in the npm package** and are not usable as licensed assets for this project (`AGENTS.md:43`; `README.en.md:122`).

The mascots are played with WAAPI `steps(1)` translations of a strip inside an overflow-hidden window; crop boxes per animation live in `packages/client/src/features/mascot/sheets.ts` (e.g. Deepy idle `{frames: 48, box: [12, 26, 36, 24], still: 0}`, `sheets.ts:40`; crab typing `{frames: 6, box: [15, 22, 28, 14], still: 0}`, `sheets.ts:90`). Deepy frame pace is **50 ms** (`DEEPY_FRAME_MS`, `sheets.ts:22`); crab **80 ms** (`CRAB_FRAME_MS`, `sheets.ts:75`); Whalegirl per-frame durations (e.g. idle 700/280/280/240/360/… ms, `sheets.ts:119`).

### 3.2 States and the events that trigger them

The state machine (`features/mascot/mascot-signals.ts`, `mascot-stage.ts`) assigns an animation per condition, with a priority (higher wins):

| Priority | Condition (event that triggers it) | Animation |
|---|---|---|
| 10 | reader's own press in flight (click/drag) | reaction: `poke-left` / `poke-right` (tap), `tickle` (4 taps within 450 ms), `drag` (held ≥ 4 px) — `mascot-player.ts:78-81`; `REACTION_PRIORITY` is in `mascot-stage.ts:62` |
| 8 | turn ended with `error`/`blocked`, or a tool result with `isError` (excluding `AbortError`), or a compaction failed | `error`, once, 4.8 s (`mascot-stage.ts:58`) |
| 7 | any session (workspace-wide) or the followed session/subagent is waiting on a pending interaction (approval, question, plan review) | `notification` (`mascot-signals.ts:32`, `mascot-signals.ts` `mascotLevel`) |
| 6 | a compaction of the followed session runs (`compaction/start` … `compaction/end`) | `compacting` ("sweeping") (`mascot-signals.ts:33,88`) |
| 5 | turn ended `completed`/`max-tokens`, or a session finishes unread out of view, or a compaction ends — "attention" | `happy`, once, 5.2 s (`mascot-stage.ts:59`) |
| 4 | one or more **subagents** of the followed session running: 1 → `music`; ≥ 2 → `conducting` ("juggling") (`mascot-signals.ts:93`) |
| 3 | the followed session is writing its answer or calling tools — "working": 1 busy session → `typing`; 2 → `music`; ≥ 3 → `building` (`mascot-signals.ts:59-61`) |
| 2 | the followed session is reasoning / has produced no readable activity — "thinking" (`mascot-signals.ts:31,95`) |
| 1 | idle (nothing running) — `idle` loop; after 60 s of no pointer/key/work, `sleeping`; on activity, `waking` once; extras every 20–40 s picked at random from `idle-look`, `idle-wave`, `idle-laptop` (crab) or `idle-look`, `idle-spout` (Deepy/Whalegirl) (`mascot-stage.ts:52-55,115-155`; `crab.ts`, `whale.ts`, `whale-girl.ts` extras lists) |

A level that just took the stage holds it at least 1000 ms against an equal/lower one (`MIN_SHOW_MS`, `mascot-stage.ts:50`). Reaction priority 10 (`REACTION_PRIORITY`, `mascot-stage.ts:62`). Moments queue behind a greater one on stage; error (8) outranks attention (5); happy (5) outranks working (3) (`mascot-stage.ts:104-111,121`).

The README's "eight states" are the **deepseek-facing names** of the same machine: Idle, Thinking, Answering-and-calling-tools (`typing`), Conducting-subagents (`conducting`), Waiting-on-you (`notification`), Failed (`error`), Finished (`happy`), Asleep (`sleeping`) (`README.en.md:51-66`).

### 3.3 Size, placement, pointer window

All three stand **on the top edge of what they stand on** — the composer card (home page, both layouts), the input area or the panel that replaces its card in a conversation — anchored to the card's **right** end and drawn above it with `z-index: 1`; hidden (`visibility: hidden`) until the first sheet is ready (`mascot-frame.css:12-16`).

- **Deepy**: 104 × 104 px (52 × 52 grid @ 2 px); `right: 8px`; `bottom: calc(100% - 4px)`; resting hit window `left: 24px; top: 60px; width: 64px; height: 36px`; ground line = middle of the shadow at logical row 48.5, box lifted so the last row lands on the card's top edge; sheets scaled smoothly, **not** `image-rendering: pixelated` (`packages/client/src/features/mascot/whale.css:1-13,21-42`; `packages/client/src/features/mascot/sheets.ts:10-26`; `docs/STYLE.md:950-970`).
- **Crab**: 104 × 72 px (52 × 36 cells @ 2 px); feet on the card's top edge (`bottom: 100%`); `right: 0` on the home single-line card; in a conversation, `right: max(var(--dsh-composer-side-clearance, 16px), (100% - card-max-width)/2)`; pointer window `left: 48px; top: 40px; width: 48px; height: 32px`; `image-rendering: pixelated`; faces the reader at rest, turns toward whatever it looks at in a state with something to look at (`packages/client/src/features/mascot/crab.css:14-34,59-67`; `docs/STYLE.md:924-949`).
- **Whalegirl**: 138 × 132 px (69 × 66 @ 2 px); `right: 8px`; `bottom: calc(100% - 12px)` (lifted 10 device px for the shadow plus 2 for the bounce); `image-rendering: pixelated`; hit window `left: 24px; top: 20px; width: 104px; height: 104px` (`packages/client/src/features/mascot/whale-girl.css:14-43`).
- On a panel replacing the card, each stands a little higher (Deepy `bottom: calc(100% - 11px)`, crab `calc(100% - 7px)`, Whalegirl `calc(100% - 19px)`) (`packages/client/src/features/mascot/whale.css:32-36`, `packages/client/src/features/mascot/whale-girl.css:26-30`, `packages/client/src/features/mascot/crab.css:36-43`).
- Only the resting (idle) body takes the pointer; other states are inert to presses, and Reduced motion pins still frames (the `still` index per animation, `packages/client/src/features/mascot/sheets.ts:39,84,118`).
- Hovering the resting mascot **250 ms** opens a pixel bubble (PoxiaoPixel face): DeepSeek account balance on top (checking ≤ once a minute), the conversation's cost under it (`mascot-bubble.ts:16`; `README.en.md:68`). A press closes the bubble and plays a reaction.

### 3.4 What an iOS client should reproduce

Minimum viable mascot spec: one sprite-strip player (`steps(1)` or per-frame timers), three assets if licensing permits (crab = do not reuse, §4), states idle/thinking/working(1–3+)/notification/error/happy/sleeping mapped to the same priorities; placement on the card's top-right edge with the same crop-box lift so the shadow rests on the edge; resting-only pointer; 60 s sleep.


## 4. License summary (information, not legal advice)

**This section is information for the reader derived from the repository's own license files. It is not legal advice, and neither the task author nor this document's author is a lawyer. For any decision beyond private study, consult one.**

The `LICENSE` at the reference root is MIT for the software, with explicit carve-outs. Relevant clauses:

> Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so…
> (`LICENSE:5-10`)

> The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
> (`LICENSE:12-13`)

**Crab artwork clause** (`LICENSE:49-56`):

> the pixel crab (Clawd) is a character of Anthropic, and all rights in it remain with Anthropic. … These files, and their copies inlined into `lib/client.js`, are **not** covered by the MIT license above.

**Anthropic font files clause** (`LICENSE:35-41`):

> `AnthropicSansWebText.ttf`, `AnthropicSerifWebText.ttf` and `AnthropicMonoWeb.ttf` are proprietary typefaces of Anthropic, extracted from Anthropic's web products. They are included in this repository **for personal use only** and are **not** covered by the MIT license above; all rights remain with Anthropic. The npm package does not ship these files.

**Sodium engine notice** (`LICENSE:25-31`):

> the files under `packages/client/src/features/sodium/` and `packages/engine/src/sheet-rewrite.ts` are the Sodium rendering engine. They are licensed under the PolyForm Shield License 1.0.0, **not** under the MIT license above; the terms are in `packages/client/src/features/sodium/LICENSE`. Read, change and redistribute them, but **not to provide a product competing with this plugin.**

The PolyForm Shield "Noncompete" clause:

> Any purpose is a permitted purpose, except for providing any product that competes with the software or any product the licensor or any of its affiliates provides using the software.
> (`packages/client/src/features/sodium/LICENSE:62`, "Noncompete")

> Goods and services compete even when they provide functionality through different kinds of interfaces or for different technical platforms.
> (`packages/client/src/features/sodium/LICENSE:68`, "Competition")

**Deepy** is by calmly-eating-bugs (@wp3171216237); it "ship[s] with the plugin by the author's permission"; the Whalegirl set "came with issue #224"; both are acknowledged in the README, not granted to third parties (`README.en.md:122-125`).

### (a) Reusing the mascot artwork in a personal, non-commercial, non-distributed iOS app

- **Crab (Clawd) / Anthropic frames**: no license is granted anywhere in this repo for reusing these frames. "Personal use" language exists only for the Anthropic *fonts*, not the crab. Copying the frames into another app — even a private one — is **not covered by the MIT grant**; it is tolerated in practice only by not being enforced. The honest statement: this repo gives you no right to do it; the risk of a personal, non-distributed app being noticed is low, but it is risk, not permission. Also note this plugin is explicitly "an unofficial fan work, not affiliated with or endorsed by Anthropic" (`README.en.md:125`; `LICENSE:49-56`).
- **Deepy**: the author granted the plugin's author permission to **ship Deepy with the plugin**. That is a license to this project, not a grant to you or to your app. Reuse in your iOS app is outside it; you would need calmly-eating-bugs's permission (and even the README's "GIFs of all 20 animations are in docs/gifs/" shows the art is shared, not licensed broadly).
- **Whalegirl**: the set "came with issue #224" (`README.en.md:123`); no license text for it exists in the repo. Treat as unlicensed; ask the set's source or draw your own.
- Practical route for (a): draw or commission your own sprite sheets (the geometry spec in §3.3 is enough), or ask both authors for permission in writing. A non-distributed personal app reduces the *enforcement* risk but grants no rights.

### (b) Reimplementing the look in our own code

- MIT permits using the plugin's code as a reference. You may reimplement the **layout, spacing, colour tokens, motion timings and state machine** in your own SwiftUI code; ideas, styles and behaviour are not what copyright protects, and the values are factual measurements.
- The MIT condition that does bind you: if you copy *code* (or substantial parts), keep the copyright notice and permission notice with it (`LICENSE:12-13`). A clean-room SwiftUI implementation carries none of that obligation.
- You may **not** recreate: the crab artwork (Anthropic's character, excluded explicitly), the Deepy/Whalegirl sheets (authors' permission only for this plugin), the Anthropic fonts (personal use only, notwithstanding the user's instruction recorded below — see "Fonts"), or the PoxiaoPixel subset beyond its SIL OFL 1.1 terms (OFL allows bundling in software, including sold software, as long as it is not sold by itself and its Reserved Font Name is not used for derivatives).
- The **PolyForm Shield** terms only cover the Sodium engine files; if your iOS client never uses or ports Sodium, they do not apply. If you ever port Sodium's rendering techniques into a product that competes with this plugin, the shield forbids it — that is the clause to read before doing so (`LICENSE:25-31`; `NOTICE.md`).

### Fonts (included faces, as hosted)

The repo ships (and the npm package carries) **JetBrains Mono** (including Italic), **Inter** (look-alike face cut to Claude's Latin coverage), **Noto Serif** (look-alike serif), and the **ClaudeStylePixel.woff2** PoxiaoPixel subset — all under the **SIL Open Font License 1.1** (`packages/assets/src/fonts/OFL.txt`; `LICENSE:43-47`). These are **not required to keep attribution inside your app's UI**, but the OFL requires (i) not selling the font software by itself, (ii) not using its Reserved Font Name for derivative versions, and (iii) keeping it under OFL if you redistribute it. Bundling them in an iOS app — including a commercial one — is therefore permitted.

The **Anthropic faces** (`AnthropicSansWebText.ttf`, `AnthropicSerifWebText.ttf`, `AnthropicMonoWeb.ttf`) are **repo-only**, never in the npm package; they are registered at runtime only when the reader drops them into `$DSH_HOME/dsh-claude-style/fonts/` (`packages/client/src/theme/typography.css:21-27` header comment; `packages/client/src/shared/webfonts.ts:5-14`). The repo states they are for **personal use only** (`LICENSE:35-41`; `README.en.md:97-99`).

Per the user's instruction recorded in this task (2026-11-08): the included fonts are offered **for research** (study, measurement, comparison against the look-alikes) and **for use in a personal iOS app**. That instruction is consistent with the OFL faces' license and with the "personal use" framing for the Anthropic faces *as long as the app stays personal and is not redistributed*. If the app is ever distributed — including through the App Store — the Anthropic faces' "personal use only" grant would no longer cover it, and the OFL faces would still be fine to bundle. The distribution scenario is not covered by anything in this repo; that would be a separate decision with Anthropic (for its faces) — again, not legal advice.

Net: for a personal, non-commercial, non-distributed iOS app, using all the included fonts for research and bundling them privately is the intended reading; for anything shipped, use the OFL faces only, and your own or licensed replacements for the rest.


## 5. Composer and other interaction details

### 5.1 Input box

- Hero/new-conversation variant: tall field, `min-height: 86px`; conversation variant: hugs the draft, `min-height: 36px`, grows a line at a time, caps at `var(--dsh-composer-text-max-height, 180px)` before it scrolls (`packages/client/src/features/composer/card.css:26-37`; `inline.css:205-215`).
- Card: `border-radius: 18px`, 1 px `--dsw-alias-border-l1` border, font-size `calc(15px × interface-font-scale)`, gap 8 px; light: white fill (`--dsw-specific-input-major: #FFFFFF`) with soft drop shadow `0 4px 12px rgba(20,20,19,0.04), 0 1px 3px rgba(20,20,19,0.02)`; dark: `#141414` equivalent, shadow `0 4px 12px rgba(0,0,0,0.30), 0 1px 3px rgba(0,0,0,0.15)` (`card.css:8-15,82-90`).
- Focus: the field lights up — 1 px halo + deepened drop shadow in the light theme (`rgba(20,20,19,0.18)` border, `0 0 0 1px rgba(20,20,19,0.065), …`); in dark it **inverts to a bright ivory rim** (`rgba(250,249,245,0.22)` border, `0 0 0 1px rgba(250,249,245,0.09), …`). Accent is never used for focus strokes (`card.css:99-110`; `docs/STYLE.md:312-322`).
- Send button: empty draft → ghost (transparent, hairline `--dsw-alias-border-l2` border, glyph in caption ink, 34 px border-box); with attachments or text it is filled (host control, 7 px radius). Commands/attach buttons: 7 px radius, transparent resting, warm plate hover (`--dsh-claude-chip`, light `#F9F9F9`) (`card.css:121-145,237-250`; chip token `--dsh-claude-chip`, light `#F9F9F9` (no dark value — host's `--dsw-specific-selector` stands), `docs/STYLE.md:190` token table).

### 5.2 Model / mode chips (and friends)

- Trigger buttons (model picker, permission, effort) share the footer control face: font-size 14 px, 7 px radius, chevron **dropped** (the click target and menu stay as shipped); hover plate is the shared chip (`card.css:150-172`).
- The composer footer is a **two-tier tray** in the classic home layout: top = white card with shadow (z-index 2); below = a seamless equal-width tray (z-index 1) attached to the card's bottom with 18 px bottom radius, transparent fill inheriting canvas, 1 px left/right/bottom border, footer controls at 28 px height (`--dsh-claude-footer-control-height`), ink opacity 0.72 at rest → 1 on hover (`vars.css:9-16`; `card.css:180-231`).
- Bottom of the transcript: the composer paints an **opaque `--dsw-alias-bg-base` bar** plus one `--dsh-composer-fade-h: 40px` gradient band above it running to transparent; the same token is the transcript's bottom clearance (`vars.css:9`; `docs/STYLE.md:303-311`).
- Model chips row: `--dsh-claude-footer-ink-opacity: 0.72` etc. (`vars.css:13-16`); hover resolves to full strength (`docs/STYLE.md:303-311` bottom-edge / composer paragraph).
- Permission control: the Claude layout uses a segment group on the classic layout, and the conversation's trigger + card on the Studio layout (`docs/STYLE.md:812-828`).

### 5.3 Scroll-to-bottom ("back to the end") button

The button is the **host's own**, rendered only while the follow is off. The skin re-places it: `position: fixed`, **horizontally centred over the composer column**, **12 px above the composer's top edge** (`FOLLOW_TAIL_AIR_PX`), full z-order below floating cards, so it does not collide with the mascot on the card's right end; the numbers are written per pass because the column moves with the sidebars (`chat-follow.ts:47,85-101`; `chat-follow.css:13-26`). The skin also keeps it out of sight while its own glide is following the tail (same module).

### 5.4 Other notable details

- Message row actions appear on hover only (opacity 0 → 1 with feedback timing 120 ms); the user's own message is right-aligned on the bubble plate `#F4F2F3` (Claude light) / `rgba(255,255,255,0.06)` (Claude dark) / `#ECF0FF` / `#262B36` (DeepSeek) (`message-actions.css:7-17`; `STYLE.md:78-79`).
- Tall user messages clamp at 320 px with a 40 px bottom fade and the skin's toggle (`§1.2`).
- Reduced animation is a single reader choice resolved onto `<body>`; every motion token has a reduced counterpart (`tokens.json:1159`).
- The turn's clock runs from the turn start, `Math.max(1000, now - start)` ticked every 250 ms (`chat-wait.ts` `TICK_MS` = 250).
- Overtime: after **10 s** with no readable activity, "No response yet" appears (`wait-state.ts:11`).
- Selection uses the platform's solid selection paints, never translucent, overriding link/code colours (`docs/STYLE.md:459-477`).
- Copy buttons and disclosures keep a 120 ms feedback timing; the transcript's `hr` and all separators are 0.5 px `--dsh-claude-divider` (`STYLE.md:295`).


## Appendix — files read

`README.en.md`, `LICENSE`, `AGENTS.md`, `docs/STYLE.md`, `docs/ARCHITECTURE.md`, `docs/NOTICE.md`, `docs/THIRD_PARTY_NOTICES.md`, `docs/gifs/`, `packages/client/src/theme/tokens.json`, `packages/client/src/theme/{typography,sidebar}.css`, `packages/client/src/features/{chat-fold,chat-wait,chat-follow,message-actions,mascot,process-column,composer,sidebar-status}/…`, `packages/client/src/shared/{turn-activity,swapping-text.css,motion.css}`, `packages/contracts/src/dom.ts`, `packages/testing/lane.mjs`, `packages/assets/src/{mascot,fonts}/…`, `scripts/build.mjs`, `packages/assets/assets.mjs`.

Verified: 170 citations checked, 58 corrected.
