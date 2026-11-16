# Launch and startup

Rules: PF-2, PF-34, PF-35. MUST: M31, M32, M33. Checks: C39, C27, H23, F16. Floor: cold type reflection ([DECISIONS.md](../DECISIONS.md) F2).

## 1. The first-frame list
Allowed before the first frame: read defaults (`AppModel.init` only reads defaults and wires the host context), register fonts in ONE call, build the shell.
After it (`start()`, `.task`, idle): Keychain read, legacy migration, first connect, warm-ups, web view, voice engine.

## 2. Batch system registration (`aa36c15`)
BAD: nine `CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)` calls (nine round trips to the font daemon) before the first frame.
GOOD:
```swift
let urls = ["InterVariable", "Newsreader", "JetBrainsMonoVariable" /* ... nine names */].compactMap { Bundle.module.url(forResource: $0, withExtension: "ttf") }
guard !urls.isEmpty else { return }
CTFontManagerRegisterFontURLs(urls as CFArray, .process, true, nil)
```

## 3. Lazy until used (`9a8604d`, `e49cf3f`)
`VoiceAudioEngine()` (AVAudioFormat, AVFAudio load) ran in every `ChatController.init`: now built on first use (`voiceEngineIfCreated` for teardown). The `DictationController` is a lazy holder, not a `@State` default per composer init.

## 4. Warm once, at idle, at a chosen moment (`faa1c08`)
```swift
static func scheduleOnce() { guard !done else { return }; done = true
    Task { @MainActor in try? await Task.sleep(for: .seconds(2)); PaseoPerf.measure("warm.composer") { warmComposerField() }
        try? await Task.sleep(for: .milliseconds(300)); PaseoPerf.measure("warm.symbols") { warmSymbols() } /* highlighter engines off main */ } }
```
Created off window, nothing shown. The warm-up must not land inside an interaction: the web view waits for the end of the open re-seat.

## 5. What does not work
- Deferring the sidebar mount 2 s (D02): moved a 200 ms to 1 s stall to a random later moment, onto a tap.
- Paying cold SwiftUI reflection before connecting: views need a `HostSession`. Fewer distinct view types and fewer property wrappers per row is the only lever.
- Keyboard and word-tagger warm-ups (D03, D04).

If you remember nothing else:
- Nothing but defaults, one font call and the shell runs before the first frame.
- Costly objects are built on first use or warmed once at idle, never in `init` and never inside an open.
- A cost moved to a later random moment is not a fix; measure the moment it lands on.
