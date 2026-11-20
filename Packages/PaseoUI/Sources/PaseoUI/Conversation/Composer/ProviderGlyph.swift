#if canImport(UIKit)
import PaseoStore
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The provider's mark in the model chip's leading edge. The host catalogue carries per-provider
/// brand SVGs (`ProviderSnapshotEntry.iconSvg`); `ProviderIcon` parses the ones this renderer
/// understands and the shape fills them in ink (§0.1). Anything unparseable — a stroke-only icon,
/// an arc, a `text` glyph — keeps the two-letter monogram, so the chip never shows a hole and
/// still reads the same for every provider.
struct ProviderGlyph: View {
    let label: String
    /// The provider's `iconSvg`, when the catalogue entry carries one.
    var iconSvg: String?

    private let icon: ProviderIcon?

    init(label: String, iconSvg: String? = nil) {
        self.label = label
        self.iconSvg = iconSvg
        self.icon = iconSvg.flatMap(ProviderIcon.parse)
    }

    var body: some View {
        if let icon {
            ProviderIconShape(icon: icon)
                .fill(Palette.secondaryInk)
                .frame(width: 16, height: 16)
                .accessibilityHidden(true)
        } else {
            monogramTile
        }
    }

    private var monogramTile: some View {
        Text(monogram)
            .font(.paseo(.caption2, weight: .semibold))
            .foregroundStyle(Palette.secondaryInk)
            .frame(width: 16, height: 16)
            .background(Palette.panel, in: .rect(cornerRadius: Radius.xs, style: .continuous))
            .accessibilityHidden(true)
    }

    /// "Claude" → "Cl", "openai/codex" → "Co".
    private var monogram: String {
        let letters = label.trimmingCharacters(in: .whitespacesAndNewlines)
            .drop { !$0.isLetter }
        guard let first = letters.first else { return "?" }
        return String(first).uppercased() + String(letters.dropFirst().prefix(1)).lowercased()
    }
}
#endif
