#if canImport(UIKit)
import SwiftUI

/// One icon button in the media viewer's bottom bar. The title stays in a `Label`, so Voice
/// Control and VoiceOver read it while the icon-only style hides it.
struct ViewerChromeButton: View {
    let title: LocalizedStringKey
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .font(.paseo(.body))
                .frame(width: Metrics.viewerChromeButtonWidth, height: Metrics.hitSize)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
    }
}
#endif
