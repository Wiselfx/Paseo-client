# Jank catalog

Every problem found by the W1 passes, the W3 sweep and the audits. Numbers are Debug simulator unless marked R (Release). Raw history:
[docs/perf/W1-findings.md](../docs/perf/W1-findings.md), [docs/perf/overall-perf.md](../docs/perf/overall-perf.md). Commit ids are in `git log`.

## Catalog
| Id | What the user feels | How it showed in numbers | Root cause | Fix (commit) | Before -> after | Rule |
| --- | --- | --- | --- | --- | --- | --- |
| J01 | Warm phone, laggy taps at rest | `busy=100 %`, `fr=9..13`, `body=Shell:40..190` at idle | `State(initialValue: ChatController(...))` in `ChatScreen.init` ran per shell pass; reads fed back | lazy `ChatControllerHolder` (`d4a71cb`) | 10 fps -> 60 fps, silent idle; bodies 20..190/s -> 0 | PF-1, PF-2 |
| J02 | Reply stutters while it streams | 145 `md.appear`/s; `Markdown` bodies 100..250/s | `.id("row:\(seqEnd)")` on streaming prose; markdown view never Equatable (closures; theme colours) | `rowAnchor` (`298cb66`), Equatable view + theme (`d20e8c3`, `6a5d058`) | 113 hitches/766 ms worst -> 33/110 ms; busy 70 -> 28 % | PF-3, PF-4 |
| J03 | Hiccup when the reply ends | 33 appear, 345 ms stall at completion | streaming prose moved to another tree slot | one `answerProse` slot (`628fc0c`) | 345 -> 138 ms | PF-5 |
| J04 | Hiccup at the end of a reply | `md.neq.stream` for all pieces; 3 splits/delta | `isStreaming` to every piece; 4 `@State` writes per delta | tail-only streaming, `PieceMemo` (`1358201`) | all pieces -> tail; splits 3 -> 1 | PF-5, PF-8 |
| J05 | Drawer stutters at its last frame | `Sidebar`/`Composer` bodies at each motion, 52..156 ms stall | `applyRoots` re-assigned hosting roots | `SurfaceFlags` (`9b271ee`) | 52..156 -> 10..36 ms | PF-7 |
| J06 | Composer tiny cost every pass | span `composer.camera` 1..2.3 ms | `isSourceTypeAvailable` in body | `static let` (`9b271ee`) | per pass -> once | PF-6 |
| J07 | Long chat opens late or blank | 1.4..2.3 s stall; 93..115 parses; blank launch | all turns to a lazy stack; estimated bottom; no rows under offset | turn window 16/12, `repinOpen` + nudge (`97ccf22`, `0aa0d6c`) | 2274 -> 1105 ms; parses 9; no blank | PF-12 |
| J08 | Sidebar re-renders at drawer motion | `Sidebar`/`SidebarRoll` bodies 1 per motion | sidebar read `isSurfaceObscured` for a poll | `SidebarUsageDriver` (`b27adb8`) | bodies 1 -> 0 | PF-13 |
| J09 | Blank when a reply arrives in an open chat | blank transcript | open re-seat fought the follow | ends on a new/running turn (`a3c6fab`) | blank -> follows | PF-14 |
| J10 | Typing: stalls per key | 8..14 hitches, 43..48 ms/key | text size recomputed 2 to 3 times/key; re-seat per key | fit memo (`e89626c`), re-seat end (`ec862cb`), env reads moved (`3102d68`) | 43..48 -> <= 22 ms | PF-38 |
| J11 | First scroll over diagrams freezes | one 605..726 ms stall | `WKWebView.init` in the scroll | prewarm (`b20d06e`, `f10f502`) | 605..726 -> 51 -> 27.7 ms (R) | PF-34 |
| J12 | Blank long chat with a tall draft | blank on plain launch | re-seat ended on "insets moved" | ends on composer focus (`b92e930`) | blank -> last message | PF-14 |
| J13 | Typing still janky | `PasteboardImageState`; `mach_msg` under `canPerformAction` | `hasImages` IPC per call | cache (`f24d3e2`) | correct, within noise | PF-16 |
| J14 | Per key: whole chat re-evaluates | `ChatScreen` body 1/key; `_printChanges`: `ConversationStore.draft` | `Binding(get: store.draft)` built in parent | composer reads its own text (`7c2802e`) | 1 -> 0/key; stalls 18..25 -> max 20 ms (R) | PF-18 |
| J15 | Crab/ticker notified per key | extra notification per key | tracked struct assigned per key | `@ObservationIgnored` + `mascotState` (`2d8aeb9`) | one fewer per key | PF-20 |
| J16 | First composer focus re-runs everything | Shell, Sidebar, SidebarRoll, ChatScreen, Composer bodies in the focus window | env closures counted as changed; roots re-assigned | `ShellRootsKey` (`cf4a5db`) | focus bodies -> `Composer,Transcript`; 140+77+48 -> 120 (AX)+46 ms | PF-19 |
| J17 | Shell reruns on every agent update | shell body follows agent | `currentWorkspaceId` read `conversation.agent` | `ConversationStore.workspaceId` (`d62664c`) | no longer follows | PF-25 |
| J18 | Long-chat open: URL scan | 179 of 949 samples | `text[i...].count` per char: O(n^2) | `httpSchemeLength` (`6e324e1`) | quadratic term gone | PF-21 |
| J19 | Long-chat open: media scan | full-conversation scan in `updateTurns` | index built for a sheet nobody opened | lazy `mediaIndex` (`510c546`) | scan off the open | PF-21 |
| J20 | Chat open: voice engine | ~8 of 245 samples | `VoiceAudioEngine()` in every controller init | lazy (`9a8604d`) | off the open | PF-34 |
| J21 | Sidebar/bubbles: date parse per pass | `FormatStyle` ISO parse per agent per pass | no cache | `PaseoDate` cache (`b368d48`, `855a74b`) | micro | PF-31 |
| J22 | Re-seat inside keyboard's first frame | `openpin.fire` in the focus window | armed until insets moved | disarm on `keyboardWillShow` (`54d75bc`) | none in focus window | PF-14 |
| J23 | Long-chat first render slow | UITextView+TextKit1 per inline-code paragraph | text engine | one `Text` + pill renderer (`81b1fb2`) | layout unchanged; open still 0.8..1.1 s | PF-9 |
| J24 | Card width readers per card | 8 `GeometryReader`s | GeometryReader per card | `onGeometryChange` (`af55a67`) | renders correctly | PF-30 |
| J25 | First-focus/code-block cold costs | highlighter, composer view first use | cold init | `ComposerWarmup` at idle (`faa1c08`) | keyboard frame unchanged (system) | PF-34 |
| J26 | Open: all pieces built cold | warm spans 13 messages ~25 ms off main | everything on main at open | `ProseWarmup`, thread-safe `ProseCache`, `CodeHighlightMirror` (`9f14d48`, `75e289d`) | highlighted blocks one layout | PF-11, PF-31 |
| J27 | Long chat open 2.6 s outliers | `Markdown:371`, `Transcript:234` bodies | window grew while re-seating | guard on reveal (`dbfda10`) | outliers gone | PF-28 |
| J28 | Open 1.2..1.4 s outliers (1 in 3) | content 33k..48k pt; 3..13 re-seats | `scrollTo(edge:.bottom)` on estimated bottom | `scrollTo(id:"bottom")` (`c07b6a0`) | 53/96/96/154/196 -> 53/95/53/53/53 bodies; 670 ms median | PF-29 |
| J29 | Sidebar re-renders on any update | whole sidebar | body read agent/workspace lists | `SidebarDirectoryHost`, `SidebarWorkspaceRow` Equatable (W3) | code-read | PF-24 |
| J30 | Stores notify on equal pushes | readers re-run | `@Observable` setter always notifies | write-on-change in 4 stores (W3) | code-read | PF-25 |
| J31 | Files page: alert keystrokes lag | re-sort per `@State` write | no memo | `FileListMemo` (W3) | code-read | PF-26 |
| J32 | Launch: nine font calls | before first frame | per-font registration | one `CTFontManagerRegisterFontURLs` (`aa36c15`) | 9 -> 1 calls | PF-35 |
| J33 | Draft typing waits for disk | JSON+write per key on main | sync persistence | `DraftFileWriter` (`d061427`) | off main | PF-32 |
| J34 | Memory grows with chats opened | every chat kept store+stream | no retention | limit 6 + busy (`d061427`) | bounded | PF-33 |
| J35 | Instrument inflated numbers | 45 of 110 samples under `PaseoPerf` | `Mirror` in `diff`; hit re-checks | removed (`675e14d`) | numbers honest | PF-22 |
| J36 | Find: window start scanned per body pass and per scroll frame | `firstTurnIndex` was `turns.firstIndex { ... }`: O(n) per read | linear scan of an ordered array | binary search over `lastRowSeq` (`040f0be`); `FindNavigationIndexTests` | code-read: O(n) -> O(log n) | PF-9/21; [hot paths](PATTERNS/hot-paths-and-indexing.md) |
| J37 | Find: jump tick allocated every built index | `all.indices.filter { ... }` per 100 ms tick | array + closure per element | `FindNavigation.nearestIndex` outward search (`040f0be`) | code-read: O(n) allocation -> O(distance) | PF-21 |
| J38 | Find: fetch outlived a close | discarded `Task { ... }` in `scrollToMatch` | no handle, no cancel | `TranscriptJumpRunner.runAfterFetch` stores and cancels (`040f0be`) | code-read | PF-36 |
| J39 | Find: dictionary write per geometry change | `FindRowProbe.report` wrote `frames[seqEnd] = frame` | growing table + hash per frame | one `lastReport` slot, compare-first (`040f0be`) | code-read | PF-9 |
| J40 | Find: per-step flags re-ran the transcript | `isFollowing = false` etc. on every step | literal writes to `@Observable` | `if x { x = false }` guards (`040f0be`) | code-read | PF-25 |


## Symptom -> likely cause -> where to look
| Symptom | Likely cause | Where to look |
| --- | --- | --- |
| Phone warm at rest, `busy` high at idle | a body loop: object built in `init`/`@State` default, feedback through a read | `-paseo-perf` idle; `body=`; `diff.*.none`; PF-2 |
| Streaming reply stutters | `.id` on a moving value; non-Equatable pieces; flag fed to all pieces | `md.appear`, `Markdown` bodies; PF-3/4/5 |
| Every keystroke re-runs a big screen | `Binding(get:)` or env read in the parent | `-paseo-perf-changes` (`perf.why`): the Observation key path; PF-18 |
| Stall on first composer focus | roots re-assigned (non-comparable env); else system keyboard | focus-window `body=`; if only `Composer,Transcript`: floor ~340..390 ms (D03/D04) |
| First tap after launch costs ~100 ms | AXe accessibility initialisation | run `ui reading` first (PF-23); not an app cost |
| Drawer stutters at first/last frame | roots or environment re-assigned; sidebar reads a flag | `Sidebar`/`Composer` bodies per motion; PF-7/13 |
| Long chat opens blank / mid-chat / slow | whole history in the stack; edge re-seat; reveal during re-seat | `openpin.fire`, content height, markdown bodies; PF-12/28/29 |
| First scroll over diagrams/images freezes | `WKWebView.init`, image decode on main | `perf.hot` leaf `__ulock_wait2`; PF-34 |
| Scrolling janks on long rows | non-Equatable rows; GeometryReader; offscreen effects; eager list | `body=` per row; PF-4/30/37 |
| Hitch only in Debug | unspecialised generics (`swift_conformsToProtocol`) | repeat in Release (3 runs) before fixing |
| `swift_conformsToProtocol` under `ShellView.body` | the instrument (`Mirror` in `diff`) | check the caller is not `PaseoPerf` (PF-22) |
| Memory grows over a session | unbounded cache, stream or retained stores | PF-31/33; Allocations |
| Edit shows no `body=` change | `==` is never true (colours, closures) | compare by drawn inputs (PF-4) |
| Find a match lags on a long chat | O(n) window-start scan, index array per tick, flag writes per step | `-paseo-perf` while jumping; PF-9/21/25; [hot paths](PATTERNS/hot-paths-and-indexing.md) |
