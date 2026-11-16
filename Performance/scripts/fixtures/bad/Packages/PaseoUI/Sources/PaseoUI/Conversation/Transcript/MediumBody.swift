// features: F19
// Fixture: a view that reads seven environment values is a MANUAL question (H14); body length alone is
// not one any more (C24 fails only over 150 lines).
import SwiftUI

struct ManyEnvBody: View { // hit: H14
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale
    @Environment(\.locale) private var locale
    @Environment(\.calendar) private var calendar
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        Text("\(colorScheme) \(dynamicTypeSize) \(reduceMotion) \(displayScale) \(locale)")
            .padding()
    }
}
