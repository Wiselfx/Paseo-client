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
    /// The chosen button's title while the daemon confirms: the card shows its
    /// pending state there, never a resolution line (D8 — the line appears only
    /// after the request leaves `pendingPermissions`).
    @State private var pendingTitle: String?

    private var answering: Bool { pendingTitle != nil }
    /// The optimistic quiet line is reported at most once per request: a retry after the
    /// answer timeout must not append a second line with the same id (the parent renders
    /// them in a `ForEach`, where duplicate ids are undefined behaviour).
    @State private var didReportAnswer = false
    @State private var questionState = QuestionFormState()

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
                    .padding(Space.md)
                    .background(Palette.panel, in: .rect(cornerRadius: Radius.lg))
                    .overlay {
                        RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(Palette.cardBorder, lineWidth: 1)
                    }
            } else {
                toolCard
                    .padding(Space.md)
                    .background(Palette.panel, in: .rect(cornerRadius: Radius.lg))
                    .overlay {
                        RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(Palette.cardBorder, lineWidth: 1)
                    }
            }
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
        .task(id: answering) {
            guard answering else { return }
            // The answer is fire-and-forget by protocol: `agent_permission_response` carries
            // no correlated reply, so a lost frame never surfaces as an error and no
            // `agent_permission_resolved` event ever arrives. Without this timeout the card
            // would sit on its spinner with dead buttons forever. When the card is still
            // mounted after the timeout the answer never landed, so the user can answer again.
            // (HB: the timeout only re-arms the buttons; the recorded answer stays put
            // and still renders if the daemon confirms it late.)
            try? await Task.sleep(for: Self.answerTimeout)
            guard !Task.isCancelled else { return }
            pendingTitle = nil
        }
    }

    // MARK: Tool cards (generic permission requests)

    @ViewBuilder private var toolCard: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol)
                .font(.glyph(.small, weight: .medium))
                .foregroundStyle(Palette.secondaryInk)
            Text(title)
                .font(.paseo(.callout, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if answering { ProgressView().controlSize(.mini) }
        }
        if let description = request.description, !description.isEmpty {
            Text(description)
                .font(.paseo(.callout))
                .foregroundStyle(Palette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        requestPreview
        HStack(spacing: 8) {
            ForEach(actionButtons, id: \.title) { spec in
                answerButton(title: spec.title, variant: spec.variant, response: spec.response)
            }
        }
    }

    /// What is being requested, from the daemon's normalized tool call when it
    /// could build one: the diff for an edit, the command for a shell, the path
    /// for a read/write or fetch. Falls back to the generic description plus the
    /// raw input dump. Existing views only — no new renderers.
    @ViewBuilder private var requestPreview: some View {
        if let detail = request.detail {
            switch detail {
            case .edit(let path, _, _, let diff):
                if let diff, !diff.isEmpty {
                    ClaudeDiffView(path: path, unifiedDiff: diff, old: nil, new: nil)
                } else {
                    previewPathRow(path)
                }
            case .shell(let command, _, _, _):
                ClaudeCodeBlock(command: command, output: nil, maxHeight: 180)
            case .read(let path, _), .write(let path, _):
                previewPathRow(path)
            case .fetch(let url, _, _):
                previewPathRow(url)
            default:
                genericPreview
            }
        } else {
            genericPreview
        }
    }

    private func previewPathRow(_ path: String) -> some View {
        Text(path)
            .font(.paseo(.codeSmall))
            .foregroundStyle(Palette.ink)
            .lineLimit(2)
            .truncationMode(.middle)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The description already renders above; this is only the raw input dump.
    @ViewBuilder private var genericPreview: some View {
        if let input = request.input {
            ClaudeCodeBlock(output: ClaudeToolCallDetail.describe(input), maxHeight: 180)
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
                    .font(.glyph(.small, weight: .medium))
                    .foregroundStyle(Palette.secondaryInk)
                Text("Proposed plan")
                    .font(.paseo(.callout, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                Spacer(minLength: 0)
                if answering { ProgressView().controlSize(.mini) }
            }
            Text(planText)
                .font(.paseo(.processTitle))
                .foregroundStyle(Palette.ink)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let description = request.description, !description.isEmpty {
                Text(description)
                    .font(.paseo(.footnote))
                    .foregroundStyle(Palette.secondaryInk)
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
                        .font(.paseo(.caption2, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(Palette.tertiaryInk)
                    Spacer(minLength: 0)
                    if answering { ProgressView().controlSize(.mini) }
                }
                ForEach(Array(form.questions.enumerated()), id: \.offset) { index, question in
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

    /// How long the card waits for the daemon's `agent_permission_resolved` event before it
    /// lets the user answer again. Normal confirmation is near-instant; a lost answer frame
    /// never resolves, so this is generous rather than tight.
    private static let answerTimeout: Duration = .seconds(10)

    private func answerButton(
        title: String, variant: AgentPermissionAction.Variant, response: AgentPermissionResponse
    ) -> some View {
        let filled = variant == .primary
        let danger = variant == .danger
        // The chosen button carries the pending state; the rest dim and disable.
        // Nothing reports a resolution here (D8): the parent renders the line only
        // after the daemon confirms (the request leaves `pendingPermissions`).
        let isPending = pendingTitle == title
        return Button {
            guard !answering else { return }
            pendingTitle = title
            Haptics.selection()
            let requestId = request.id
            let line = ResolutionLine.text(for: response, request: request)
            Task { await store.respond(to: requestId, with: response) }
            if !didReportAnswer {
                didReportAnswer = true
                onAnswered(AnsweredPermission(id: requestId, line: line))
            }
        } label: {
            HStack(spacing: 6) {
                Text(title)
                    .font(.paseo(.callout, weight: .medium))
                    .lineLimit(1)
                if isPending {
                    ProgressView()
                        .controlSize(.mini)
                        .accessibilityLabel("Waiting for confirmation")
                }
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 36)
            .foregroundStyle(
                filled
                    ? Palette.background
                    : danger ? Palette.failureInk : Palette.ink)
            .background(
                filled ? Palette.ink : Palette.adaptive(light: 0.94, dark: 0.24),
                in: .capsule)
        }
        .buttonStyle(.plain)
        .disabled(answering)
        .opacity(answering && !isPending ? 0.6 : 1)
        .animation(Motion.feedback.resolved(reduceMotion: reduceMotion), value: answering)
        .accessibilityLabel(isPending ? "\(title), waiting for confirmation" : title)
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
                    text: Binding(
                        get: { state.texts[index] ?? "" },
                        set: { state.texts[index] = $0 }),
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
