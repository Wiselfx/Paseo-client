#if canImport(UIKit)
import SwiftUI

/// 0.5 pt hairline, as the DSH separators are drawn.
struct ClaudeDivider: View {
    var body: some View {
        Rectangle().fill(Palette.divider).frame(height: 0.5)
    }
}
#endif
