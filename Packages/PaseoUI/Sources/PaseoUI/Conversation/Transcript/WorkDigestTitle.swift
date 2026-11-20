#if canImport(UIKit)
import SwiftUI

/// A work section's title words, in the process voice.
struct WorkDigestTitle: View {
    let text: String
    let ink: Color

    var body: some View {
        Text(text)
            .font(.paseo(.processTitle, weight: .medium))
            .foregroundStyle(ink)
            .lineLimit(1)
    }
}
#endif
