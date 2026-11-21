#if canImport(UIKit)
import Foundation
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import PaseoStore

/// A forge issue/change-request pill: kind icon, "#42" and the kind word.
struct AttachmentForgePill: View {
    let item: ComposerAttachmentItem
    let attachment: AgentAttachment

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.glyph(.regular, weight: .light))
                .foregroundStyle(Palette.secondaryInk)
                .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.fileName)
                    .font(.paseo(.caption, weight: .medium))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .frame(maxWidth: 110, alignment: .leading)
                Text(Self.kindWord(attachment))
                    .font(.paseo(.caption))
                    .foregroundStyle(Palette.tertiaryInk)
                    .lineLimit(1)
                    .frame(maxWidth: 110, alignment: .leading)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(minHeight: 56)
        .background(Palette.panel, in: .rect(cornerRadius: Radius.md))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.md).strokeBorder(Palette.cardBorder, lineWidth: 1)
        }
    }

    private var symbol: String {
        switch attachment {
        case .forgeChangeRequest: "arrow.triangle.branch"
        case .forgeIssue: "exclamationmark.circle"
        default: "doc"
        }
    }

    /// "Pull request", "Merge request" or "Issue": under the number, and in the pill's spoken label.
    static func kindWord(_ attachment: AgentAttachment) -> String {
        switch attachment {
        case .forgeChangeRequest(let forge):
            forge.forge?.lowercased() == "gitlab" ? "Merge request" : "Pull request"
        case .forgeIssue: "Issue"
        default: "Attachment"
        }
    }
}
#endif
