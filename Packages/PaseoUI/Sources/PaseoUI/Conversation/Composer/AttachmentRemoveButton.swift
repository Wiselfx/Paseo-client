#if canImport(UIKit)
import Foundation
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import PaseoStore

/// The "x" on an attachment pill's corner: always a separate action from the pill itself.
struct AttachmentRemoveButton: View {
    /// What the button removes, said by VoiceOver ("Remove report.pdf").
    let label: String
    let onRemove: () -> Void

    var body: some View {
        Button {
            onRemove()
        } label: {
            Image(systemName: "xmark")
                .font(.glyph(.small, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Palette.mediaControl, in: .circle)
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .offset(x: 6, y: -6)
        .accessibilityLabel(label)
    }
}
#endif
