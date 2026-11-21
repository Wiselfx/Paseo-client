#if canImport(UIKit)
import PaseoStore
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// One queued message.
struct QueueRow: View {
    let message: MessageQueue.QueuedMessage
    let onEdit: () -> Void
    let onSendNow: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock")
                .font(.glyph(.small, weight: .medium))
                .foregroundStyle(Palette.tertiaryInk)
            Text(message.text)
                .font(.paseo(.callout))
                .foregroundStyle(Palette.secondaryInk)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            Button {
                Haptics.light()
                onEdit()
            } label: {
                Image(systemName: "pencil")
                    .font(.glyph(.small, weight: .medium))
                    .foregroundStyle(Palette.secondaryInk)
                    .frame(width: ComposerMetrics.controlSize, height: ComposerMetrics.controlSize)
                    .frame(width: ComposerMetrics.hitSize, height: ComposerMetrics.hitSize)
                    .contentShape(.rect)
            }
            .buttonStyle(ComposerPressStyle(reduceMotion: reduceMotion))
            .accessibilityLabel("Edit queued message")
            Button {
                onSendNow()
            } label: {
                Image(systemName: "arrow.up")
                    .font(.glyph(.small, weight: .semibold))
                    .foregroundStyle(Palette.secondaryInk)
                    .frame(width: ComposerMetrics.controlSize, height: ComposerMetrics.controlSize)
                    .frame(width: ComposerMetrics.hitSize, height: ComposerMetrics.hitSize)
                    .contentShape(.rect)
            }
            .buttonStyle(ComposerPressStyle(reduceMotion: reduceMotion))
            .accessibilityLabel("Send queued message now")
        }
        .frame(minHeight: 44)
        .padding(.horizontal, 10)
        .contentShape(.rect)
    }
}
#endif
