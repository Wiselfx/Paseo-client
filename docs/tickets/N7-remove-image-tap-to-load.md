# N7: remove the image tap-to-load code (it can never trigger now)

Read `AGENTS.md`, then `docs/tickets/_L-common.md`, then this file.

## Why
Images always load now (commit 322019f): `mediaFetchPolicy` returns `.automatic` for `.remoteImage`, `.daemonImage` and
`.thumbnail`, and `mediaDownloadCap` returns nil. The tap-to-download box for images, the "tappedLoad" state and the
cap plumbing are dead. User rule: whatever is unused goes. Upstream has no tap-to-load rule (R-7).

## Owns (touch only these)
- `Packages/PaseoUI/Sources/PaseoUI/Conversation/Prose/Rich/ClaudeRichBlocks.swift`
- `Packages/PaseoUI/Sources/PaseoUI/Conversation/Prose/Rich/RichGalleryCard.swift`
- `Packages/PaseoUI/Sources/PaseoUI/Conversation/Screen/ChatMediaSheet.swift`
Do NOT touch `VideoCard.swift`, `AudioRow.swift`, `MediaFetchPolicy.swift`, `MediaPipeline.swift` or any test: video and audio
still wait for a tap and still use the policy.

## Steps
1. In the three files, find every use of `mediaFetchPolicy(kind: .remoteImage` / `.daemonImage`, `mediaDownloadCap(kind: .remoteImage` /
   `.daemonImage`, and the state they feed (`policy`, `capBytes`, `tappedLoad`, `showsTapBox`, the "Tap to download" box and its
   `Text("Tap to download")`, the `.tapToDownload` / `.cacheOnly` switch arms that only serve images).
2. Delete them and simplify: the image always starts loading when the card appears; pass `capBytes: nil` where a cap argument is
   still required by `MediaPipeline`. KEEP: the failure box with Retry, the `.tooLarge` failure display only if the pipeline can
   still return it (check `MediaPipeline.swift`; if it can, keep the failure message but not the tap box), the offline failure
   text (`.cacheOnly`/offline) if it is reachable via `linkCondition.offline`.
3. Do not change any visible copy, layout or behaviour for images that load. No new features.

## Proof
`swiftc -parse` on each edited file; grep that `showsTapBox`, `tappedLoad` and `Tap to download` no longer appear in your three
files (the `Download N images` gallery card is gallery-level: if it exists only for the tap policy, remove it too, else keep).
`style-lint.sh` shows no new hits. Commit `N7: remove image tap-to-load code` with `Upstream: none (removal of a non-upstream rule)`.

## Final message
What you deleted per file, the parse results, anything you were unsure about or left because it still serves video/audio.
