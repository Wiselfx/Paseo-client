#if canImport(UIKit)
import SwiftUI

/// One tile of the appearance ladder: the theme's canvas with two bars standing in for text.
/// The picker clips and sizes it.
struct AppearanceSwatch: View {
    let choice: ClaudeAppearance

    /// Light canvases carry dark bars, dark canvases light ones.
    private var barsAreDark: Bool {
        switch choice {
        case .light, .system: true
        case .dark, .pureBlack: false
        }
    }

    var body: some View {
        ZStack {
            switch choice {
            case .light:
                Palette.Swatch.light
            case .dark:
                Palette.Swatch.dark
            case .system:
                HStack(spacing: 0) {
                    Palette.Swatch.light
                    Palette.Swatch.dark
                }
            case .pureBlack:
                Palette.Swatch.pureBlack
            }
            VStack(alignment: .leading, spacing: 5) {
                Capsule()
                    .fill((barsAreDark ? Color.black : Color.white).opacity(barsAreDark ? 0.8 : 0.5))
                    .frame(width: 40, height: 5)
                Capsule()
                    .fill((barsAreDark ? Color.black : Color.white).opacity(barsAreDark ? 0.4 : 0.3))
                    .frame(width: 26, height: 5)
                Spacer(minLength: 0)
            }
            .padding(Space.md)
        }
    }
}
#endif
