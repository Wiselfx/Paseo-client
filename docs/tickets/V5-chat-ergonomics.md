# V5: chat ergonomics (font size, keyboard, composer)

Worker: DeepSeek (the chat worker). Read `AGENTS.md`, `docs/UX-SPEC.md` §0 and §4.1 first. User feedback
from the device, 2026-11-09.

## 1. Chat text is too small
Assistant prose is 14 pt (`Chat/ClaudeChatComponents.swift:294`, `ClaudeMarkdownTheme(... bodySize: 14)`).
Target the Claude iOS app: **assistant prose 17 pt serif**, user bubbles 17 pt sans, composer text 17 pt,
headings and code scaled to match (keep the theme's existing ratios; code ~15). All of it must still scale
with Dynamic Type and our text-size setting (`ClaudeTextScale`): check the theme uses `relativeTo:` and the
content multiplier the way `ClaudeTypography.serif` does. Check line heights/paragraph spacing still read well
at 17.

## 2. Tapping outside doesn't close the keyboard
Tapping a message, the transcript background, or anywhere outside the composer must dismiss the keyboard,
like Claude/iMessage. Also `.scrollDismissesKeyboard(.interactively)` on the transcript. Don't break taps
on links, buttons, context menus, or text selection; don't add a full-screen tap catcher that swallows
gestures (use a simultaneous tap on the scroll content, or focus state cleared on tap).

## 3. Long text overflows the composer
A long message grows the composer until its buttons go under the keyboard. The text field must cap its
height (about 40% of the space above the keyboard, ~8–10 lines on an iPhone) and scroll inside itself
after that. The composer's controls row (attach, chip, mic, send) stays visible above the keyboard at all
times, in `ChatComposer.swift` and `DraftChatView.swift` alike.

## 4. Composer shape follows Claude
In Claude, the minimal one-line pill only exists on the hero/new-session screen before the first send.
Once a conversation exists, the composer is **always** the expanded two-row card (text row + controls row),
focused or not. So: `DraftChatView` keeps the dynamic pill→card behaviour (UX-SPEC §4.1); `ChatComposer`
in an existing conversation is always the card. Update UX-SPEC §4.1 to say so.

## Off-limits
Another worker is doing a performance pass on `Chat/EdgeDrawer.swift`, `Chat/PaseoShellView.swift` and
scroll handlers in `Conversation/ChatTranscript.swift`. You may touch `ChatTranscript.swift` only for the
keyboard dismissal; keep that change small.

## Compile gate
Push your branch (never `main`/`foundation`): `git push -q origin v5-chat-ergonomics`, then
`ssh -i ~/.ssh/paseo_build_ed25519 -o BatchMode=yes claude@host.orb.internal build v5-chat-ergonomics`.
Loop until `** BUILD SUCCEEDED **` with no new warnings.

## Done
Mac gate green, PaseoCore green if touched, commit `V5: chat ergonomics` on `v5-chat-ergonomics`.
