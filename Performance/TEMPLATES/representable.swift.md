# New UIViewRepresentable (idempotent update; shape of ClaudeSelectableInlineCode and ComposerUITextView)

```swift
struct ThingField: UIViewRepresentable, Equatable {
    let text: String
    let font: UIFont
    let alignment: NSTextAlignment
    let onChange: (String) -> Void          // not part of equality: a stable object's method

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.text == rhs.text && lhs.font == rhs.font && lhs.alignment == rhs.alignment
    }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        // Idempotent: compare before every assignment; no work when inputs are equal.
        if view.text != text { view.text = text }
        if view.font != font { view.font = font }
        if view.textAlignment != alignment { view.textAlignment = alignment }
        context.coordinator.onChange = onChange
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator: NSObject, UITextViewDelegate { var onChange: (String) -> Void = { _ in } }
}
// call site: ThingField(...).equatable()
```
Expensive sizing: memoise `sizeThatFits` on a key struct listing EVERY input it reads (text, width, font name+size, insets, content-size category, exclusions, padding, line limit);
in `-paseo-perf` re-check each hit once and count a mismatch (`fit.MISMATCH` must stay 0). Cached IPC answers refresh on a notification (`PasteboardImageState`).
Finger tracking is not done here: ESCALATE (R-3).
