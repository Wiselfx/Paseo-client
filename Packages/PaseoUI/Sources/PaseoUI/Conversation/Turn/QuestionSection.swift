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

    /// Counts option taps so the selection haptic fires for a tap, not for the "Other" field
    /// clearing the selection as the user types.
    @State private var selectionTicks = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(question.header.uppercased())
                .font(.paseo(.caption2, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(Palette.tertiaryInk)
                .padding(.horizontal, 8)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(question.options.enumerated(), id: \.offset) { optionIndex, option in
                    QuestionOptionRow(
                        option: option,
                        selected: (state.selections[index] ?? []).contains(optionIndex),
                        multiSelect: question.multiSelect
                    ) {
                        toggle(optionIndex)
                    }
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
                .accessibilityLabel(question.options.isEmpty ? "Answer" : "Other answer")
                // A single-select "Other" clears the option selection, matching Claude Code.
                .onChange(of: state.texts[index] ?? "") { _, text in
                    if !question.multiSelect, !text.isEmpty {
                        state.selections[index] = []
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .paseoFeedback(.selection, trigger: selectionTicks)
    }

    /// Applies a tap on option `optionIndex`: toggles it in multi-select, otherwise selects it
    /// (or clears it when it already is the selection) and empties the "Other" text.
    private func toggle(_ optionIndex: Int) {
        selectionTicks += 1
        if question.multiSelect {
            var current = state.selections[index] ?? []
            if current.contains(optionIndex) { current.remove(optionIndex) } else { current.insert(optionIndex) }
            state.selections[index] = current
        } else {
            if state.selections[index] == [optionIndex] {
                state.selections[index] = []
            } else {
                state.selections[index] = [optionIndex]
                state.texts[index] = ""
            }
        }
    }
}
#endif
