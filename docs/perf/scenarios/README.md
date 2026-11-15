# Perf scenarios

Run on the gate's simulator with the app built from your branch (`install <branch>`), launched with
`-paseo-perf` (`perf-run.sh` relaunches unless you pass `--keep`). The test daemon is port 6768
(only the `pi` provider, never a claude provider). Setup of the long test chats is at the bottom.

```sh
export PASEO_PASSWORD=simtest-pass; unset PASEO_WORKSPACE_ID
docs/perf/scenarios/perf-run.sh [--keep] <name> "<gate do steps separated by |>"
AGENT=<agent id> docs/perf/scenarios/stream.sh        # scenario 2
```

Output: the app's window lines after the scenario started (the Mac's clock), then
`VERDICT windows= frames= hitches= dropped= longest-gap= worst-frame= stalls>8ms= stall-max= busy-avg= scroll-frames=`.
A hitch is a frame later than 1.5 budgets. Compare with the budgets in `PERFORMANCE-RULES.md`.

| # | Scenario | Steps (gate `do` syntax) |
| --- | --- | --- |
| 0 | Idle after launch | `perf-run.sh idle "wait 10"` (fresh launch; expect no window lines) |
| 1 | Chat scroll | `--keep chat-scroll "scroll up \| scroll up \| scroll up \| wait 1 \| scroll down \| scroll down \| scroll down"`; drag: `swipe 220 300 220 800`; "Back to the end": `tap Back to the end` |
| 2 | Streaming | `stream.sh` (asks the test agent for a long markdown reply with inline code and fences, 3 steps of `wait`); with scrolling: `stream.sh "scroll up \| wait 3 \| scroll down \| wait 15"` |
| 3 | Prose, dynamic type | scenario 1 after `textsize ax5` / `xs`, then `appearance light` / `dark` |
| 4 | Code blocks | open a turn with a 300-line fence; `swipe 300 400 100 400` scrolls it sideways; `tap Copy code`; `tap Expand code` |
| 5 | Think blocks | a turn with `Thought` rows: `tap <row label>` to expand and collapse |
| 6 | Sidebar and panel | `--keep sidebar "edge left \| wait 2 \| tapxy 420 500 \| wait 2 \| edge left \| wait 2 \| tapxy 420 500 \| wait 2"`; panel: `edge right`, close with `tapxy 40 500`; keyboard up: `tapid composer.draft` first |
| 7 | Rich media | open the rich-media chat (`Search`, type the title, tap the result), then scenario 1 over the image, gallery, diagram and card turns |
| 8 | New session | `--keep new-session "edge left \| wait 2 \| tap New session \| wait 3 \| tapid composer.draft \| wait 2 \| type <text> \| wait 2 \| tap Model, thinking and mode \| wait 2"` |

Opening a chat from the gate: `do tap Open sidebar | tap Search | type <title> | tapxy 220 262` (the first result).
Finish a scenario on a normal screen (a chat, sidebar closed).

## Test chats

Generate with `paseo --host localhost:6768 run/send` on the pi provider (`pi/opencode-go/beam-free`):
ask it to reply with exactly a supplied markdown block (prose, a 12 row table, code fences of 20 to 300
lines in several languages, images by local path, mermaid) many times, so the chat is long and the content
is yours. Keep chats under about 10 000 pt of content for scroll and stream runs; very long chats
(60 000 pt) are for the open-a-long-chat scenario.

Known measurement limits: the gate builds Debug; `swipe` and `scroll` have fixed speeds; `applog` keeps the
newest 300 lines (a window line per second of activity fits about five minutes). See `GATE-UPGRADE.md`.
