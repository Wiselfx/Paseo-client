#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// Every thought of a work run as one section: "Thought for 12s" folded, the whole reasoning as
/// one continuous text when opened. Folded by default (unless Settings → Always expand
/// reasoning), and folded it builds nothing from the text: while the model thinks it shows only
/// a live "Thinking", so streaming reasoning costs one line and never moves the transcript.
struct WorkThoughtSection: View {
    /// The run's `.reasoning` rows, in order.
    let rows: [TimelineRow]
    /// How long the run thought, once known.
    let seconds: TimeInterval?
    /// The model is thinking right now: the run's newest row is a thought.
    let isLive: Bool
    let highlighted: Bool
    var findTarget: Int?

    @State private var userOpen: Bool?
    @State private var liveSince = Date.now
    /// Counts the reader's taps so the haptic plays for them and not for a find opening the section.
    @State private var toggleCount = 0
    @AppStorage("paseo.reasoning.alwaysExpand") private var alwaysExpand = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isOpen: Bool { userOpen ?? alwaysExpand }

    private var title: String {
        if let seconds, seconds >= 1 { return "Thought for \(DurationText.short(seconds))" }
        return "Thought"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WorkDigestHeader(
                icon: WorkIcon(kind: .thought), isOpen: isOpen,
                accessibilityLabel: isLive ? "Thinking" : title, action: toggle
            ) {
                if isLive {
                    ClaudeSweepLabel(startedAt: liveSince, rest: Palette.tertiaryInk) { ink in
                        WorkDigestTitle(text: "Thinking", ink: ink)
                    }
                } else {
                    WorkDigestTitle(text: title, ink: Palette.tertiaryInk)
                }
            }
            // The folded line stands for every thought, so find and the outline land on it.
            .rowAnchors(rows.map(\.seqEnd))
            if isOpen {
                WorkThoughtText(text: Self.joined(rows))
                    .padding(.leading, WorkTimelineMetrics.gutter)
                    .padding(.bottom, 10)
                    .transition(.opacity)
            }
        }
        .background { FindWash(highlighted: highlighted, bleed: 4) }
        .paseoFeedback(.selection, trigger: toggleCount)
        .onChange(of: findTarget, initial: true) { _, target in reveal(target) }
    }

    private func toggle() {
        toggleCount += 1
        withAnimation(Motion.disclosure.resolved(reduceMotion: reduceMotion)) {
            userOpen = !isOpen
        }
    }

    /// A find match in the reasoning opens it.
    private func reveal(_ target: Int?) {
        guard let target, !isOpen,
            rows.contains(where: { $0.seqStart <= target && target <= $0.seqEnd })
        else { return }
        userOpen = true
    }

    /// The thoughts as one text, a paragraph break between them. Read only while open.
    static func joined(_ rows: [TimelineRow]) -> String {
        rows.compactMap { row -> String? in
            guard case .reasoning(let reasoning) = row.item else { return nil }
            return reasoning.text
        }
        .joined(separator: "\n\n")
    }
}
#endif
