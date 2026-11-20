#if canImport(UIKit)
import Foundation
import PaseoStore
import SwiftUI
import UIKit

/// Live answer state for one question form; owned by the card (it unmounts with the card).
struct QuestionFormState {
    /// Selected option indices per question, by position.
    var selections: [Int: Set<Int>] = [:]
    /// Free-text ("Other") text per question, by position.
    var texts: [Int: String] = [:]

    /// One question's free text, "" when untouched: what the answer field binds to.
    subscript(text index: Int) -> String {
        get { texts[index] ?? "" }
        set { texts[index] = newValue }
    }

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
#endif
