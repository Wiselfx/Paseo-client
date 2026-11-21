#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// One tool call: the line, and its output when opened. A live shell call opens on its own so its
/// output can be watched; it folds again when it lands unless the reader opened it.
struct WorkToolStep: View {
    let call: ToolCall
    let rail: WorkRailPosition
    let isLive: Bool
    let highlighted: Bool
    let findHit: Bool

    @State private var userExpanded: Bool?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var opensLive: Bool {
        guard isLive, call.status == .running else { return false }
        if case .shell = call.detail { return true }
        return false
    }

    private var isExpanded: Bool { userExpanded ?? (findHit || opensLive) }

    var body: some View {
        let wording = WorkToolWording(call)
        let stat = WorkDiffStat.of(call)
        WorkStepFrame(
            icon: WorkIcon(
                kind: wording.icon, running: call.status == .running,
                failed: call.status == .failed),
            rail: rail, highlighted: highlighted
        ) {
            VStack(alignment: .leading, spacing: 0) {
                WorkDisclosureButton(
                    isExpanded: isExpanded,
                    accessibilityLabel: [wording.verb, wording.target].compactMap { $0 }
                        .joined(separator: " "),
                    accessibilityDetails: spokenDetails(stat),
                    action: toggleExpanded
                ) {
                    HStack(spacing: 8) {
                        WorkToolLine(verb: wording.verb, target: wording.target)
                        Spacer(minLength: 4)
                        WorkOutcome(call: call)
                        if let stat {
                            DiffStat(added: stat.added, removed: stat.removed)
                        }
                        ClaudeTurnChevron(expanded: isExpanded)
                    }
                    .frame(minHeight: WorkTimelineMetrics.headerHeight)
                    .contentShape(.rect)
                }
                if isExpanded {
                    ClaudeToolCallDetail(call: call)
                        .padding(.top, 2)
                        .padding(.bottom, 10)
                        .transition(.opacity.combined(with: .offset(y: -2)))
                }
            }
        }
        .paseoFeedback(.selection, trigger: userExpanded)
    }

    /// What the visible line shows besides the verb and target, which the spoken label replaces.
    private func spokenDetails(_ stat: (added: Int, removed: Int)?) -> [String] {
        var details: [String] = []
        if let outcome = WorkOutcome(call: call).accessibilityText { details.append(outcome) }
        if let stat, let text = WorkDiffStat.spokenText(added: stat.added, removed: stat.removed) {
            details.append(text)
        }
        return details
    }

    private func toggleExpanded() {
        withAnimation(Motion.disclosure.resolved(reduceMotion: reduceMotion)) {
            userExpanded = !isExpanded
        }
    }
}
#endif
