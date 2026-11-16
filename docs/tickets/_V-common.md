# V-round common rules (rich media repair)

Read `AGENTS.md` first (R-1 narrow observation, R-2 equatable rows, R-3 UIKit for finger motion, R-4 tokens, R-7 upstream first). Then
`docs/research/14-rich-ui-plan-full.md` §1.3 (sizes and no layout jumps), §1.4 (motion), §1.5 (accessibility), §1.6 (performance rules) and §4 (media).

The owner's bar, in his words: mission-critical smoothness, taste, looks, responsiveness, no jitter, no jank, perceived smoothness and performance. Concretely:
- A card reserves its final size before its content arrives; content arriving never moves a row or the scroll position. No fade-in flash on a second visit.
- Nothing runs per scroll frame: no work in `body` that scans, parses, decodes or measures. Decode and file work off the main actor. Publish state only when it changes.
- Rows stay `Equatable` values with the actions object from the environment; no closures in row initializers.
- A failure draws an honest, calm state in the same reserved box, with Retry where it helps. Never an endless spinner: every wait has an end (success, failure with text, or a tap to start).
- Reduce Motion respected through `Motion.resolved(reduceMotion:)`; tokens only (`Palette`, `Typography`, `Space`, `Radius`, `Motion`).
- Use the roads upstream and the host already give (R-7). Use the repo's existing pipeline (`MediaPipeline`, `MediaMetadataCache`, `RichActions`, `PaseoCard`); no parallel implementations.

You cannot compile or run the UI here (`swiftc -parse` only; Core builds and tests on Linux with `swift build --build-tests && swift test`). So re-read every change as a compiler and as a layout engine would,
and say in your final message what the lead must eyeball on the simulator. Never push or merge. One commit per item. No force unwraps. Existing tests: the owner authorised changing tests that a behaviour change makes wrong;
change only those, list each (file, test, why) in your final message, and add tests for new Core logic in new files.

Evidence from the owner's simulator session is in `/home/paseo/dev/feedback/rich-media-findings.md` (read it first, items 1 to 22). The test conversation is agent `9972fe65` on the test daemon:
`export PASEO_PASSWORD=<test-daemon-password>; unset PASEO_WORKSPACE_ID; paseo --host localhost:6768 logs 9972fe65` shows exactly what the model sent. Sample files: `/home/paseo/paseo-test-work/rich/`
(red.png, green.png, blue.png 640x400; tone.wav 6 s; clip.mp4 4 s 640x360; hello.py). Never message or prompt any claude-provider agent.
