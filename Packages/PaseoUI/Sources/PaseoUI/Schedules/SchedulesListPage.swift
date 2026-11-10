#if canImport(UIKit)
import Combine
import PaseoStore
import SwiftUI

// MARK: - List page

struct SchedulesListPage: View {
    let session: HostSession
    let onClose: () -> Void
    let onOpen: (String) -> Void
    let onNew: () -> Void
    let showToast: (String) -> Void

    @State private var now = Date()
    private let poll = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    private var schedules: SchedulesStore { session.schedules }
    private var knownAgentIds: Set<String> { Set(session.agents.map(\.id)) }

    var body: some View {
        VStack(spacing: 0) {
            header
            if let actionError = schedules.actionError {
                Text(actionError)
                    .font(.paseo(.footnote))
                    .foregroundStyle(Palette.failureInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
            }
            content
        }
        .onReceive(poll) { date in
            now = date
            Task { await schedules.load() }
        }
    }

    private var header: some View {
        ZStack {
            Text("Schedules")
                .font(.paseo(.title, weight: .semibold))
            HStack {
                Button {
                    Haptics.selection()
                    onClose()
                } label: {
                    Image(systemName: "xmark").font(.glyph(.large, weight: .light))
                        .frame(width: 42, height: 42)
                }
                .glassEffect(in: .circle)
                .accessibilityLabel("Close")
                Spacer()
                Button {
                    Haptics.selection()
                    onNew()
                } label: {
                    Image(systemName: "plus").font(.glyph(.large, weight: .light))
                        .frame(width: 42, height: 42)
                }
                .glassEffect(in: .circle)
                .accessibilityLabel("New schedule")
            }
        }
        .frame(height: 56)
        .padding(.horizontal, 16)
        .padding(.top, 6)
    }

    @ViewBuilder private var content: some View {
        if !schedules.isSupported {
            unsupportedState
        } else if case .failed(let message) = schedules.phase, schedules.schedules.isEmpty {
            failedState(message)
        } else if (schedules.phase == .idle || schedules.phase == .loading), schedules.schedules.isEmpty {
            ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if schedules.schedules.isEmpty {
            emptyState
        } else {
            list
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(schedules.schedules.enumerated()), id: \.element.id) { index, summary in
                    if index > 0 {
                        ClaudeDivider().padding(.leading, 20)
                    }
                    row(summary)
                }
            }
            .padding(.top, 4)
            .padding(.bottom, 18)
        }
        .scrollBounceBehavior(.basedOnSize)
        .refreshable { await schedules.load() }
    }

    private func row(_ summary: ScheduleSummary) -> some View {
        let state = summary.state(now: now, knownAgentIds: knownAgentIds)
        return Button {
            Haptics.selection()
            onOpen(summary.id)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title(summary))
                        .font(.paseo(.callout, weight: .medium))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    Text(subtitle(summary))
                        .font(.paseo(.footnote))
                        .foregroundStyle(Palette.secondaryInk)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 4) {
                    ScheduleStatePill(state: state)
                    Text(nextCaption(summary, state: state))
                        .font(.paseo(.caption2))
                        .foregroundStyle(Palette.captionInk)
                }
            }
            .padding(.horizontal, 20)
            .frame(minHeight: 58)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Schedule \(title(summary))")
        .accessibilityValue("\(subtitle(summary)), \(nextCaption(summary, state: state))")
    }

    private func title(_ summary: ScheduleSummary) -> String {
        if let name = summary.name, !name.isEmpty { return name }
        let firstLine = summary.prompt.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true).first
        return firstLine.map(String.init) ?? "Untitled schedule"
    }

    private func subtitle(_ summary: ScheduleSummary) -> String {
        summary.cadence.words
    }

    private func nextCaption(_ summary: ScheduleSummary, state: ScheduleState) -> String {
        switch state {
        case .paused: return "Paused"
        case .expired, .finished: return "No upcoming run"
        default: return scheduleNextRun(summary.nextRunAt)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "clock")
                .font(.glyph(.large, weight: .light))
                .frame(width: 48, height: 48)
                .background(Palette.panel, in: .circle)
            VStack(spacing: 4) {
                Text("No schedules yet")
                    .font(.paseo(.title))
                    .foregroundStyle(Palette.ink)
                Text("Schedules run agents on a cadence.")
                    .font(.paseo(.callout))
                    .foregroundStyle(Palette.secondaryInk)
                    .multilineTextAlignment(.center)
            }
            Button {
                Haptics.selection()
                onNew()
            } label: {
                Label("New schedule", systemImage: "plus")
                    .font(.paseo(.callout, weight: .medium))
                    .foregroundStyle(Palette.background)
                    .padding(.horizontal, 17)
                    .frame(minHeight: 44)
                    .background(Palette.ink, in: .capsule)
            }
            .accessibilityIdentifier("schedules.new")
        }
        .padding(.horizontal, 36)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var unsupportedState: some View {
        VStack(spacing: 8) {
            Image(systemName: "clock")
                .font(.glyph(.xlarge, weight: .light))
                .foregroundStyle(Palette.tertiaryInk)
            Text("Schedules aren't available on this host")
                .font(.paseo(.callout, weight: .medium))
                .foregroundStyle(Palette.ink)
            Text("The daemon did not grant the automation.manage permission.")
                .font(.paseo(.footnote))
                .foregroundStyle(Palette.secondaryInk)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 32)
    }

    private func failedState(_ message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.glyph(.xlarge, weight: .light))
                .foregroundStyle(Palette.tertiaryInk)
            Text(message)
                .font(.paseo(.footnote))
                .foregroundStyle(Palette.secondaryInk)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            Button {
                Haptics.selection()
                Task { await schedules.load() }
            } label: {
                Text("Retry")
                    .font(.paseo(.footnote, weight: .medium))
                    .foregroundStyle(Palette.ink)
                    .padding(.horizontal, 18)
                    .frame(minHeight: 32)
                    .background(Palette.chip, in: .capsule)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 32)
    }
}
#endif
