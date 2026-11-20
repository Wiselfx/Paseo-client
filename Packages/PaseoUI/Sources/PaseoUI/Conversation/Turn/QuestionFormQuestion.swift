#if canImport(UIKit)
import Foundation
import PaseoStore
import SwiftUI
import UIKit

struct QuestionFormQuestion: Equatable {
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
#endif
