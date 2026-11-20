#if canImport(UIKit)
import Foundation
import PaseoStore
import SwiftUI
import UIKit

// MARK: - Question payload

/// The `ask_user` payload on a `.question` request: `{ questions: [{ question, header,
/// options: [{ label, description?, preview? }], multiSelect, allowOther, allowEmpty,
/// placeholder?, dismissLabel? }] }`. Anything else parses as nil and the card degrades to the
/// generic buttons.
struct QuestionForm: Equatable {
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
#endif
