# Testing

What runs today. The old screenshot, UI and accessibility suites (under `Examples/ClaudeUIDemo`) are
gone: there is no `Examples/` directory in the repository.

| Check | Where | What it checks | Runs on |
|---|---|---|---|
| PaseoCore tests | `Packages/PaseoCore/Tests` (suites `PaseoFixtures`, `PaseoKitTests`, `PaseoProtocolTests`, `PaseoStoreTests`) | Wire decoding against captured fixtures, the connection and relay code, store and timeline logic | Linux: `swift test` in `Packages/PaseoCore` |
| CI | [`.github/workflows/ci.yml`](../../../.github/workflows/ci.yml) | One job, `core`: `swift test` in `Packages/PaseoCore`, in a `swift:6.2` container. Nothing else: no format, project-sync, UI or SDK build job | GitHub Actions, Linux |
| PaseoUI tests | `Packages/PaseoUI/Tests/PaseoUITests` (six files, target declared in `Packages/PaseoUI/Package.swift`) | Markdown, code highlighting, `PaseoFormat`, media, schedule wording | Apple platforms only (the `PaseoUI` module is Apple-only). Never built on Linux |
| Mac build gate | [`Tools/build-gate/build-gate`](../../../Tools/build-gate/build-gate) | Forced-command gate on the Mac. Verbs: `build <ref>`, `ipa <ref>`, `test <ref> <scheme> [filter]` (schemes `PaseoUITests`, `PaseoClient`, `PaseoUI`, `PaseoCore`), `uitest <ref> [filter]`, `analyze <ref>`, `ping`, `sims`, `ls`, `get`, `simreset` | macOS, reached over SSH from the Linux side. Run the PaseoUI tests with `test <ref> PaseoUI` |
| Style lint | [`Tools/style-lint/style-lint.sh`](../../../Tools/style-lint/style-lint.sh) | R-4 token rule: literal fonts, colours, radii and animations outside `DesignSystem/`. A report; exit code is always 0 | Anywhere: `Tools/style-lint/style-lint.sh [path]` |

## Not yet created

A UI-test target that drives the app in an iPhone simulator. The build gate's `uitest` verb expects a
`PaseoUITests` scheme, but `App/PaseoClient.xcodeproj` has no UI-test target yet
(`grep -c UITests App/PaseoClient.xcodeproj/project.pbxproj` prints `0`). Until it exists, `uitest` has
nothing to run.

## Running the tests

On Linux:

```sh
. ~/.local/share/swiftly/env.sh
cd Packages/PaseoCore
swift build --build-tests
swift test
swift test --filter TimelineStateTests   # one suite
```

On the Mac, through the build gate: send the forced command `test <ref> PaseoUI` (`<ref>` is a branch or
commit). The gate prints the commit it tested and the results; the verbs are listed in its header.

## Evidence for a reviewed change

Paste the `swift test` summary line (PaseoCore) or the build-gate result line (PaseoUI, App) into the
review. A build with no errors is not a test run, and a run with zero tests is not a pass. Say which
suites ran; do not claim a suite passed if it did not run.
