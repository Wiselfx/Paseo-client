# UIKit interop and keyboard

Rules: PF-16, PF-38. MUST: M27, M34, M35. Checks: H15, H26, C09, F03, F08. Floor: first system keyboard show ([DECISIONS.md](../DECISIONS.md) F3).

## 1. Memoise the expensive size (`e89626c`; verified against real layout in perf mode)
SwiftUI asks `sizeThatFits` several times per key; each is a TextKit layout plus language identification.
```swift
private struct FitKey: Equatable { let text: String; let width: CGFloat; let fontName: String; let fontSize: CGFloat
    let insets: UIEdgeInsets; let category: UIContentSizeCategory; let exclusions: Int; let padding: CGFloat; let lines: Int }
private var fitMemo: (key: FitKey, size: CGSize)?
// hit: return memo.size.  In -paseo-perf a hit is re-checked once and `fit.MISMATCH` must stay 0.
```
Key = every input `sizeThatFits` reads; if you cannot list them all, do not memoise.

## 2. `updateUIView` is idempotent (PF-38; `d20e8c3`)
BAD: `uiView.attributedText = built` on every parent pass (an attributed string built and compared per paragraph per token).
GOOD: make the representable `Equatable` on its inputs (`content`, `font`, `theme`, `alignment`, not the closure) with `.equatable()`, and compare before assigning:
`if uiView.text != text { uiView.text = text }`.

## 3. IPC in a hot callback (PF-16; `f24d3e2`)
`UIPasteboard.hasImages` is a round trip to the pasteboard daemon, asked from `canPerformAction(paste:)` (repeatedly while editing) and the composer body.
```swift
@MainActor final class PasteboardImageState { static let shared = PasteboardImageState(); private var cached: Bool?
    var hasImages: Bool { if let cached { return cached }; let v = UIPasteboard.general.hasImages; cached = v; return v }
    // refreshed on UIPasteboard.changedNotification and didBecomeActive
}
```
Same for `UIImagePickerController.isSourceTypeAvailable(.camera)`: `private static let cameraIsAvailable = ...` (1 to 2.3 ms per pass).

## 4. The keyboard: what is ours and what is not
- First software keyboard show ~340 to 390 ms (Release simulator) is UIKit; no invisible prewarm exists (throwaway field: D03; NLTagger: D04). Do not try again.
- Per key: stalls <= 20 ms; `ChatScreen` body 0 per key, `Composer` 1 (PF-18).
- `keyboardWillShow` ends the open re-seat before the insets move (PF-14). Keep the transcript layout independent of the keyboard (`stableViewportHeight`).
- `ComposerWarmup` builds a `ComposerUITextView` off window and 20 SF Symbols once, 2 s after the shell appears; first-focus frame unchanged (~390 ms, system).
- Behaviour switches (`writingToolsBehavior`, `inlinePredictionType`, `spellCheckingType`, TextKit 1 vs 2) are visible changes: owner decision, escalate.

If you remember nothing else:
- Compare before you assign in `updateUIView`; memoise sizing keyed on every input; make the representable Equatable.
- No IPC in a hot callback or a body: cache with a notification refresh.
- The first keyboard show is the system's; do not spend time on it, and never change keyboard behaviour without the owner.
