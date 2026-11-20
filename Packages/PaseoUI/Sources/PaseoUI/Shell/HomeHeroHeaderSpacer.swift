#if canImport(UIKit)
import SwiftUI

/// The blank strip that stands in for the home header: the same height, no chrome and no
/// button, so a launch frame reserves the header's space without drawing any of it (H4 §1).
struct HomeHeroHeaderSpacer: View {
    var body: some View {
        Color.clear.frame(height: HomeHeroMetrics.headerHeight)
    }
}
#endif
