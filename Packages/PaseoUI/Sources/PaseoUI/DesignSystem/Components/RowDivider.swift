#if canImport(UIKit)
import SwiftUI

/// The hairline between two rows in a group, inset by the row's own leading padding.
struct RowDivider: View {
    var body: some View {
        ClaudeDivider().padding(.horizontal, Space.lg)
    }
}
#endif
