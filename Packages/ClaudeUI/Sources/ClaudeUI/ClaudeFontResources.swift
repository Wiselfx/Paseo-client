#if canImport(UIKit)
    import CoreText
    import Foundation

    /// Registers the bundled Newsreader serif for this process. Public so Paseo's DesignSystem can use it.
    @MainActor public enum ClaudeFontResources {
        private static let registration: Void = {
            for name in ["Newsreader", "Newsreader-Italic"] {
                if let url = Bundle.module.url(forResource: name, withExtension: "ttf") {
                    CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
                }
            }
        }()
        public static func register() { _ = registration }
    }
#endif
