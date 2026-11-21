#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// One link or file row: values in, the jump verb on the actions object (R-2).
struct MediaSheetRow: View, Equatable {
    let item: ConversationMediaItem

    @Environment(\.richActions) private var richActions

    nonisolated static func == (lhs: MediaSheetRow, rhs: MediaSheetRow) -> Bool {
        lhs.item == rhs.item
    }

    var body: some View {
        // The haptic is the controller's: `openMediaItem` plays it as the jump starts.
        Button {
            richActions?.openMediaItem(item)
        } label: {
            HStack(spacing: Space.md) {
                Image(systemName: item.kind.glyphName)
                    .font(.glyph(.regular, weight: .light))
                    .foregroundStyle(Palette.secondaryInk)
                    .frame(width: 28, alignment: .center)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title)
                        .font(.paseo(.body))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    if let subtitle {
                        Text(subtitle)
                            .font(.paseo(.caption))
                            .foregroundStyle(Palette.secondaryInk)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: Space.sm)
                Image(systemName: "chevron.right")
                    .font(.glyph(.small, weight: .semibold))
                    .foregroundStyle(Palette.tertiaryInk)
            }
            .padding(.horizontal, Space.lg)
            .padding(.vertical, Space.sm)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(item.kind.accessibilityNoun), \(item.title)")
    }

    private var subtitle: String? {
        switch item.kind {
        case .link:
            return (item.ref as NSString).lastPathComponent.isEmpty
                ? RichContentDetector.domain(for: item.ref) : (item.ref as NSString).lastPathComponent
        case .file:
            let parent = (item.ref as NSString).deletingLastPathComponent
            return (parent as NSString).lastPathComponent
        default:
            return nil
        }
    }
}
#endif
