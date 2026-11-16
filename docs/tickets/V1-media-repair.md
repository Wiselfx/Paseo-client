# V1: repair what is broken in images, galleries, video, audio and row layout

Read `AGENTS.md`, `docs/tickets/_V-common.md`, then this file. Do the items in order, one commit each, then the final message.

## Items
1. **Host-file cards never load after a relaunch (probable regression from R1).** Images, gallery tiles, video and audio that live on the host show an endless spinner (video, image) or "0:00 / 0:00" (audio)
   after the app is relaunched into a chat. Suspected cause: `ChatController.configureActions()` (`Conversation/Screen/ChatController.swift` ~268-345) registers the daemon-file reader with
   `MediaPipeline.shared.registerDaemonFetch(for: workspaceID, …)` and sets `richActions.daemonWorkspaceID` once, from `store.agent?.workspaceId`; when the chat opens before the agent snapshot arrives
   (R1 restores the last screen at launch), the workspace id is nil, nothing is registered, and the cards wait forever. Prove it by reading the code and the order of events, then fix at the root:
   registration and `daemonWorkspaceID` must follow the agent's workspace id whenever it becomes known or changes, exactly once per id, and must be torn down correctly (`deinit` path). Cards that already
   asked and found no reader must not stay stuck: they must retry when the reader appears (check how `MediaPipeline` reports "no resolver" and make that a retriable, not a cached, failure).
   Also make any remaining endless wait impossible: if no reader can ever exist, show the failure state with Retry.
2. **Images clip at the right edge.** A 640x400 local image draws wider than the text column and is cut off by the screen edge (left edge aligned with the text, right edge past the screen). Find why the width is not bounded to
   the prose column (`RichLocalImage`, `RichRemoteImage`, `ProseMarkdownImage`, `RichGalleryCard`, and the splice container `ClaudeRichSplice`/`ClaudeMarkdownView`: what width is proposed to these views, any `fixedSize`,
   `.frame(maxWidth: .infinity)` under an unbounded parent, `scaledToFill` without clipping, or the measured `width` state feeding the decode size). Fix it at the root so every card (image, gallery, remote image,
   link hero, video poster) is exactly the column width, at every Dynamic Type size, in a bubble and in a prose block.
3. **Assistant block draws over the user's long message.** In the transcript the first block of the assistant reply (a heading) overlaps the last lines of the user's long bubble, and the bubble's time ("12:02")
   lands beside the assistant's first paragraph; short messages are fine. Row heights are wrong for a long bubble. Investigate `ClaudeTurnView` (`Conversation/Transcript/ChatTurns.swift`), `ClaudeUserBubble`
   (`Conversation/Turn/ClaudeChatComponents.swift`, its entrance `.offset`/`.opacity`/animation and the sent-time label added in the last days), the transcript's row measurement/anchoring
   (`ChatTranscript.swift`, `TranscriptChromeState.swift`), and any cached or estimated height. Find the real cause and fix it so no row can overlap another, for any text length, with the time under the bubble.
4. **Video and audio.** After item 1, make sure `clip.mp4` plays inline and `tone.wav` plays and shows its length. Read `Conversation/Prose/Media/VideoCard.swift` and `AudioRow.swift`: the plan says full media
   waits for a tap (`MediaFetchPolicy` video/audio = tapToDownload): the card must then show a tap box with the size, not an endless spinner; after a tap it must download to the cache file, show progress, then play.
   Fix every dead end you find (spinner with no timeout, duration never read, player not created, cap/limit errors with no text).
5. **Gallery.** Check against the plan (C2 in `docs/research/14-rich-ui-plan-full.md`) how three adjacent images should lay out. The app draws a mosaic (one tall tile left, two stacked right). If the plan says a mosaic
   for three, leave it and say so; if it says otherwise, follow the plan. Either way every tile must reserve its size, be clipped to its rounded rectangle and never exceed the column.
6. **Smoothness pass over everything you touched:** list in your final message each place you checked for layout jumps, per-frame work, main-thread decode, and what you changed.

## Owns
`Conversation/Prose/Rich/*` except the artifact/web files (`RichWebContent.swift`, `ArtifactPage.swift`, `SandboxedHTMLView.swift`, `OfflineContentRules.swift`, mermaid files: another worker owns them),
`Conversation/Prose/Media/*`, `Conversation/Prose/ProseMarkdownImage.swift`, `Conversation/Screen/ChatController.swift` (only the registration lines), `Conversation/Transcript/ChatTurns.swift`,
`Conversation/Turn/ClaudeChatComponents.swift`, `Conversation/Transcript/ChatTranscript.swift` and `TranscriptChromeState.swift` only if item 3 needs them.
Commits: `V1.1 host-file reader`, `V1.2 image width`, `V1.3 row overlap`, `V1.4 video and audio`, `V1.5 gallery`, `V1.6 smoothness`.
