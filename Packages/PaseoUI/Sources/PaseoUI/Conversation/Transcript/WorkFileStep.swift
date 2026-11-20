#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// A run of calls on one file: "Edited ChatTurns.swift ×3 +12 −3". The file name opens the file;
/// the rest of the line opens the calls.
struct WorkFileStep: View {
    let call: ClaudeMergedFileCall
    let rail: WorkRailPosition
    let highlighted: Bool
    let findHit: Bool
    let onOpenFile: (String) -> Void

    @State private var userExpanded: Bool?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isExpanded: Bool { userExpanded ?? findHit }
    private var last: ToolCall? { call.calls.last }
    private var running: Bool { last?.status == .running }
    private var failed: Bool { last?.status == .failed }

    private var verb: String {
        switch call.kind {
        case .read: running ? "Reading" : "Read"
        case .edit: running ? "Editing" : "Edited"
        case .write: running ? "Writing" : "Wrote"
        }
    }

    private var icon: WorkIcon.Kind {
        switch call.kind {
        case .read: .read
        case .edit: .edit
        case .write: .write
        }
    }

    var body: some View {
        WorkStepFrame(
            icon: WorkIcon(kind: icon, running: running, failed: failed),
            rail: rail, highlighted: highlighted
        ) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 7) {
                    toggle {
                        Text(verb)
                            .font(.paseo(.processTitle, weight: .medium))
                            .foregroundStyle(Palette.secondaryInk)
                            .lineLimit(1)
                            .fixedSize()
                            .frame(minHeight: WorkTimelineMetrics.headerHeight)
                            .contentShape(.rect)
                    }
                    Button {
                        onOpenFile(call.path)
                    } label: {
                        HStack(spacing: 5) {
                            Text(call.fileName)
                                .font(.paseo(.codeSmall))
                                .foregroundStyle(Palette.tertiaryInk)
                                .underline(true, pattern: .dot, color: Palette.captionInk)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            if call.count > 1 {
                                Text("×\(PaseoFormat.integer(call.count))")
                                    .font(.paseo(.codeCaption))
                                    .foregroundStyle(Palette.captionInk)
                            }
                        }
                        .frame(minHeight: WorkTimelineMetrics.headerHeight)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open \(call.fileName)")
                    toggle {
                        HStack(spacing: 8) {
                            Spacer(minLength: 4)
                            if let last, last.status == .failed { WorkOutcome(call: last) }
                            if let stat = call.diffStat {
                                DiffStat(added: stat.added, removed: stat.removed)
                            }
                            ClaudeTurnChevron(expanded: isExpanded)
                        }
                        .frame(minHeight: WorkTimelineMetrics.headerHeight)
                        .contentShape(.rect)
                    }
                }
                if isExpanded {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(call.calls, id: \.callId) { toolCall in
                            ClaudeToolCallDetail(call: toolCall)
                        }
                    }
                    .padding(.top, 2)
                    .padding(.bottom, 10)
                    .transition(.opacity.combined(with: .offset(y: -2)))
                }
            }
        }
    }

    private func toggle<Label: View>(@ViewBuilder label: () -> Label) -> some View {
        Button {
            Haptics.selection()
            withAnimation(Motion.disclosure.resolved(reduceMotion: reduceMotion)) {
                userExpanded = !isExpanded
            }
        } label: {
            label()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(verb) \(call.fileName)")
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
    }
}
#endif
