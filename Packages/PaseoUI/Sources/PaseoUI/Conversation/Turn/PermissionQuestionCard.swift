#if canImport(UIKit)
import Foundation
import PaseoStore
import SwiftUI
import UIKit

/// The Claude-Code question card: a gray heading band carrying the question (`QUESTION`
/// eyebrow, 14 pt medium text), options as one divided list of borderless rows aligned to
/// the control grid, a boxed free-text field when offered, and the dismiss/submit row.
/// The typed answers live here, so a keystroke re-renders this card and not the whole request.
struct PermissionQuestionCard: View {
    let form: QuestionForm
    let request: AgentPermissionRequest
    /// The chosen button's title while the daemon confirms.
    let pendingTitle: String?
    /// Reports the chosen answer to the parent, which sends it.
    let onAnswer: (String, AgentPermissionResponse) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var questionState = QuestionFormState()

    private var answering: Bool { pendingTitle != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Heading band: eyebrow + the question text, full-bleed, on the table-head wash.
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: 8) {
                    Text("QUESTION")
                        .font(.paseo(.caption2, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(Palette.tertiaryInk)
                    Spacer(minLength: 0)
                    if answering { ProgressView().controlSize(.mini) }
                }
                ForEach(form.questions.enumerated(), id: \.offset) { index, question in
                    Text(form.questions.count > 1 ? "\(index + 1). \(question.question)" : question.question)
                        .font(.paseo(.callout, weight: .medium))
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.adaptive(light: 1, dark: 0.16))
            ClaudeDivider()
            // Options: one list, hairline rules, no per-row capsules.
            VStack(alignment: .leading, spacing: 0) {
                ForEach(form.questions.enumerated(), id: \.offset) { index, question in
                    QuestionSection(index: index, question: question, state: $questionState)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 8)
                    if index < form.questions.count - 1 {
                        ClaudeDivider().padding(.leading, 16)
                    }
                }
            }
            let allAnswered = form.questions.indices.allSatisfy {
                questionState.isAnswered(index: $0, form: form)
            }
            HStack(spacing: 8) {
                if form.dismissable {
                    let dismissTitle = form.dismissLabel ?? "Dismiss"
                    PermissionAnswerButton(
                        title: dismissTitle, variant: .secondary,
                        isPending: pendingTitle == dismissTitle, answering: answering
                    ) {
                        onAnswer(dismissTitle, .denying(message: "Dismissed by user"))
                    }
                }
                PermissionAnswerButton(
                    title: "Submit", variant: .primary,
                    isPending: pendingTitle == "Submit", answering: answering,
                    action: submit)
                .disabled(!allAnswered)
                .opacity(!allAnswered ? 0.45 : 1)
                .animation(Motion.feedback.resolved(reduceMotion: reduceMotion), value: allAnswered)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Palette.panel, in: .rect(cornerRadius: Radius.md))
        .clipShape(.rect(cornerRadius: Radius.md))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.md).strokeBorder(Palette.cardBorder, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
    }

    private func submit() {
        onAnswer("Submit", submitResponse())
    }

    private func submitResponse() -> AgentPermissionResponse {
        var answers: [String: JSONValue] = [:]
        for (index, question) in form.questions.enumerated() {
            answers[question.header] = .string(questionState.answerString(index: index, question: question))
        }
        var payload = request.input ?? .object([:])
        if case .object(var base) = payload {
            base["answers"] = .object(answers)
            payload = .object(base)
        }
        return .allow(selectedActionId: nil, updatedInput: payload, updatedPermissions: nil)
    }
}
#endif
