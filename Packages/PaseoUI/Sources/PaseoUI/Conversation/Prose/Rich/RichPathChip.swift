#if canImport(UIKit)
import LinkPresentation
import MapKit
import PaseoStore
import SwiftUI
import UIKit
import WebKit

/// A mono path chip: for local image paths that can't be read, and for bare non-image
/// `file://` paths (§1.5). Tap copies the path; the menu also offers Show in Files.
struct RichPathChip: View {
    let path: String
    var glyph: String = "doc.text"

    @Environment(\.richActions) private var richActions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.toast) private var toast
    /// Bumped on a pasteboard copy (no `RichActions`): the copy haptic, once per tap.
    @State private var copyTaps = 0

    var body: some View {
        Button {
            copyPath()
        } label: {
            PaseoCard(content:
                HStack(spacing: 8) {
                    Image(systemName: glyph)
                        .font(.glyph(.small))
                        .foregroundStyle(Palette.secondaryInk)
                    Text(path)
                        .font(.paseo(.codeSmall))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 8)
                    Image(systemName: "doc.on.doc")
                        .font(.glyph(.small))
                        .foregroundStyle(Palette.secondaryInk)
                }
                .contentShape(.rect))
        }
        .buttonStyle(PaseoCardButtonStyle(reduceMotion: reduceMotion))
        .paseoCardMenu(copyTitle: "Copy path", copyText: path, filePath: path)
        .paseoCardAccessibility(kind: "File", title: path, isButton: true)
        .accessibilityHint("Copies the path")
        .paseoFeedback(.light, trigger: copyTaps)
    }

    private func copyPath() {
        if let richActions {
            richActions.copyText(path)
        } else {
            UIPasteboard.general.string = path
            copyTaps += 1
        }
        // The haptic alone is invisible: say what happened.
        toast?.show("Path copied", systemImage: "checkmark")
    }
}
#endif
