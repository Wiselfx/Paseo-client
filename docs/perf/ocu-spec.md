# open-claude-ui → Paseo iOS: design-spec review

Read-only distillation of the cloned repo at `/tmp/ocu` (docs are Chinese; this file is English).
Target: our iPhone SwiftUI app (`/home/paseo/dev/Paseo-client`), against `docs/UX-SPEC.md` and
`Packages/PaseoUI/Sources/PaseoUI`.

## 0. Sources, confidence, and how to read

**Primary sources**

| Source | Version / status | Use |
| :--- | :--- | :--- |
| `docs/v4.29.0-4.4212.0/06-全量CSS扫描与官方规范比对.md` | 3.6556.2 → 4.4212.0, **runtime-verified** (`getComputedStyle` via Electron debugger) | Highest authority for tokens |
| `docs/v4.29.0-4.4212.0/01..05,07` | 3.6556.2 baseline + 4.29/4.4212 increments | Keyframes, density, skeleton, gray/orange ramps |
| `docs/v4.16336.0/*` | Side Browser surface, desktop | Corroborates radii/motion; mostly N/A on iPhone |
| `docs/v2/*` | 2.37337.1, historical | Corrects v1 in places; itself corrected by v4.29 |
| `docs/v1/*` | 1.x / 2.37337.1, historical | Rich detail; many values superseded |
| `AGENTS.md` | repo's own summary | Convenient, but mixes v3 runtime values with stale v1 values |
| `code-examples/*.tsx/.ts/.css` | repo implementation | Real values; itself inconsistent with current docs in places |

**Confidence labels**

- **[R]** runtime-verified in `docs/v4.29.0-4.4212.0/06` §6.7.5 (lines 964–1022).
- **[A]** byte/AST-verified in the v4.29 docs.
- **[V2]** v2-only claim (superseded or unverified).
- **[V1]** v1-only claim (superseded or unverified).

**Ours** = `Packages/PaseoUI/Sources/PaseoUI/...`. Line numbers are from the current working tree.

---

## 1. Color

| Value | OCU source | Ours | Verdict |
| :--- | :--- | :--- | :--- |
| Page/canvas light | `--cds-surface-0 #f9f9f7` [R] `06:986`; chat canvas `--surface-1 #fcfcfb` [A] `v1/01:50` | `background #F9F9F7` `Chat/ClaudeStyle.swift:89` | Chat canvas is one step dark; should be `#FCFCFB`, sidebar `#F9F9F7` |
| Sidebar light | `--surface-0 #f9f9f7` [A] `v1/01:49` | `sidebarBackground 0.96 = #F5F5F5` `ClaudeStyle.swift:100` | Too dark by ~2 steps |
| Panel/card light | `--surface-2 #ffffff` [A] `v1/01:51` | `panel 1.0 = #FFFFFF` `ClaudeStyle.swift:106` | Match |
| Chat canvas dark | `--surface-1 #151515` [R] `06:992`; `v2/03:67` | `#141413` `ClaudeStyle.swift:89` | 1/255 off; effectively match |
| Sidebar dark | `--surface-0 #0b0b0b` [R] `06:986` | `16/255 = #101010` `ClaudeStyle.swift:100` | Too light |
| Panel dark | `--surface-2 #1a1a19` [A] `v1/01:51`; popover `--surface-3 #20201f` | `panel 31/255 = #1F1F1F` `ClaudeStyle.swift:106` | Between surface-2/3; pick `#1A1A19` |
| Composer dark | `--surface-3 #20201f` [A] `v1/01:52` | `#262624` `ClaudeStyle.swift:110` | Too light |
| Text primary | `#0b0b0b` / `#f0efec` [R] `06:972,992` | `primaryInk #161616/#FDFDFD` `ClaudeStyle.swift:149`; `ink #212121/#F2F0EB` `127` | All three ours are lighter; adopt official |
| Text secondary | `#52514e` / `#c3c2b7` [R] `06:973,993` | `secondaryInk #70686A/#BEB6B8` `ClaudeStyle.swift:195` | Ours much lighter/warmer |
| Text muted | `#898781` **both modes** [R] `06:974,994` | `tertiaryInk #91888A/#9C9395` `ClaudeStyle.swift:202` | Close; ours warm, official neutral and mode-invariant |
| Accent (selection/focus) | text `#184f95` light / `#6da7ec` dark; border `#86b6ef`/`#0d366b` [R] `06:975-976,995-996`; `AGENTS.md:52,69` | `proseLink #184F95/#8AB4F8` `ClaudeStyle.swift:163`; `unread #2A78D6` `239`; checkmark `.blue` `ClaudeSheets.swift:63` | Light prose link already exact; dark link/off-state and border-accent missing |
| Brand clay | `--cds-clay #d97757`; `--clay-emphasized #c6613f` (both modes); `--fill-brand-hover #d97757` [R] `06:977-979,997-998`; `AGENTS.md:66-69` | `orange #d97757` only `ClaudeStyle.swift:143` | Missing `#c6613f` and hover token |
| Border | `alpha-2 = 10%` light / `10%` dark; hairline 0.5 px [R] `06:980,999`; `v1/01:120-140` | `divider` black 5% `ClaudeStyle.swift:216`; `cardBorder #E9E9E9`/white 9% `222` | Ours too faint in light, too solid for card edge |
| User bubble fill | neutral gray; `--bg-neutral = alpha-1` [A] `cds-theme.css:194`; `gray-50 #f0efec` [A] `v4.29/04:317` | `#F4F2F3` / white 6% `ClaudeStyle.swift:228` | Ours warm; official neutral |
| Chip fill | `--fill-secondary` white 10% light / `alpha-2` dark [R] `06:985`; `cds-theme.css:165` | `chip 0.965` light / `0.14` dark `ClaudeStyle.swift:235` | Ours visible gray; official nearly invisible in light |
| Skeleton base/sheen | `#0b0b0b 5%` light / white 7.5% dark, base = sheen [R] `06:981,1000`; `v4.29/04:434-449` | none | Missing |
| Popover shadow | `0 8px 24px #0000001f, 0 2px 6px #00000014` light; `0 8px 24px #00000052, 0 2px 6px #0003` dark [R] `06:983,1002` | none (1 px border instead) | Missing |
| Focus ring | blue `#2a78d6` 1 px + glow `#cde2fb` [R] `06:984,1003`; `v4.16336.0/01:88` | none | Missing (iOS uses focus engine) |
| Code block bg | `#0d0d0c` dark [A] `v1/05:673`, `v1/07` CodeBlock | `codeBackground 0.04 = #0A0A0A` dark `ClaudeStyle.swift:103` | Close; adopt `#0D0D0C` |
| Code block radius | 12 px [A] `v1/05:673`; `cds-theme.css:320` | 8 px `Chat/ClaudeChatComponents.swift:64-66` | Ours 8; official 12 |
| Code header height | 36 px [A] `v1/05:674` | 9 px vertical padding + mono 12.5 `ClaudeChatComponents.swift:45-46` | Ours more compact |
| Diff gaps | inline `pad-md` 12, block `pad-xs` 6 [A] `v1/05:5.5.1` | ad-hoc | Missing |
| Copy decay | 2.5 s `saved-check-decay` [A] `v1/04:57-62`, `v1/05:675` | 1.5 s `ClaudeChatComponents.swift:107` | Ours too short |
| Success/failure ink | not specified in v4.29 runtime table | `successInk #3B8B4F/#6FAF7E` `ClaudeStyle.swift:246`; `failureInk #C0453A/#E5675C` `240` | Keep ours; no contradiction found |

---

## 2. Radii

| Value | OCU source | Ours | Verdict |
| :--- | :--- | :--- | :--- |
| Base control radius | 8 px comfortable / 6 px compact [R] `06:1010,1016`; `v2/03:84` | ad-hoc 10/12/14/16 | Unify to 8 |
| Card radius | 12 px (`radius + 4`) [A] `06:425`; `v4.16336.0/01:99` | `ClaudeCard` 10 `ClaudeStyle.swift:438`; `RowGroup` 28 `ClaudeSheets.swift:80`; permission card 16 `ClaudePermissionCard.swift:40` | Adopt 12 for cards |
| Composer radius | 14 px comfortable / 12 px compact [R] `06:1006-1018,679-703`; `v2/03:83` | 27 expanded / 24 collapsed `Conversation/ChatComposer.swift:708,711` | Expanded card should be 14; collapsed pill stays capsule |
| User bubble radius | 18 px [A] `v1/01:83`; formula `radius+4` [A] `v1/03:55` | 20 `Chat/ClaudeChatComponents.swift:162` | Adopt 18 |
| Code block radius | 12 px [A] `v1/05:673` | 8 `ClaudeChatComponents.swift:64` | Adopt 12 |
| Panel radius | 10 px compact / 12 px comfortable [A] `v2/03:85` | 10 `ClaudeStyle.swift:438` | Match compact |
| Media tile radius | 16 px (desktop attachment tile uses `rounded-card` 12) [A] `v1/02:348` | 16 `ClaudeMediaView.swift:84` | Keep 16 for iOS thumbnail |
| Pill radius | 999/9999 px [A] `v1/01:86`; `cds-theme.css:315` | `.capsule` | Match |
| Dialog radius | 16 px [A] `v1/02:292`, `v1/07` ConfirmationDialog | sheets are system; custom cards 16 | Match for custom cards |
| Precision scale | xs 2, sm 4, md 6, lg 8, xl 12, 2xl 16, 3xl 24 [A] `v1/01:76-82`; `AGENTS.md:79` | ad-hoc | Provide a central radius enum |

---

## 3. Spacing & sizing

| Value | OCU source | Ours | Verdict |
| :--- | :--- | :--- | :--- |
| Bubble padding | pad-x 16, pad-y 12 [A] `v1/03:56-57`; `cds-theme.css:219-220` | 16 / 10 `ClaudeChatComponents.swift:204-205` | Adopt 12 vertical |
| Bubble max width | 85% (`clamp(85%,448px,100%)` under 40rem) [A] `v1/03:60-62` | `Spacer(minLength: 42)` `ClaudeChatComponents.swift:191` | Fixed 42 pt vs 85%; consider 85% |
| Chat turn gap | 15 px at body 14/20; item gap 10 px [A] `v1/03:107-110` | transcript spacing ad-hoc | Desktop; use as ratio (0.75×line height) |
| Composer min height | 44 px [A] `v1/03:289` | controls row 36 `ChatComposer.swift:500,752` | Adopt 44 touch row |
| Composer max height | `min(40svh, 24rem)` = 384 px [A] `v1/03:289` | ~40% of space above keyboard `ChatComposer.swift:683` | Already equivalent; document as 40svh |
| Control heights | compact 24 / comfortable 32; nested 22 [R] `06:1012-1013`; `v2/03:87` | 36/44/52 | iPhone needs 44; keep 44, drop 36 |
| Gap scale | compact 6/8/12/20/32; comfortable 8/12/16/28/40 [A] `v2/03:90` | ad-hoc | Provide a central spacing enum |
| Sidebar row height | 28 px compact [A] `v2/03:22` | 44 pt `Sidebar/PaseoSidebar.swift:331,486` | Desktop density; keep 44 on iPhone |
| Sidebar width | 288 px [A] `v1/01:105` | N/A iPhone | Not applicable |
| Attachment tile | 7.5 rem square (120 px → 112.94) [A] `v1/02:348-352` | 56 pt thumbnail `Chat/ComposerAttachments.swift:180` | Desktop; keep 56 iOS |
| Dialog max widths | 400/520/720/880/1024/1152 [A] `v1/02:286-293` | N/A iPhone sheets | Not applicable |

---

## 4. Typography

| Value | OCU source | Ours | Verdict |
| :--- | :--- | :--- | :--- |
| Desktop scale | caption 11, footnote 12, code 12, body 14, prose 14–16, heading 15, title 20 [A] `v1/01:347-353` | status 11/13, code 12.5, body 17, sidebar 13/16, sheet title 17 | iPhone sizes are larger; keep ours |
| Mobile input floor | `font-size: max(16px, body)` [A] `v1/01:492` | composer 17 `ChatComposer.swift:124` | Match |
| User bubble size | body 14 desktop [A] `v1/01:350` | 14 `ClaudeChatComponents.swift:201` but UX-SPEC §0.3/§4.1 says 17 | Internal conflict; pick 17 for iOS |
| Bubble line height | 20 px at 14 [A] `v1/03:107-110` | 22 (`lineSpacing 8`) `ClaudeChatComponents.swift:203` | At 17 pt official prose ratio is 1.43–1.5 → 24–25; ours 25 is fine |
| Chat body (iPhone) | desktop 14; mobile min 16 [A] `v1/01:492` | `chatBodySize 17` `ClaudeStyle.swift:9` | Match iOS practice |
| Greeting display | 38 px serif light (wght 330, opsz 48) [A] `v1/01:547` | serif 26 `ClaudeHomeHero.swift:106` | Desktop; iOS 26 is right |
| Empty-state icon | XL 24 px [A] `v1/01:527` | 44 pt mark `ClaudeHomeHero.swift:100` | iOS hero is 44 by UX-SPEC §3.1 |
| Dark weight compensation | dark wght −40/−30 [V1] `v1/01:383-425`; `v1/07` globals | none | v1-only; v4.29 does not confirm; unverified |
| Tabular numbers | counters/timers/diffs use `tabular-nums` [A] `v1/01:497-505`; `AGENTS.md:103` | status line `monospacedDigit()` `ClaudeStatusLine.swift:167` | Extend to token counters/rings |
| Font stacks | Anthropic Sans/Serif/Mono with system fallback [A] `v1/01:300-320`; `v1/07` tailwind | Anthropic faces + Newsreader fallback `ClaudeStyle.swift:15-19` | Match |
| Model chip | 12 px medium [A] `v1/01:448` | 12 `ChatComposer.swift:95-107` | Match |
| Send label | 12 px semibold [A] `v1/01:450` | icon-only | N/A |

---

## 5. Motion & springs

| Value | OCU source | Ours | Verdict |
| :--- | :--- | :--- | :--- |
| Durations | fast 60, snap 120, base 200, sheet 300, slow 450 [R] `06:1017`; `v2/04:50-58` | feedback 120, move 200, open 250, rise 500, settle 320 `ClaudeStyle.swift:269-295`; `EdgeDrawer.swift:24` | Adopt official set; reconcile with UX-SPEC §0.4 (0.32) |
| Easings | out `cubic-bezier(.165,.84,.44,1)`, snap `(.32,.72,0,1)`, overshoot `(.34,1.3,.64,1)` [R] `06:366-368`; `v2/04:60-66` | `timingCurve(0.22,1,0.36,1)`, `.smooth`, `.easeOut` | Add central easing tokens |
| Button spring | 600/30, ζ 0.612, +8.8% [A] `AGENTS.md:96-104`; `v2/04:64` | `.snappy` on small pops | Adopt for button press only |
| Drag-release spring | 320/28, ζ 0.783, +1.9% [A] `AGENTS.md:106-112` | `EdgeDrawer` velocity-aware settle | Match concept; keep ours |
| Panel/drawer spring | 1200/80/0.1, ζ 3.652, 0% [A] `AGENTS.md:120-126`; `v1/04:161` | `.smooth(0.32)` | UX-SPEC mandates critically damped; keep ours |
| Message enter | `translateY(10px)` fade, 200 ms [A] `v1/04:45-49`; `v1/06:196-205` | scale + opacity, 200 ms `ClaudeChatComponents.swift:188-195,257-261` | Adopt fade-up, drop scale |
| Thinking dots | 3 px clay, gap 3.5 px, 1.9 s `cubic-bezier(.4,0,.2,1)`, delays 0/.15/.3 [A] `v1/02:236-255`, `v1/03:132-150` | 4 pt orange, custom 3-lane `ClaudeLoader.swift:30-33` | Align to 3 pt clay 1.9 s |
| Status enter/exit | enter 0.24 s rise 6 px; exit 0.18 s fall 4 px [A] `v1/03:160-165` | `swap 0.15`, spring 0.25/0.62 `ClaudeStatusLine.swift:184-190` | Adopt enter/exit pair; remove underdamped spring |
| Timeline expand | 0.2 s `cubic-bezier(.19,1,.22,1)` [A] `v1/03:180-190` | work group collapse ad-hoc | Adopt |
| Skeleton sweep | 2 s linear 105° [A] `v4.29/05:5.1.3`; `v1/04:63-70` | none | Adopt if skeleton added |
| Skeleton breathe | 2 s ease-in-out, wave stagger 90 ms, lockstep on group [A] `v4.29/03:3.3` | none | Adopt if skeleton added |
| Progress sweep | 1.6 s `cubic-bezier(.65,0,.35,1)`, 60% width, opacity .5, mask [A] `06:1459-1471` | `ProgressView` | Adopt for indeterminate progress |
| Chip stagger | base 50 ms + min(sibling-index−1,8)×30 ms [A] `v2/02:110` | none | Adopt for chip rows |
| Pill pop | pop-up 1.32×, dip 0.82× [A] `v4.29/03:3.6`; `v2/03:139` | none | Adopt for pill feedback |
| Scroll fade | 24 px hard cut (actual masks) [A] `06:6.6.4`; token default 28 px but unconsumed [A] `v4.29/03:3.7` | 40 pt fade band `ChatTranscript.swift:585-595` | Adopt 24 pt |
| Scroll pinning | 150 ms cooldown, 40 px bottom tolerance, 35 vh bottom padding [A] `v1/06:206-230` | auto-scroll on send; no cooldown | Adopt cooldown + tolerance |
| Token reveal | 120 ms `cubic-bezier(.16,1,.3,1)`, blur 6 px, translateY 4 px, opacity 0.2 [A] `v1/06:196-205` | none | Optional; SwiftUI text streaming |
| Hover/card lift | −1.5 px, 150 ms [A] `v1/01:223` | N/A touch | Not applicable |
| Lightbox | min scale 2, deadzone 4 px, wheel exp 0.01, snap 1.05, tap 1.25, damping 0.7, preload 2; backdrop 0.2 s, content 0.25 s [A] `v1/05:332-458` | `ClaudeMediaView` 140×140, no zoom physics | Adopt deadzone/snap for full-screen viewer |
| Gallery | 75 vw slides, gap 32 px, 300 ms ease-out, inactive 0.4/hover 0.75 [A] `v1/05:459-497` | none | Desktop; N/A |
| Split pane | deadzone 4 px, 50/50 snap, dock 18%/420 px, min 380/420 [A] `v1/05:498-540` | N/A iPhone | Not applicable |
| IME guard | WebKit 500 ms post-composition [A] `v1/03:3.3.2` | SwiftUI TextField; dictation controlled | N/A native, note only |

---

## 6. Composer

| Value | OCU source | Ours | Verdict |
| :--- | :--- | :--- | :--- |
| Radius | 14 px comfortable / 12 px compact [R] `06:1006-1018` | 27 expanded / 24 collapsed `ChatComposer.swift:708` | Adopt 14 expanded |
| Min height | 44 px [A] `v1/03:289` | 36 row `ChatComposer.swift:500` | Adopt 44 |
| Max height | 384 px / 40 svh [A] `v1/03:289` | ~40% `ChatComposer.swift:683` | Match |
| Text size | 14 desktop / min 16 mobile [A] `v1/01:492` | 17 `ChatComposer.swift:124` | Match iOS |
| Model chip | 12 px medium, grey fill [A] `v1/01:448` | 12 `ChatComposer.swift:95-107` | Match |
| Placeholder | 45% opacity [A] `v1/01:442` | secondaryInk | Close |
| Send button | 12 px semibold; clay brand [A] `v1/01:450`, `v1/03:350` | icon, clay tint | Match concept |
| Attachment chip | 120 px tile desktop; inline pill [A] `v1/02:348` | 56 pt thumbnail | iOS keep 56 |
| Chin row | 28 px visual, 44 px touch via negative margin [A] `v2/02:208-220` | 36 pt row | iPhone already 44+; keep |
| Composer shadow | dual-ring: `0 4px 20px rgba(0,0,0,.035)` + inset 1 px border [A] `v1/01:184-200` | panel fill + border | Optional; iOS flat |

---

## 7. Message bubbles

| Value | OCU source | Ours | Verdict |
| :--- | :--- | :--- | :--- |
| User radius | 18 px [A] `v1/01:83` | 20 `ClaudeChatComponents.swift:162` | Adopt 18 |
| User padding | 16 / 12 [A] `v1/03:56-57` | 16 / 10 `ClaudeChatComponents.swift:204-205` | Adopt 12 vertical |
| User max width | 85% [A] `v1/03:60` | fixed 42 pt spacer | Consider 85% |
| User fill | neutral gray [A] `v1/03:64`; `cds-theme.css:194` | `#F4F2F3` warm | Adopt neutral |
| Assistant layout | zero border, 4 px text inset, text stop `clamp(0,(100%−384)×.175,56)` [A] `v1/03:89-102` | full-bleed prose | Desktop; N/A iPhone |
| Collapse threshold | 300 px + 3 rem gradient [A] `v1/03:69-75` | none (UX-SPEC §4.3 forbids Show more) | UX-SPEC wins; keep none |
| Enter animation | fade-up 10 px, 200 ms [A] `v1/04:45` | scale+opacity 200 ms | Adopt fade-up |
| Context menu preview | bubble shape preview [A] `v1/03` (UX-SPEC §4.3) | `.contextMenuPreview` bubble radius `ClaudeChatComponents.swift:210-211` | Match |

---

## 8. Tool & permission cards

| Value | OCU source | Ours | Verdict |
| :--- | :--- | :--- | :--- |
| Pending border | clay border 50% + clay glow [A] `v1/03:330`; `McpToolDecisionCard.tsx:86` | `cardBorder` `ClaudePermissionCard.swift:41` | Adopt clay border for pending |
| Radius/padding | panel 10/12, padding 12 [A] `v1/01:80` | 16 / 14 `ClaudePermissionCard.swift:40` | Adopt 12 / 12 |
| Running state | blue spinner [A] `v1/03:335` | `ProgressView.mini` `ClaudeChatComponents.swift:76` | Match |
| Success/error | badge + collapsible output [A] `v1/03:335` | 6 pt dot `ClaudeChatComponents.swift:78-84` | Match (6 pt is official) |
| Actions | Allow Once (brand clay), Always Allow, Deny (ghost danger) [A] `v1/03:350-360`; `McpToolDecisionCard.tsx:199-213` | upstream labels, variant mapping `ClaudePermissionCard.swift:95-105` | Verify variants match roles |
| Status dot | 6 px [A] `v1/02:205-215` | 6 pt `ClaudeChatComponents.swift:78-84` | Match |
| Whitelist GC | 330 s [A] `v1/03:318` | daemon-side | N/A client |

---

## 9. Sidebar

| Value | OCU source | Ours | Verdict |
| :--- | :--- | :--- | :--- |
| Width | 288 px [A] `v1/01:105` | N/A | Not applicable |
| Row height | 28 px compact [A] `v2/03:22` | 44 pt | Desktop; keep 44 |
| Divider | 0.5 px [A] `v2/03:27` | 0.5 pt `ClaudeStyle.swift:368` | Match |
| Branch badge | monospace [A] `v2/03:24` | not in row | Optional; low value |
| PR capsule | inline [A] `v2/03:25` | workspace panel PR pane | N/A sidebar |
| Running heartbeat | breathing halo [A] `v2/03:26` | status dot | Optional |
| Drag deadzone | 4 px [A] `v1/06:6.2.3` | N/A iPhone | Not applicable |
| Ghost drop | −1.5° tilt, 40% opacity, clay dashed [A] `v1/06:6.2.4` | N/A | Not applicable |
| New session pill | inverted capsule [A] `v1/01` footer; UX-SPEC §2 | 44 pt ink capsule `PaseoSidebar.swift:486-487` | Match |

---

## 10. Sheets & popovers

| Value | OCU source | Ours | Verdict |
| :--- | :--- | :--- | :--- |
| Dialog max widths | 400/520/720/880/1024/1152 [A] `v1/02:286-293` | N/A iPhone | Not applicable |
| Dialog radius | 16 px [A] `v1/02:292` | custom cards 16 | Match |
| Nested dialog blur | 2 px [A] `v1/02:305` | N/A | Not applicable |
| Popover shadow | `0 8px 24px #0000001f, 0 2px 6px #00000014` [R] `06:983` | none | Adopt for custom popovers |
| Popover radius | card 12 [A] `06:425` | ComposerMenu 14 `Chat/ComposerMenu.swift:13-15` | Close; keep 14 |
| Sheet header | no OCU value; UX-SPEC §0.3 says 30 pt circle | 42 pt circle `ClaudeSheets.swift:8,18` | Internal conflict; UX-SPEC wins (fix code, not OCU) |
| Single-stroke rule | no inner borders [A] `v1/01:1.4.2`; `v4.16336.0/01:61` | mostly followed | Match |

---

## 11. Empty states, media, voice

| Value | OCU source | Ours | Verdict |
| :--- | :--- | :--- | :--- |
| Empty icon | XL 24 px [A] `v1/01:527` | 44 pt mark | iOS hero 44 by UX-SPEC §3.1 |
| Greeting | 38 px serif light [A] `v1/01:547` | serif 26 | iOS 26 |
| Media deadzone | 4 px [A] `v1/05:332-458` | none | Adopt in viewer |
| Media snap | scale ≤1.05 → 1.0 [A] `v1/05:332-458` | none | Adopt |
| Media min zoom | 2× [A] `v1/05:332-458` | none | Adopt |
| Media tap zoom | 1.25× [A] `v1/05:332-458` | none | Adopt |
| Backdrop/content | 0.2 s / 0.25 s ease-out [A] `v1/05:332-458` | system sheet | Optional |
| Gallery | 75 vw, gap 32, 300 ms, 0.4/0.75 [A] `v1/05:459-497` | none | Desktop N/A |
| Mic bars | 6 bands, FFT 512, smoothing .5, −70/−10 dB, noise gate 8%, gamma 0.7, height 4–24 px [A] `v1/05:177-205` | 5 bars, heights 8/13/18/13/8 × volume `ChatComposer.swift:360-364` | Adopt gamma/noise gate; keep 5 bars iOS |
| SFX volume | 30% fixed [A] `v1/05:130-160`; `v1/08` | gain soft .2 / clear .55, default Off `Chat/SoundCues.swift:26-37` | Conflict; UX-SPEC/DSH default Off wins |
| Haptics | no OCU data (desktop) | `Haptics.swift` | Keep ours; no contradiction |
| Voice personas | airy/buttery/glassy/mellow/rounded [A] `v1/05:5.1.4` | none | Optional; not in scope |

---

## 12. Ranked adoptable changes (40 max)

Each item: **change** — citation — current state.

1. **Adopt official text colors.** Set `primaryInk` `#0B0B0B`/`#F0EFEC`, `secondaryInk` `#52514E`/`#C3C2B7`, `tertiaryInk` `#898781` both modes. Source: `06:972-974,992-994` [R]. Ours: `ClaudeStyle.swift:127,149,195,202`.
2. **Add accent-blue role tokens.** `accentInk #184F95/#6DA7EC`, `accentBorder #86B6EF/#0D366B`. Source: `06:975-976,995-996` [R]. Ours: `proseLink` light matches, dark and border missing (`ClaudeStyle.swift:163`).
3. **Add brand clay pair.** `brand #C6613F`, `brandHover #D97757`; keep `orange #D97757` for pulse. Source: `06:977-979,997-998` [R]; `AGENTS.md:66-69`. Ours: `ClaudeStyle.swift:143`.
4. **Fix dark surfaces.** Sidebar `#0B0B0B`, chat `#151515`, panel `#1A1A19`, composer `#20201F`. Source: `06:986,992-998`; `v1/01:49-52`. Ours: `ClaudeStyle.swift:89,100,106,110`.
5. **Fix light surfaces.** Sidebar `#F9F9F7`, chat `#FCFCFB`. Source: `v1/01:49-50`; `06:986`. Ours: `ClaudeStyle.swift:89,100`.
6. **Fix borders.** Divider 10% light / 10% dark at 0.5 pt; card edge 10% light / 10% dark. Source: `06:980,999`; `v1/01:120-140`. Ours: `ClaudeStyle.swift:216,222`.
7. **Neutral user bubble.** `#F0EFEC` light / white 6% dark. Source: `v1/03:64`; `cds-theme.css:194`; `v4.29/04:317`. Ours: `#F4F2F3` `ClaudeStyle.swift:228`.
8. **Bubble radius 18.** Source: `v1/01:83` [A]. Ours: 20 `ClaudeChatComponents.swift:162`.
9. **Bubble padding 16/12.** Source: `v1/03:56-57` [A]. Ours: 16/10 `ClaudeChatComponents.swift:204-205`.
10. **Card radius 12.** Source: `06:425` [A]; `v4.16336.0/01:99`. Ours: 10/16/28 `ClaudeStyle.swift:438`, `ClaudeSheets.swift:80`, `ClaudePermissionCard.swift:40`.
11. **Composer expanded radius 14.** Source: `06:1006-1018,679-703` [R]; `v2/03:83`. Ours: 27 `ChatComposer.swift:708`.
12. **Composer control row 44 pt.** Source: `v1/03:289` [A]. Ours: 36 `ChatComposer.swift:500,752`.
13. **Document composer cap as 40 svh / 384.** Source: `v1/03:289` [A]. Ours: ~40% `ChatComposer.swift:683`.
14. **Unify control radius 8.** Source: `06:1010,1016` [R]. Ours: ad-hoc 10/12/14/16.
15. **Code block radius 12.** Source: `v1/05:673` [A]. Ours: 8 `ClaudeChatComponents.swift:64`.
16. **Panel radius 10.** Source: `v2/03:85` [A]. Ours: 10 `ClaudeStyle.swift:438` — confirm all panels.
17. **Central duration tokens 60/120/200/300/450.** Source: `06:1017` [R]. Ours: 120/200/250/500 `ClaudeStyle.swift:269-295`.
18. **Central easing tokens out/snap/overshoot.** Source: `06:366-368` [R]. Ours: `timingCurve(0.22,1,0.36,1)` `ClaudeChatComponents.swift:193`.
19. **Reconcile drawer settle with sheet duration.** Official 300 ms vs UX-SPEC 0.32; pick one and note. Source: `06:1017` [R]; `EdgeDrawer.swift:24`.
20. **Message enter fade-up, no scale.** `translateY(10)` fade 200 ms. Source: `v1/04:45-49` [A]. Ours: scale+opacity `ClaudeChatComponents.swift:188-195`.
21. **Thinking dots 3 pt clay, 1.9 s, gap 3.5.** Source: `v1/02:236-255` [A]. Ours: 4 pt orange custom `ClaudeLoader.swift:30-33`.
22. **Status enter/exit 0.24 s rise 6 / 0.18 s fall 4.** Source: `v1/03:160-165` [A]. Ours: spring 0.25/0.62 `ClaudeStatusLine.swift:184-190`.
23. **Timeline expand 0.2 s ease-expand.** Source: `v1/03:180-190` [A]. Ours: ad-hoc.
24. **Skeleton sweep 2 s linear 105°.** Source: `v4.29/05:5.1.3` [A]. Ours: none.
25. **Skeleton breathe 2 s + 90 ms wave stagger.** Source: `v4.29/03:3.3` [A]. Ours: none.
26. **Progress sweep 1.6 s `cubic-bezier(.65,0,.35,1)`, 60% width.** Source: `06:1459-1471` [A]. Ours: `ProgressView`.
27. **Chip stagger 50 ms + 30 ms.** Source: `v2/02:110` [A]. Ours: none.
28. **Pill pop 1.32× / dip 0.82×.** Source: `v4.29/03:3.6` [A]. Ours: none.
29. **Button spring 600/30.** Source: `AGENTS.md:96-104` [A]. Ours: `.snappy`.
30. **Drag-release spring 320/28.** Source: `AGENTS.md:106-112` [A]. Ours: `EdgeDrawer` velocity settle — verify parameters.
31. **Pending tool card clay border 50%.** Source: `v1/03:330` [A]; `McpToolDecisionCard.tsx:86`. Ours: `cardBorder` `ClaudePermissionCard.swift:41`.
32. **Tool card radius 12 / padding 12.** Source: `v1/01:80` [A]. Ours: 16/14 `ClaudePermissionCard.swift:40`.
33. **Tool actions: Allow Once brand, Always Allow, Deny ghost danger.** Source: `v1/03:350-360` [A]. Ours: upstream labels `ClaudePermissionCard.swift:95-105`.
34. **Context ring threshold 80% (official) vs ours 90%.** Source: `v1/03:321` [A]; `ClaudeUsageRing.swift:19`. Note UX-SPEC §0.1 forbids color change; keep monochrome, consider threshold.
35. **User bubble font 17 to match `chatBodySize`.** Source: UX-SPEC §0.3/§4.1; OCU desktop body 14 is desktop-only. Ours: 14 `ClaudeChatComponents.swift:201`.
36. **Tabular numbers for counters.** Source: `v1/01:497-505` [A]. Ours: status line only `ClaudeStatusLine.swift:167`.
37. **Sidebar branch badge monospace.** Source: `v2/03:24` [A]. Ours: none in row.
38. **Popover shadow tokens.** Source: `06:983,1002` [R]. Ours: none.
39. **Focus ring blue `#2A78D6` + glow `#CDE2FB`.** Source: `06:984,1003` [R]. Ours: none.
40. **Copy decay 2.5 s.** Source: `v1/04:57-62` [A]. Ours: 1.5 s `ClaudeChatComponents.swift:107`.

**Honourable mentions (not counted):** scroll fade 24 pt (`06:6.6.4` vs `ChatTranscript.swift:585`), scroll pinning 150 ms/40 px (`v1/06:206-230`), media deadzone/snap (`v1/05:332-458`), mic-bar gamma (`v1/05:177-205`), code bg `#0D0D0C` (`v1/05:673`).

---

## 13. UNTRUSTED

### 13.1 Internal contradictions in the OCU docs

| Claim A | Claim B | Resolution |
| :--- | :--- | :--- |
| Composer radius 20 px `v1/01:84`, `v1/07` ChatComposer, `AGENTS.md:75` | 12/14 px `v2/01:27`, `v2/03:83`, `v4.29/06:679-703` [R] | **14 px**; v1/AGENTS stale |
| Bubble radius 18 px `v1/01:83` | formula `radius+4` = 12 default / 18 large `v1/03:55` | Ambiguous; 18 is the table value, 12 is the computed default. Treat 18 as the intended large value |
| Scroll fade 28 px, 7-stop mask `v1/01:284`, `v1/04:230-260`, `v1/08` | 24 px `v2/02:139`; 28 px token exists but **no mask consumes it**; actual masks are 24 px hard cuts `v4.29/06:6.6.3-6.6.4` | **24 px hard cut**; 7-stop is inference |
| 7 easings `v1/01:603-608` | 3 official easings `v2/04:60-66`, `v4.29/06:345-368` [R] | **3 easings**; v1 extras are inference |
| `--clay-emphasized #cc5a36` `v1/01:56`, `v1/07:12` | `#c6613f` both modes `v4.29/04:364`, `06:977` [R] | **`#c6613f`** |
| Accent = clay `v1/01:198-201`, `v1/08` focus ring | accent = blue `#184f95`/`#86b6ef` `v4.29/06:584,975-976` [R] | **Blue accent**; clay is brand |
| `--fill-brand-hover` darker `#cc5a36` `v1/01:56` | hover = `#d97757` lighter `v4.29/06:979` [R] | **Lighter hover** |
| Text colors `#151515/#f5f5f5`, `#525252/#a3a3a3`, `#8a8a8a/#666` `v1/08` | `#0b0b0b/#f0efec`, `#52514e/#c3c2b7`, `#898781` both `v4.29/06:972-974,992-994` [R] | **v4.29 runtime values** |
| Button heights XS 20/SM 24/MD 28/LG 32/XL 40 `v1/08`, `v1/07` | xxs 19/xs 23/sm 26/md 30/lg 38 `v1/02:32-38`; compact 24/comfortable 32 `v2/03:87`, `v4.29/06:1010` [R] | v1 tables conflict; use 32 comfortable / 24 compact |
| `--cds-radius` compact 6 px `v2/03:84` | 8 px both densities `v4.29/06:694-703` [A] | **8 px**; v2 wrong |
| `radius--xs/sm/lg` compact 5/7/10, comfortable 6/5/7 `v4.29/04:656-668` | comfortable 6/7/10 `v4.29/06:1016` [R] | v4.29/04 internally inconsistent; use 06 |
| Dark weight compensation −40/−30 `v1/01:383-425` | not confirmed in v4.29; font role chain added 4.4212 `06:6.12.2` | **Unverified**; do not adopt |
| `AGENTS.md:12` clay dark `#cc6b49`, `AGENTS.md:52` border-accent clay | clay both modes `#d97757`; border-accent blue `06:977,997` [R] | AGENTS stale |
| `ChatComposer.tsx:102` still `rounded-[20px]` | docs say 14 px | Repo implementation stale |
| `cds-theme.css:155` focus shadow clay | runtime focus shadow blue `06:984` [R] | Repo implementation stale |
| Skeleton dark base/sheen white `v1/07` issue branch | neutral black 7.5% `v4.29/04:434-449` [R] | **Neutral black** |

### 13.2 Contradictions with the real Claude app (as I know it)

- **User bubble color.** v1 claims `#f0f4f8` (blue tint) `v1/03:65`, `v1/07` ChatMessageBubbles; v4.29 `--bg-tint-blue` is a derived token `cds-theme.css:217`. The real Claude user bubble is a neutral warm gray, not blue. Our `#F4F2F3` is closer than `#f0f4f8`.
- **Bubble radius.** Real Claude bubbles are continuously rounded but not 20 px; 18 px is plausible. The 12 px computed default in v1/03 is likely a compact-density artifact.
- **Composer radius.** Real Claude's composer is a rounded rectangle, not a capsule; 14 px matches. Our 27 px is too round.
- **Accent.** Real Claude uses blue for links/selection/focus, clay for brand/send. v1's clay focus ring is wrong.
- **Dark mode.** Real Claude dark canvas is near-black `#0B0B0B`/`#151515`, not `#1A1915` (v2's "1.x baseline") and not pure `#000`. Our `#141413` is close.
- **Scroll fade.** Real Claude uses a short hard-ish edge fade; the 7-stop gamma mask is likely a doc invention.
- **Haptics/sounds.** The docs are desktop-only and contain no haptic spec; the 30% SFX volume applies to desktop voice mode. Do not treat it as an iOS haptic spec.
- **`--cds-ease-out` two values.** v4.29/04:613-615 notes both `cubic-bezier(.165,.84,.44,1)` and `cubic-bezier(0,0,.2,1)`; the official doc says the former `06:366`. Use the former.

---

## 14. Not applicable (desktop / web-only)

| Item | Source | Why N/A |
| :--- | :--- | :--- |
| Sidebar width 288 px | `v1/01:105` | iPhone sidebar is full-width drawer |
| Sidebar row 28 px | `v2/03:22` | 44 pt touch minimum |
| Titlebar 46–48 px, traffic lights 74 px | `v1/01:104`, `v1/06:75` | macOS chrome |
| Chat max width 672–768 px | `v1/01:106` | iPhone is full width |
| Dialog max widths 400–1152 px | `v1/02:286-293` | iPhone sheets full width |
| Nested dialog blur | `v1/02:305` | Desktop modality |
| Hover/card lift −1.5 px | `v1/01:223` | No hover on touch |
| Container queries 576/480/384/320 | `v1/06:6.5` | Web layout |
| Split-pane docking | `v1/05:5.3` | Desktop panels |
| Gallery 75 vw runway | `v1/05:459-497` | Desktop lightbox |
| Drag-and-drop sidebar reorder | `v1/06:6.2` | Desktop pointer |
| IME composition guard | `v1/03:3.3.2` | WebKit; iOS native handles |
| Rate-limit backoff 5 s/10 min | `v1/06:6.7` | Daemon/client networking, not UI |
| Roving tabindex | `v1/06:6.6` | Desktop keyboard |
| Electron window factory | `v1/07` createClaudeMainWindow | Desktop host |
| Voice personas / TTS / dictation pipeline | `v1/05:5.1.4-5.1.5` | Desktop voice; our voice is in-app |
| 24 kHz TTS, karaoke highlight | `v1/05:5.1.5` | Desktop reading feature |

---

## 15. Source index (real places)

**OCU docs**
- `docs/v1/01-设计哲学与设计令牌体系.md:49-56,76-107,120-145,167-201,223,284,343-379,383-425,427-460,489-505,529-560,592-608`
- `docs/v1/02-基础原子组件与交互控件.md:32-38,205-255,286-293,342-363`
- `docs/v1/03-会话核心流与指令交互引擎.md:42-110,132-190,282-289,317-375`
- `docs/v1/04-动效物理学、着色器与环境光影.md:31-70,158-161,230-260`
- `docs/v1/05-视听多媒体与产物交互物理学.md:124-160,177-205,332-458,459-497,498-540,599-610,671-684`
- `docs/v1/06-系统级桌面架构与协作拓扑.md:75,152-165,206-230,290-330,425-450`
- `docs/v1/07-工程配置与资产代码库总览.md:1-240`
- `docs/v1/08-AI-Agent-前端-UI-与动效开发指南.md:1-258`
- `docs/v2/01-综述与版本边界.md:27-29`
- `docs/v2/02-新增特性深度逆向.md:110,139,150-187,208-220`
- `docs/v2/03-架构重构与对比分析.md:22-27,66-67,83-117,139`
- `docs/v2/04-系统底座全景解密.md:50-66`
- `docs/v4.29.0-4.4212.0/01-综述与版本边界.md`
- `docs/v4.29.0-4.4212.0/03-架构重构与对比分析.md:3.1-3.7`
- `docs/v4.29.0-4.4212.0/04-系统底座全景解密.md:306-330,363-385,434-449,589-616,656-706`
- `docs/v4.29.0-4.4212.0/05-open-claude-ui差异审计.md:5.1.3,5.2.1,5.2.2`
- `docs/v4.29.0-4.4212.0/06-全量CSS扫描与官方规范比对.md:345-430,484-620,679-712,964-1022,1061-1088,1459-1471`
- `docs/v4.29.0-4.4212.0/07-总结与后续工作.md:7.1-7.5`
- `docs/v4.16336.0/01-总体架构与设计令牌体系.md:88-134`
- `AGENTS.md:12-13,39-79,96-140`
- `code-examples/cds-theme.css:11-12,90-108,137-170,184-220,246-264,294-357`
- `code-examples/ClaudeMotionPresets.ts:60-126`
- `code-examples/ChatComposer.tsx:102,145,161,258`
- `code-examples/ChatMessageBubbles.tsx:141-154,361-384`
- `code-examples/McpToolDecisionCard.tsx:84-91,199-213`

**Ours**
- `Packages/PaseoUI/Sources/PaseoUI/Chat/ClaudeStyle.swift:9,89-246,269-301,366-368,432-440`
- `Packages/PaseoUI/Sources/PaseoUI/Chat/EdgeDrawer.swift:19,23-24`
- `Packages/PaseoUI/Sources/PaseoUI/ClaudeSheets.swift:4-80`
- `Packages/PaseoUI/Sources/PaseoUI/Chat/ClaudeChatComponents.swift:64-84,100-107,162,188-211,257-261`
- `Packages/PaseoUI/Sources/PaseoUI/Conversation/ChatComposer.swift:95-130,500,683,708-711,752`
- `Packages/PaseoUI/Sources/PaseoUI/Chat/ClaudePermissionCard.swift:40-41,57-105`
- `Packages/PaseoUI/Sources/PaseoUI/Chat/ClaudeLoader.swift:27-33`
- `Packages/PaseoUI/Sources/PaseoUI/Chat/ClaudeStatusLine.swift:161-190`
- `Packages/PaseoUI/Sources/PaseoUI/Chat/ClaudeHomeHero.swift:100-147`
- `Packages/PaseoUI/Sources/PaseoUI/Conversation/ChatTranscript.swift:585-595`
- `Packages/PaseoUI/Sources/PaseoUI/Sidebar/PaseoSidebar.swift:73-79,299-331,479-491`
- `Packages/PaseoUI/Sources/PaseoUI/Paseo/DesignSystem/Haptics.swift:10-38`
- `Packages/PaseoUI/Sources/PaseoUI/Chat/SoundCues.swift:20-40`
- `Packages/PaseoUI/Sources/PaseoUI/Chat/ClaudeUsageRing.swift:12-56`
- `Packages/PaseoUI/Sources/PaseoUI/Chat/ClaudeToolDetail.swift:120-147`
- `Packages/PaseoUI/Sources/PaseoUI/ClaudeMediaView.swift:84,103-123`
- `docs/UX-SPEC.md:0.1-0.4,1.1-1.4,2,3.1,4.1-4.3,5,6`
