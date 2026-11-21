#if canImport(UIKit)
import PaseoStore
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The composer's "+" menu: photo library, camera, files, a pasted image, a forge issue or PR, a
/// file mention, and the agent actions. Its own view, so the pasteboard check and the labels it
/// reads do not belong to the composer's body.
struct ComposerAddMenu: View {
    @Binding var photoSelection: [PhotosPickerItem]
    @Binding var showCameraPicker: Bool
    @Binding var showFileImporter: Bool
    let cameraAvailable: Bool
    let forgeIsGitLab: Bool
    let onPasteImage: () -> Void
    let onAddForge: () -> Void
    let onMentionFile: () -> Void
    let onNewAgent: () -> Void
    let onCopyAgentId: () -> Void

    var body: some View {
        Menu {
            PhotosPicker(selection: $photoSelection, maxSelectionCount: 10, matching: .images) {
                Label("Photo library", systemImage: "photo.on.rectangle")
            }
            if cameraAvailable {
                Button("Camera", systemImage: "camera") { showCameraPicker = true }
            }
            Button("Files", systemImage: "folder") { showFileImporter = true }
            // The field takes ⌘V; the menu offers the same thing for discovery, and attaches
            // every image on the pasteboard (D2 §2).
            if PasteboardImageState.shared.hasImages {
                Button("Paste image", systemImage: "doc.on.clipboard", action: onPasteImage)
            }
            Button(
                forgeIsGitLab ? "Add issue or MR" : "Add issue or PR",
                systemImage: "arrow.triangle.branch", action: onAddForge)
            Button("Mention a file", systemImage: "at", action: onMentionFile)
            Divider()
            Button("New agent", systemImage: "plus.bubble", action: onNewAgent)
            Button("Copy agent ID", systemImage: "doc.on.doc", action: onCopyAgentId)
        } label: {
            Image(systemName: "plus")
                .font(.glyph(.regular, weight: .regular))
                .frame(width: ComposerMetrics.controlSize, height: ComposerMetrics.controlSize)
                .foregroundStyle(Palette.ink)
                .background(Palette.chip, in: .circle)
                .frame(width: ComposerMetrics.hitSize, height: ComposerMetrics.hitSize)
                .contentShape(.rect)
        }
        .accessibilityLabel("Add to agent")
    }
}
#endif
