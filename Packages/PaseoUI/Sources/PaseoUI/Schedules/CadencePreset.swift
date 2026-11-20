#if canImport(UIKit)
import PaseoStore
import SwiftUI

// MARK: - Editor page

struct CadencePreset: Hashable {
    let label: String
    let expression: String

    static let all: [CadencePreset] = [
        .init(label: "Every day at 9:00", expression: "0 9 * * *"),
        .init(label: "Weekdays at 9:00", expression: "0 9 * * 1-5"),
        .init(label: "Mondays at 9:00", expression: "0 9 * * 1"),
        .init(label: "1st of the month at 9:00", expression: "0 9 1 * *"),
        .init(label: "Every 6 hours", expression: "0 */6 * * *"),
        .init(label: "Every hour", expression: "0 * * * *"),
    ]
}
#endif
