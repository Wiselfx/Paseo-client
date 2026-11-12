import SwiftUI

// MARK: - Widget tokens (Phase E G15)

// The extension's own tiny token file. PaseoUI is app-target code (UIKit scenes,
// the app icon, app-only services) and is deliberately not linked here; these
// mirror the roles the widgets use. `accent` matches `Palette.accent`'s clay,
// which reads on light and dark.

// NOTE: keep in sync with `Palette.accent` (DesignSystem/Palette.swift).
enum WidgetTokens {
    /// The clay accent, identical in both schemes.
    static let accent = Color(red: 217 / 255, green: 119 / 255, blue: 87 / 255)
}
