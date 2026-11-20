#if canImport(UIKit)
import SwiftUI

/// The blank strip that stands in for the draft's workspace line and resting composer.
struct HomeHeroRestingFooter: View {
    var body: some View {
        Color.clear.frame(height: HomeHeroMetrics.draftChrome)
    }
}
#endif
