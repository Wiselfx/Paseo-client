#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// The PR pane's state row: the state pill, "#number · title" and the review decision.
struct PRStateRow: View {
    let status: CheckoutPrStatus

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            StatePill(stateLabel, tone: stateTone)
            VStack(alignment: .leading, spacing: Space.xs) {
                Text("#\(String(status.number ?? 0)) · \(status.title)")
                    .font(.paseo(.callout, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if let reviewDecisionLine {
                    Text(reviewDecisionLine)
                        .font(.paseo(.caption))
                        .foregroundStyle(Palette.secondaryInk)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, Space.lg)
        .padding(.bottom, 10)
    }

    private var stateLabel: String {
        if status.isDraft == true { return "Draft" }
        switch status.state.uppercased() {
        case "OPEN": return "Open"
        case "MERGED": return "Merged"
        case "CLOSED": return "Closed"
        default: return status.state.capitalized
        }
    }

    private var stateTone: StatePill.Tone {
        if status.isMerged || status.isDraft == true { return .neutral }
        return status.state.uppercased() == "OPEN" ? .success : .neutral
    }

    private var reviewDecisionLine: String? {
        guard let decision = status.reviewDecision, !decision.isEmpty else { return nil }
        return "Review: \(decision.replacing("_", with: " ").capitalized)"
    }
}
#endif
