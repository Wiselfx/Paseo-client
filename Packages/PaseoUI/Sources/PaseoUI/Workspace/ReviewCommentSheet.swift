#if canImport(UIKit)
import Foundation
import SwiftUI
import UIKit
import PaseoStore

/// The "Leave a comment" sheet: the target's quoted snippet, a multiline body, and
/// Cancel / Comment (or Delete / Save when editing). Mirrors upstream's mobile comment sheet.
struct ReviewCommentSheet: View {
    let title: String
    let targetLabel: String
    let snippet: String?
    let initialBody: String
    let isEditing: Bool
    let onSave: (String) -> Void
    let onDelete: (() -> Void)?
    let onCancel: () -> Void

    @State private var text: String
    @FocusState private var focused: Bool

    init(
        title: String, targetLabel: String, snippet: String?, initialBody: String,
        isEditing: Bool, onSave: @escaping (String) -> Void, onDelete: (() -> Void)?,
        onCancel: @escaping () -> Void
    ) {
        self.title = title
        self.targetLabel = targetLabel
        self.snippet = snippet
        self.initialBody = initialBody
        self.isEditing = isEditing
        self.onSave = onSave
        self.onDelete = onDelete
        self.onCancel = onCancel
        _text = State(initialValue: initialBody)
    }

    private var canSave: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: title, close: onCancel)
            VStack(alignment: .leading, spacing: 14) {
                Text(targetLabel)
                    .font(.paseo(.codeCaption))
                    .foregroundStyle(Palette.secondaryInk)
                if let snippet, !snippet.isEmpty {
                    Text("> \(snippet.prefix(200))")
                        .font(.paseo(.codeCaption))
                        .foregroundStyle(Palette.secondaryInk)
                        .lineLimit(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Palette.quoteWash, in: .rect(cornerRadius: Radius.md))
                }
                ZStack(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("Leave a comment")
                            .font(.paseo(.callout))
                            .foregroundStyle(Palette.tertiaryInk)
                            .allowsHitTesting(false)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 8)
                    }
                    TextEditor(text: $text)
                        .font(.paseo(.callout))
                        .foregroundStyle(Palette.ink)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 120, maxHeight: 240)
                        .focused($focused)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(Palette.chip, in: .rect(cornerRadius: Radius.md))
                HStack(spacing: 10) {
                    if let onDelete {
                        Button {
                            onDelete()
                        } label: {
                            Text("Delete")
                                .font(.paseo(.callout, weight: .medium))
                                .foregroundStyle(Palette.failureInk)
                                .padding(.horizontal, Space.lg)
                                .frame(minHeight: 44)
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                    Button("Cancel", action: onCancel)
                        .font(.paseo(.callout))
                        .foregroundStyle(Palette.secondaryInk)
                        .frame(minHeight: 44)
                    Button {
                        guard canSave else { return }
                        onSave(text)
                    } label: {
                        Text(isEditing ? "Save" : "Comment")
                            .font(.paseo(.callout, weight: .semibold))
                            .foregroundStyle(Palette.background)
                            .padding(.horizontal, 22)
                            .frame(minHeight: 44)
                            .background(Palette.ink.opacity(canSave ? 1 : 0.35), in: .capsule)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSave)
                    .accessibilityLabel("Save review comment")
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Space.lg)
            .padding(.top, Space.xs)
        }
        .background(Palette.background)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task { focused = true }
    }
}
#endif
