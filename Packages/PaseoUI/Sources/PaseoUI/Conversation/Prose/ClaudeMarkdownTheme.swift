#if canImport(UIKit)
    /// Theme values follow `docs/research/08-dsh-live-observation.md` §6: serif body, 12 pt between
    /// blocks, mono code. Sizes are measured at Claude's 17 pt body (V5); headings and code are
    /// ratios of `bodySize`, so the whole ladder follows the size setting and Dynamic Type.
    /// Claude's uncaptured rich-block metrics remain provisional.
    public struct ClaudeMarkdownTheme: Equatable, Sendable {
        public var bodyFont: Font
        public var headingFonts: [Font]
        public var codeFont: Font
        public var foreground: Color = Palette.ink
        public var secondary: Color = Palette.secondaryInk
        public var link: Color = Palette.proseLink
        public var inlineCodeForeground: Color = Palette.ink
        /// The blockquote's wash: rgba(20,20,19,0.04) light / rgba(250,249,245,0.06) dark.
        public var quoteWash: Color = Palette.quoteWash
        public var codeBackground: Color = Palette.codeSurface
        public var inlineCodeBackground: Color = Palette.inlineCodeFill
        public var tableHeaderBackground: Color = Palette.adaptive(light: 1, dark: 0.16)
        public var rule: Color = Palette.divider
        public var blockSpacing: CGFloat = 12
        public var lineSpacing: CGFloat = 9
        public var listSpacing: CGFloat = 9
        public var tableColumnWidth: CGFloat = 150
        /// The theme is built from one number — the body size in points — so inline strong and
        /// emphasis runs can ask `ProseFonts` for a *real* face (J1 §1: the bundled serif is one
        /// static Regular, so `.weight()` and `.italic()` on it draw Regular).
        public var bodySize: CGFloat = 20
        /// Heading sizes are ratios of `bodySize`: h1 1.5, h2 1.29, h3 1.14, h4 1, h5 0.93, h6 0.86
        /// (the sizes measured at 14 pt: 21 / 18 / 16 / 14 / 13 / 12).
        public static let headingRatios: [CGFloat] = [1.5, 1.286, 1.143, 1, 0.929, 0.857]

        public init(serifName: String = "Newsreader16pt-Regular", bodySize: CGFloat = 20) {
            foreground = Palette.ink
            // Dynamic Type (shifted by Content size in `RootView`) scales prose; the theme no
            // longer multiplies sizes by hand.
            self.bodySize = bodySize
            bodyFont = ProseFonts.serif(size: bodySize)
            headingFonts = Self.headingRatios.enumerated().map { index, ratio in
                // h1–h3 are bold, h4–h6 semibold, as real faces.
                ProseFonts.serif(
                    size: bodySize * ratio, relativeTo: index < 3 ? .headline : .body,
                    weight: index < 3 ? .bold : .semibold)
            }
            // ~0.88 of the body: 15 pt at the 17 pt Claude body. The code-size step is applied by
            // the code container (`codeTypeScale()`), not baked into the face.
            codeFont = ProseFonts.mono(size: 15)
        }
        /// What decides how a piece lays out: the size ladder, spacing and the two faces. Colours are
        /// Palette tokens that resolve per trait when drawn, and the theme builder makes fresh
        /// colour values on every call (`Palette.adaptive`), so comparing them would make every pair
        /// unequal and defeat `ClaudeMarkdownView`'s Equatable (W1).
        nonisolated public static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.bodySize == rhs.bodySize && lhs.blockSpacing == rhs.blockSpacing
                && lhs.lineSpacing == rhs.lineSpacing && lhs.listSpacing == rhs.listSpacing
                && lhs.tableColumnWidth == rhs.tableColumnWidth && lhs.bodyFont == rhs.bodyFont
                && lhs.codeFont == rhs.codeFont && lhs.headingFonts == rhs.headingFonts
        }

        public static var artifact: Self {
            var theme = Self()
            theme.bodyFont = .system(size: 17)
            theme.bodySize = 17
            theme.codeFont = .system(size: 13, design: .monospaced)
            theme.lineSpacing = 6
            return theme
        }

        /// The face for a run of prose: `font` is the run's base (the body face or one heading of
        /// the ladder), `strong`/`emphasis` the markdown marks on top of it. Returns a real face:
        /// strong is 600 (DSH strong is semibold, not 700), emphasis is the base weight slanted.
        /// A heading keeps its ladder size; anything this theme did not build is left alone.
        public func face(for font: Font, strong: Bool, emphasis: Bool) -> Font {
            guard let role = role(of: font) else { return font }
            let weight: Font.Weight = strong ? .semibold : role.weight
            return ProseFonts.serif(
                size: role.size, relativeTo: role.relativeTo, weight: weight, italic: emphasis)
        }

        /// Which rung of this theme's ladder `font` is: the body, or one heading. `Font` is
        /// equatable, and the ladder is seven values, so this is O(7) with no allocation.
        private func role(of font: Font) -> (size: CGFloat, relativeTo: Font.TextStyle, weight: Font.Weight)? {
            if font == bodyFont { return (bodySize, .body, .regular) }
            guard let index = headingFonts.firstIndex(of: font) else { return nil }
            let ratio = Self.headingRatios[min(index, Self.headingRatios.count - 1)]
            return (
                bodySize * ratio, index < 3 ? .headline : .body, index < 3 ? .bold : .semibold
            )
        }
    }
#endif
