#if canImport(UIKit)
import SwiftUI

/// The diff palette per row kind: sign glyph, line text and row fill.
@MainActor
enum DiffRowStyle {
    static func contentTint(_ kind: DiffModel.RowKind) -> Color {
        switch kind {
        case .hunkHeader: Palette.tertiaryInk
        case .context, .add, .remove: Palette.ink
        }
    }

    static func signTint(_ kind: DiffModel.RowKind) -> Color {
        switch kind {
        case .add: Palette.diffAddedInk
        case .remove: Palette.diffRemovedInk
        case .context, .hunkHeader: .clear
        }
    }

    static func rowFill(_ kind: DiffModel.RowKind) -> Color {
        switch kind {
        case .add: Palette.diffAdded
        case .remove: Palette.diffRemoved
        case .hunkHeader: Palette.chip
        case .context: .clear
        }
    }
}
#endif
