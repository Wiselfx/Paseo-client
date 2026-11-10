#if canImport(UIKit)
import Foundation
import PaseoStore
import SwiftUI
import UIKit

/// One pending permission request, inline in the transcript. Answers through the store; the card
/// disappears when the daemon reports the resolution, not optimistically. This view also reports
/// what it answered, so `ClaudeChatView` can keep a quiet line in place of the card afterwards
/// (the store drops resolved requests without remembering the answer).
struct ClaudePermissionCard: View {
    let request: AgentPermissionRequest
    let store: ConversationStore
    /// Fired when the user taps an answer; the focus record is that this client answered.
    let onAnswered: (AnsweredPermission) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var answering = false
    @State private var questionState = QuestionFormState()
    private let typography = ClaudeTypography()

    private var isPlan: Bool { request.kind == .plan }
    /// Pi `ask_user`-style payloads parse; anything else degrades to the generic tool card.
    private var questionForm: QuestionForm? { QuestionForm(input: request.input) }

    private var title: String {
        if let title = request.title, !title.isEmpty { return title }
        if request.kind == .question { return "How would you like to proceed?" }
        return isPlan ? "Proposed plan" : request.name
    }

    var body: some View {
        Group {
            if let form = questionForm {
                questionCard(form)
            } else if isPlan {
                planCard
                    .padding(12)
                    .background(ClaudePalette.panel, in: .rect(cornerRadius: ClaudeRadius.card))
                    .overlay {
                        RoundedRectangle(cornerRadius: ClaudeRadius.card).strokeBorder(ClaudePalette.cardBorder, lineWidth: 1)
                    }
            } else {
                toolCard
                    .padding(12)
                    .background(ClaudePalette.panel, in: .rect(cornerRadius: ClaudeRadius.card))
                    .overlay {
                        RoundedRectangle(cornerRadius: ClaudeRadius.card).strokeBorder(ClaudePalette.cardBorder, lineWidth: 1)
                    }
            }
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    // MARK: Tool cards (generic permission requests)

    @ViewBuilder private var toolCard: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(ClaudePalette.secondaryInk)
            Text(title)
                .font(typography.sans(15, weight: .semibold))
                .foregroundStyle(ClaudePalette.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if answering { ProgressView().controlSize(.mini) }
        }
        if let description = request.description, !description.isEmpty {
            Text(description)
                .font(typography.sans(14))
                .foregroundStyle(ClaudePalette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        if let input = request.input {
            ClaudeCodeBlock(output: ClaudeToolCallDetail.describe(input), maxHeight: 180)
        }
        HStack(spacing: 8) {
            ForEach(actionButtons, id: \.title) { spec in
                answerButton(title: spec.title, variant: spec.variant, response: spec.response)
            }
        }
    }

    private struct ActionSpec: Hashable {
        var title: String
        var variant: AgentPermissionAction.Variant
        var response: AgentPermissionResponse
    }

    private var actionButtons: [ActionSpec] {
        if let actions = request.actions, !actions.isEmpty {
            return actions.map { action in
                ActionSpec(
                    title: action.label,
                    variant: action.variant ?? (action.behavior == .deny ? .secondary : .primary),
                    response: response(for: action))
            }
        }
        return [
            ActionSpec(title: "Deny", variant: .secondary, response: .denying()),
            ActionSpec(title: "Accept", variant: .primary, response: .allowing()),
        ]
    }

    private var symbol: String {
        switch request.kind {
        case .plan: "list.bullet.clipboard"
        case .question: "questionmark.bubble"
        case .mode: "slider.horizontal.3"
        case .tool: "hand.raised"
        case .other, .unknown: "lock.shield"
        }
    }

    private func response(for action: AgentPermissionAction) -> AgentPermissionResponse {
        switch action.behavior {
        case .allow: .allowing(selectedActionId: action.id)
        case .deny: .denying(selectedActionId: action.id)
        case .unknown: .denying(selectedActionId: action.id)
        }
    }

    // MARK: Plan card

    @ViewBuilder private var planCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "list.bullet.clipboard")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(ClaudePalette.secondaryInk)
                Text("Proposed plan")
                    .font(typography.sans(15, weight: .semibold))
                    .foregroundStyle(ClaudePalette.ink)
                Spacer(minLength: 0)
                if answering { ProgressView().controlSize(.mini) }
            }
            Text(planText)
                .font(typography.serif(14))
                .foregroundStyle(ClaudePalette.primaryInk)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let description = request.description, !description.isEmpty {
                Text(description)
                    .font(typography.sans(13))
                    .foregroundStyle(ClaudePalette.secondaryInk)
            }
            HStack(spacing: 8) {
                answerButton(title: "Reject", variant: .secondary, response: .denying())
                answerButton(title: "Approve", variant: .primary, response: .allowing())
            }
        }
    }

    private var planText: String {
        if let metadata = request.metadata, let text = metadata["planText"]?.stringValue,
           !text.isEmpty {
            return text
        }
        if let input = request.input, let text = input["plan"]?.stringValue,
           !text.isEmpty {
            return text
        }
        return request.description ?? "The agent proposed a plan."
    }

    // MARK: Question form

    /// The Claude-Code question card: a gray heading band carrying the question (`QUESTION`
    /// eyebrow, 14 pt medium text), options as one divided list of borderless rows aligned to
    /// the control grid, a boxed free-text field when offered, and the dismiss/submit row.
    @ViewBuilder private func questionCard(_ form: QuestionForm) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Heading band: eyebrow + the question text, full-bleed, on the table-head wash.
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: 8) {
                    Text("QUESTION")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(ClaudePalette.tertiaryInk)
                    Spacer(minLength: 0)
                    if answering { ProgressView().controlSize(.mini) }
                }
                ForEach(Array(form.questions.enumerated()), id: \.offset) { index, question in
                    Text(form.questions.count > 1 ? "\(index + 1). \(question.question)" : question.question)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(ClaudePalette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ClaudePalette.adaptive(light: 1, dark: 0.16))
            ClaudeDivider()
            // Options: one list, hairline rules, no per-row capsules.
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(form.questions.enumerated()), id: \.offset) { index, question in
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
                    answerButton(
                        title: form.dismissLabel ?? "Dismiss", variant: .secondary,
                        response: .denying(message: "Dismissed by user"))
                }
                answerButton(
                    title: "Submit", variant: .primary,
                    response: submitResponse(form))
                .disabled(!allAnswered)
                .opacity(!allAnswered ? 0.45 : 1)
                .animation(reduceMotion ? nil : .easeOut(duration: ClaudeMotion.feedback), value: allAnswered)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(ClaudePalette.panel, in: .rect(cornerRadius: 14))
        .clipShape(.rect(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14).strokeBorder(ClaudePalette.cardBorder, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
    }

    private func submitResponse(_ form: QuestionForm) -> AgentPermissionResponse {
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

    // MARK: Buttons

    private func answerButton(
        title: String, variant: AgentPermissionAction.Variant, response: AgentPermissionResponse
    ) -> some View {
        let filled = variant == .primary
        let danger = variant == .danger
        return Button {
            guard !answering else { return }
            answering = true
            Haptics.selection()
            let requestId = request.id
            let line = ResolutionLine.text(for: response, request: request)
            Task { await store.respond(to: requestId, with: response) }
            onAnswered(AnsweredPermission(id: requestId, line: line))
        } label: {
            Text(title)
                .font(typography.sans(14, weight: .medium))
                .lineLimit(1)
                .padding(.horizontal, 14)
                .frame(height: 36)
                .foregroundStyle(
                    filled
                        ? ClaudePalette.background
                        : danger ? ClaudePalette.failureInk : ClaudePalette.ink)
                .background(
                    filled ? ClaudePalette.ink : ClaudePalette.adaptive(light: 0.94, dark: 0.24),
                    in: .capsule)
        }
        .buttonStyle(.plain)
        .disabled(answering)
        .opacity(answering ? 0.6 : 1)
        .animation(reduceMotion ? nil : .easeOut(duration: ClaudeMotion.feedback), value: answering)
        .accessibilityLabel(title)
    }
}

// MARK: - Question payload

/// The `ask_user` payload on a `.question` request: `{ questions: [{ question, header,
/// options: [{ label, description?, preview? }], multiSelect, allowOther, allowEmpty,
/// placeholder?, dismissLabel? }] }`. Anything else parses as nil and the card degrades to the
/// generic buttons.
private struct QuestionForm: Equatable {
    var questions: [QuestionFormQuestion]

    static func == (lhs: QuestionForm, rhs: QuestionForm) -> Bool {
        lhs.questions.map(\.question) == rhs.questions.map(\.question)
    }

    init?(input: JSONValue?) {
        guard let input, case .object(let object) = input,
            case .array(let items)? = object["questions"], !items.isEmpty
        else { return nil }
        var parsed: [QuestionFormQuestion] = []
        for item in items {
            guard case .object(let question) = item,
                let prompt = question["question"]?.stringValue,
                let header = question["header"]?.stringValue,
                case .array(let options) = question["options"]
            else { return nil }
            var parsedOptions: [QuestionFormOption] = []
            for option in options {
                guard case .object(let raw) = option, let label = raw["label"]?.stringValue else {
                    return nil
                }
                parsedOptions.append(
                    QuestionFormOption(
                        label: label,
                        description: raw["description"]?.stringValue,
                        preview: raw["preview"]?.stringValue))
            }
            parsed.append(
                QuestionFormQuestion(
                    question: prompt, header: header, options: parsedOptions,
                    multiSelect: question["multiSelect"] == .bool(true),
                    allowOther: question["allowOther"] == .bool(true) || question["isOther"] == .bool(true),
                    allowEmpty: question["allowEmpty"] == .bool(true),
                    placeholder: question["placeholder"]?.stringValue,
                    dismissLabel: question["dismissLabel"]?.stringValue))
        }
        questions = parsed
    }

    /// Show a dismiss button when every question is dismissable (all `allowEmpty`) or any
    /// question names one (`dismissLabel`).
    var dismissable: Bool {
        let named = questions.contains { $0.dismissLabel != nil }
        let allEmpty = questions.allSatisfy { $0.allowEmpty && $0.options.isEmpty }
        return named || allEmpty
    }

    var dismissLabel: String? {
        questions.compactMap(\.dismissLabel).first
    }
}

private struct QuestionFormQuestion: Equatable {
    var question: String
    var header: String
    var options: [QuestionFormOption]
    var multiSelect: Bool
    var allowOther: Bool
    var allowEmpty: Bool
    var placeholder: String?
    var dismissLabel: String?

    static func == (lhs: QuestionFormQuestion, rhs: QuestionFormQuestion) -> Bool {
        lhs.question == rhs.question
    }
}

private struct QuestionFormOption: Equatable {
    var label: String
    var description: String?
    var preview: String?
}

/// Live answer state for one question form; owned by the card (it unmounts with the card).
private struct QuestionFormState {
    /// Selected option indices per question, by position.
    var selections: [Int: Set<Int>] = [:]
    /// Free-text ("Other") text per question, by position.
    var texts: [Int: String] = [:]

    func isAnswered(index: Int, form: QuestionForm) -> Bool {
        let question = form.questions[index]
        if let selected = selections[index], !selected.isEmpty { return true }
        if !question.options.isEmpty && !question.allowOther { return question.allowEmpty }
        if let text = texts[index]?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            return true
        }
        return question.allowEmpty
    }

    /// The answer string the daemon expects: labels joined by ", " — one `header → text` per question.
    func answerString(index: Int, question: QuestionFormQuestion) -> String {
        let labels = (selections[index] ?? []).sorted().map { question.options[$0].label }
        let other = texts[index]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !other.isEmpty {
            if question.multiSelect { return (labels + [other]).joined(separator: ", ") }
            return other
        }
        return labels.joined(separator: ", ")
    }
}

/// One question block: header caption, the prompt, options, and the free-text field when needed.
private struct QuestionSection: View {
    let index: Int
    let question: QuestionFormQuestion
    @Binding var state: QuestionFormState

    private var segments: Bool { question.multiSelect }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(question.header.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(ClaudePalette.tertiaryInk)
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
                    text: Binding(
                        get: { state.texts[index] ?? "" },
                        set: { state.texts[index] = $0 }),
                    axis: .vertical
                )
                .font(.system(size: 14))
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(ClaudePalette.chip, in: .rect(cornerRadius: ClaudeRadius.control))
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
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(selected ? ClaudePalette.ink : ClaudePalette.tertiaryInk, lineWidth: 1.5)
                            .frame(width: 16, height: 16)
                        if selected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(ClaudePalette.ink)
                        }
                    } else {
                        Circle()
                            .stroke(selected ? ClaudePalette.ink : ClaudePalette.tertiaryInk, lineWidth: 1.5)
                            .frame(width: 16, height: 16)
                        if selected {
                            Circle().fill(ClaudePalette.ink).frame(width: 8, height: 8)
                        }
                    }
                }
                .frame(width: 20, height: 20)
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.label)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(ClaudePalette.primaryInk)
                    if let description = option.description, !description.isEmpty {
                        Text(description)
                            .font(.system(size: 13))
                            .foregroundStyle(ClaudePalette.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 8)
            .background(selected ? ClaudePalette.adaptive(light: 0.965, dark: 0.10) : .clear)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The one quiet line left behind when a request resolves; kept in the transcript by the client,
/// because the store drops resolved requests from `pendingPermissions` without remembering the answer.
struct AnsweredPermission: Identifiable, Hashable {
    var id: String
    var line: String
}

enum ResolutionLine {
    static func text(for response: AgentPermissionResponse, request: AgentPermissionRequest) -> String {
        if request.kind == .plan {
            if case .allow = response { return "Approved plan" }
            return "Rejected plan"
        }
        switch response {
        case .allow: return "Allowed: \(request.name)"
        case .deny(_, _, let interrupt): return interrupt == true ? "Canceled" : "Denied"
        case .unknown(let behavior, _): return behavior == "dismiss" ? "Canceled" : "Denied"
        }
    }
}
#endif
