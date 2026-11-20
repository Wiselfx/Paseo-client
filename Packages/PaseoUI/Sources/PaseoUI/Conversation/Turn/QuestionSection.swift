#if canImport(UIKit)
import Foundation
import PaseoStore
import SwiftUI
import UIKit

/// One question block: header caption, the prompt, options, and the free-text field when needed.
struct QuestionSection: View {
    let index: Int
    let question: QuestionFormQuestion
    @Binding var state: QuestionFormState

    private var segments: Bool { question.multiSelect }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(question.header.uppercased())
                .font(.paseo(.caption2, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(Palette.tertiaryInk)
                .padding(.horizontal, 8)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(question.options.enumerated()), id: \.offset) { optionIndex, option in
                    optionRow(option, index: optionIndex)
                    if optionIndex < question.options.count - 1 {
                        ClaudeDivider().padding(.leading, 42)
                    }
                }
            }
            if question.options.isEmpty || question.allowOther {
                TextField(
                    question.placeholder ?? (question.options.isEmpty ? "Type your answer" : "Other"),
                    text: $state[text: index],
                    axis: .vertical
                )
                .font(.paseo(.callout))
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Palette.chip, in: .rect(cornerRadius: Radius.sm))
                .padding(.top, 4)
                .padding(.horizontal, 8)
                .accessibilityLabel("Other answer")
                // A single-select "Other" clears the option selection, matching Claude Code.
                .onChange(of: state.texts[index] ?? "") { _, text in
                    if !question.multiSelect, !text.isEmpty {
                        state.selections[index] = []
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private func optionRow(_ option: QuestionFormOption, index optionIndex: Int) -> some View {
        let selected = (state.selections[index] ?? []).contains(optionIndex)
        Button {
            Haptics.selection()
            if question.multiSelect {
                var current = state.selections[index] ?? []
                if selected { current.remove(optionIndex) } else { current.insert(optionIndex) }
                state.selections[index] = current
            } else {
                if state.selections[index] == [optionIndex] {
                    state.selections[index] = []
                } else {
                    state.selections[index] = [optionIndex]
                    state.texts[index] = ""
                }
            }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    if segments {
                        RoundedRectangle(cornerRadius: Radius.xs)
                            .stroke(selected ? Palette.ink : Palette.tertiaryInk, lineWidth: 1.5)
                            .frame(width: 16, height: 16)
                        if selected {
                            Image(systemName: "checkmark")
                                .font(.glyph(.small, weight: .bold))
                                .foregroundStyle(Palette.ink)
                        }
                    } else {
                        Circle()
                            .stroke(selected ? Palette.ink : Palette.tertiaryInk, lineWidth: 1.5)
                            .frame(width: 16, height: 16)
                        if selected {
                            Circle().fill(Palette.ink).frame(width: 8, height: 8)
                        }
                    }
                }
                .frame(width: 20, height: 20)
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.label)
                        .font(.paseo(.callout, weight: .medium))
                        .foregroundStyle(Palette.ink)
                    if let description = option.description, !description.isEmpty {
                        Text(description)
                            .font(.paseo(.footnote))
                            .foregroundStyle(Palette.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 8)
            .background(selected ? Palette.adaptive(light: 0.965, dark: 0.10) : .clear)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
#endif
