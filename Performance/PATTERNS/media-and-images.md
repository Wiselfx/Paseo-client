# Media and images

Rules: PF-10, PF-30, PF-31, PF-34. MUST: M13, M14, M18, M29, M31. Checks: C13, C09, H07, H21, H22, F04, F13.

## 1. Read a card's width with `onGeometryChange`, not a GeometryReader per card (`af55a67`; 8 card kinds + tables)
BAD:
```swift
GeometryReader { proxy in
    Color.clear.onAppear { width = proxy.size.width }.onChange(of: proxy.size.width) { _, new in width = new }
}
```
GOOD:
```swift
Color.clear.onGeometryChange(for: CGFloat.self) { $0.size.width } action: { newWidth in
    if width != newWidth { width = newWidth }          // written on change only
}
```

## 2. Start the shared web view at a quiet moment (`b20d06e`, `f10f502`; first scroll over cards 605 to 726 -> 51 -> 27.7 ms Release)
BAD: the first diagram/SVG card builds `WKWebView` in the middle of a scroll and waits for WebKit's content process (`__ulock_wait2`, 112 of 260 samples).
GOOD: `RichWebSnapshotRenderer.shared.prewarm()` runs one second after the open re-seat ends (fallback 8 s), never inside the open:
```swift
.onChange(of: openPin) { _, pinned in
    guard !pinned else { return }
    Task { @MainActor in try? await Task.sleep(for: .seconds(1)); guard !scrollHeld else { return }; RichWebSnapshotRenderer.shared.prewarm() }
}
```
One shared `WKWebView`, never one per block.

## 3. Decode at the drawn size, off main (read end to end in pass 8.6; nothing needed changing)
The pipeline already does it: `CGImageSourceCreateThumbnailAtIndex` (`ImageDownsampler`, width-exact, `ShouldCacheImmediately`), decode in the pipeline actor/detached tasks,
`NSCache` with count and cost limits and memory-warning eviction, a failure memo, coalesced requests, revision-validated disk keys, off-main poster and waveform work.
BAD in a body: `Image(uiImage: UIImage(data: data)!)`, `AsyncImage`. GOOD: ask the pipeline for the size you draw and show reserved space until it answers.

## 4. Reserve space; never change a row's height after it appears (PF-10)
Cards reserve their size; a card whose height must follow content (web view height reporter) writes `@State` on change only. Content height moved 6300 -> 9100 pt while scrolling up before reservation.

Cold costs: link cards fetch metadata only on cheap links (Low Data Mode gets the text-only row); video/audio load on tap (`MediaFetchPolicy`).

If you remember nothing else:
- Sizes come from `onGeometryChange` written on change; no GeometryReader per card.
- One shared web view, warmed at a chosen quiet moment; images are decoded at drawn size off main through the pipeline, caches bounded by count and cost.
- A row reserves its size before it appears.
