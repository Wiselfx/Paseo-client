#if canImport(UIKit)
import SwiftUI

/// The file viewer's header: back to the folder, the file's name, and the actions: Cancel and
/// Save while editing; otherwise mention in chat, copy, edit, and the overflow menu.
struct FileViewerTopBar: View {
    let fileName: String
    let backLabel: String
    /// The workspace-relative path "Mention in chat" sends.
    let relativePath: String
    let isEditing: Bool
    let isSaving: Bool
    let isPreparingSave: Bool
    let copied: Bool
    /// A save just succeeded: the copy button gives way to a checkmark.
    let showsSaved: Bool
    let canCopy: Bool
    let canEdit: Bool
    /// "Reveal in Files page"; nil hides the action (e.g. Preview sheets).
    let onReveal: (() -> Void)?
    let onBack: () -> Void
    let onCancelEditing: () -> Void
    let onSave: () -> Void
    let onCopy: () -> Void
    let onEdit: () -> Void
    let onShare: () -> Void
    let onSaveToFiles: () -> Void

    @Environment(\.mentionInChat) private var mentionInChat

    var body: some View {
        HStack(spacing: Space.sm) {
            Button(action: onBack) {
                HStack(spacing: Space.xs) {
                    Image(systemName: "chevron.left").font(.glyph(.small, weight: .semibold))
                    Text(backLabel).font(.paseo(.footnote)).lineLimit(1)
                }
                .foregroundStyle(Palette.secondaryInk)
                .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                .contentShape(.rect)
            }
            .accessibilityLabel("Back to \(backLabel)")
            Spacer(minLength: Space.xs)
            // A ternary with `fileName` infers `String`, which would leave "Editing" untranslated.
            Group {
                if isEditing {
                    Text("Editing \(fileName)")
                } else {
                    Text(verbatim: fileName)
                }
            }
            .font(.paseo(.codeSmall))
            .foregroundStyle(Palette.secondaryInk)
            .lineLimit(1)
            .truncationMode(.middle)
            Spacer(minLength: Space.xs)
            if isEditing {
                Button("Cancel", action: onCancelEditing)
                    .font(.paseo(.footnote))
                    .foregroundStyle(Palette.secondaryInk)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(.rect)
                    .accessibilityLabel("Discard edits")
                    .accessibilityInputLabels(["Cancel", "Discard edits"])
                Button(action: onSave) {
                    if isSaving {
                        ProgressView().controlSize(.small).frame(width: 44, height: 44)
                    } else {
                        Text("Save")
                            .font(.paseo(.footnote, weight: .semibold))
                            .foregroundStyle(Palette.ink)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(.rect)
                    }
                }
                .disabled(isSaving)
                .accessibilityLabel("Save file")
            } else {
                if let mentionInChat {
                    Button {
                        mentionInChat(relativePath)
                    } label: {
                        Image(systemName: "at")
                            .font(.glyph(.regular, weight: .light))
                            .foregroundStyle(Palette.tertiaryInk)
                            .frame(width: 44, height: 44)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Mention in chat")
                }
                if showsSaved {
                    Image(systemName: "checkmark")
                        .font(.glyph(.small, weight: .semibold))
                        .foregroundStyle(Palette.successInk)
                        .frame(width: 44, height: 44)
                        .accessibilityLabel("Saved")
                } else if canCopy {
                    Button(action: onCopy) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.glyph(.regular, weight: .light))
                            .foregroundStyle(copied ? Palette.ink : Palette.tertiaryInk)
                            .frame(width: 44, height: 44)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(copied ? "Copied" : "Copy file contents")
                } else {
                    Color.clear.frame(width: 44, height: 44)
                }
                if canEdit {
                    Button {
                        Haptics.selection()
                        onEdit()
                    } label: {
                        Image(systemName: "pencil")
                            .font(.glyph(.regular, weight: .regular))
                            .foregroundStyle(Palette.secondaryInk)
                            .frame(width: 44, height: 44)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Edit file")
                } else {
                    Color.clear.frame(width: 44, height: 44)
                }
                Menu {
                    if let onReveal {
                        Button("Reveal in Files page", systemImage: "folder", action: onReveal)
                    }
                    Button("Share…", systemImage: "square.and.arrow.up", action: onShare)
                    Button("Save to Files…", systemImage: "square.and.arrow.down", action: onSaveToFiles)
                } label: {
                    Group {
                        if isPreparingSave {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "ellipsis")
                                .font(.glyph(.regular, weight: .medium))
                                .foregroundStyle(Palette.secondaryInk)
                        }
                    }
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("More file actions")
            }
        }
        .padding(.horizontal, Space.sm)
        .frame(minHeight: 48)
    }
}
#endif
