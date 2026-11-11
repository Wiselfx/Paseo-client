#if canImport(UIKit)
import SwiftUI

/// The height of the container rich cards are laid out in, for the 60 %/70 % media caps (§3).
///
/// Set once per screen — the transcript root, the file viewer — never per card. A card that
/// measured its own window had to render one frame uncapped and then shrink, which reads as a
/// jump, and every image mounted its own `UIViewRepresentable`. An environment value is known
/// before the card's first layout, so the cap is part of the first frame.
///
/// 800 is a phone-height fallback: a host that sets nothing still caps, so no screenshot is
/// ever drawn at full height.
struct RichViewportHeightKey: EnvironmentKey {
    static let defaultValue: CGFloat = 800
}

extension EnvironmentValues {
    var richViewportHeight: CGFloat {
        get { self[RichViewportHeightKey.self] }
        set { self[RichViewportHeightKey.self] = newValue }
    }
}
#endif
