#if canImport(UIKit)
import SwiftUI

/// A titled field in the speech provider sheet: the title, the control, and a hint under it. An
/// env var hint ("Set by …") wins over the regular hint.
struct SpeechFieldColumn<Content: View>: View {
    let title: String
    let hint: String?
    let envHint: String?
    private let content: Content

    init(
        title: String, hint: String?, envHint: String?, @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.hint = hint
        self.envHint = envHint
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(title)
                .font(.paseo(.body))
            content
            if let hint = envHint ?? hint {
                Text(hint)
                    .font(.paseo(.footnote))
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, Space.lg)
        .padding(.vertical, 10)
        .frame(minHeight: 60, alignment: .leading)
    }
}
#endif
