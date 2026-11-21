#if canImport(UIKit)
import SwiftUI

/// The artifact page's bar: a close button, the title, and the actions menu (source toggle,
/// copy, reload, share). It holds layout only: every action is a closure the page owns.
struct ArtifactPageTopBar: View {
    let title: String
    /// What the source toggle says while the source is showing ("View diagram" or "View page").
    let hideSourceTitle: String
    let canReload: Bool
    /// True when the card already drew an image: the menu offers "Share image" instead of
    /// "Share as .html".
    let hasShareImage: Bool
    @Binding var showSource: Bool
    let onClose: () -> Void
    let onCopy: () -> Void
    let onReload: () -> Void
    let onShare: () -> Void

    var body: some View {
        HStack {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.paseo(.body))
                    .frame(width: Metrics.hitSize, height: Metrics.hitSize)
                    .contentShape(.circle)
            }
            .glassEffect(in: .circle)
            .accessibilityLabel("Close viewer")
            Spacer(minLength: 8)
            Text(title)
                .font(.paseo(.headline))
                .lineLimit(1)
            Spacer(minLength: 8)
            Menu {
                Button(showSource ? hideSourceTitle : "View source", action: toggleSource)
                Button("Copy source", systemImage: "doc.on.doc", action: onCopy)
                if canReload {
                    Button("Reload", systemImage: "arrow.clockwise", action: onReload)
                }
                if hasShareImage {
                    Button("Share image", systemImage: "square.and.arrow.up", action: onShare)
                } else {
                    Button("Share as .html", systemImage: "square.and.arrow.up", action: onShare)
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.paseo(.body))
                    .frame(width: Metrics.hitSize, height: Metrics.hitSize)
                    .contentShape(.circle)
            }
            .glassEffect(in: .circle)
            .accessibilityLabel("Artifact actions")
        }
        .padding(.horizontal, Space.md)
        .padding(.top, Space.md)
    }

    private func toggleSource() {
        showSource.toggle()
    }
}
#endif
