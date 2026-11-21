#if canImport(UIKit)
import SwiftUI
import UIKit

/// A command-center results group's heading, exposed to VoiceOver's headings rotor.
struct SearchSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.paseo(.footnote, weight: .medium))
            .foregroundStyle(Palette.secondaryInk)
            .padding(.top, Space.lg)
            .padding(.bottom, Space.xs)
            .padding(.horizontal, Space.xl)
            .accessibilityAddTraits(.isHeader)
    }
}
#endif
