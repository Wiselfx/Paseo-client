#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// M7g: a quiet row near the transcript end while the daemon reports background work,
/// tapping through to the sheet (kind, command/label, started, Stop with confirmation
/// for shells) when the stop gate is on.

struct BackgroundWorkRow: View {
    let items: [BackgroundWorkItem]
    let action: () -> Void


    /// "2 background tasks" / "1 background task".
    private var text: String {
        items.count == 1 ? "1 background task" : "\(items.count) background tasks"
    }

    var body: some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            HStack(spacing: 8) {
                ClaudeGlyph(kind: .api, size: 13, color: Palette.tertiaryInk)
                Text(text)
                    .font(.paseo(.footnote))
                    .foregroundStyle(Palette.secondaryInk)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.glyph(.small, weight: .semibold))
                    .foregroundStyle(Palette.tertiaryInk)
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(Palette.adaptive(light: 0.96, dark: 0.10), in: .rect(cornerRadius: Radius.sm))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("transcript.backgroundWork")
        .accessibilityLabel(text)
    }
}

/// The sheet that lists background work with a Stop affordance per stoppable item.
struct ChatBackgroundWorkSheet: View {
    let backgroundWork: BackgroundWorkStore

    @State private var pendingStop: BackgroundWorkItem?

    private var canStop: Bool { backgroundWork.canStop }

    var body: some View {
        SheetScaffold("Background work", detents: .mediumLarge) {
            Group {
                if backgroundWork.items.isEmpty {
                    EmptyState(
                        systemImage: "gearshape.2",
                        title: "No background tasks",
                        message: "Background work your agent starts appears here."
                    )
                    .padding(.horizontal, 40)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(backgroundWork.items) { item in
                                backgroundWorkRow(item)
                                if item.id != backgroundWork.items.last?.id {
                                    ClaudeDivider().padding(.leading, 52)
                                }
                            }
                            if let error = backgroundWork.error {
                                InlineBanner(.failure, title: error)
                                    .padding(.horizontal, Space.lg)
                                    .padding(.vertical, 10)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .confirmationDialog(
                "Stop this background task?",
                isPresented: Binding(
                    get: { pendingStop != nil },
                    set: { if !$0 { pendingStop = nil } }),
                titleVisibility: .visible,
                presenting: pendingStop
            ) { item in
                Button("Stop", role: .destructive) {
                    performStop(item)
                    pendingStop = nil
                }
                Button("Cancel", role: .cancel) { pendingStop = nil }
            } message: { _ in
                Text("Its output will be discarded.")
            }
            .task { await backgroundWork.load() }
        }
    }

    private func performStop(_ item: BackgroundWorkItem) {
        // Refusals land in the store's `error`, rendered inline under the list.
        Task { _ = await backgroundWork.stop(itemId: item.id) }
    }

    private func backgroundWorkRow(_ item: BackgroundWorkItem) -> some View {
        HStack(spacing: 12) {
            ClaudeGlyph(kind: glyph(for: item.kind), size: 15, color: Palette.tertiaryInk)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(rowTitle(item))
                    .font(.paseo(.callout, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(item.kind)
                        .font(.paseo(.codeCaption))
                    Text("·")
                    Text(startedText(item.startedAt))
                }
                .font(.paseo(.codeCaption))
                .foregroundStyle(Palette.tertiaryInk)
            }
            Spacer(minLength: 8)
            if canStop && item.canStop == true, item.stopToken != nil {
                Button("Stop") {
                    Haptics.selection()
                    if item.kind == "shell" {
                        pendingStop = item
                    } else {
                        performStop(item)
                    }
                }
                .font(.paseo(.footnote, weight: .medium))
                .foregroundStyle(Palette.failureInk)
                .padding(.horizontal, 14)
                .frame(minHeight: 32)
                .background(Palette.adaptive(light: 0.96, dark: 0.18), in: .capsule)
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
    }

    private func rowTitle(_ item: BackgroundWorkItem) -> String {
        item.command ?? item.description ?? item.kind
    }

    private func glyph(for kind: String) -> ClaudeGlyph.Kind {
        switch kind {
        case "monitor": .browse
        default: .api
        }
    }

    private func startedText(_ iso: String) -> String {
        guard let date = PaseoDate.parse(iso) else {
            return iso.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let seconds = max(0, Date().timeIntervalSince(date))
        if seconds < 3600 {
            return "started \(Int(seconds / 60))m ago"
        }
        if Calendar.current.isDateInToday(date) {
            return "started \(PaseoFormat.time(date))"
        }
        return "started \(PaseoFormat.dateTime(date))"
    }
}
#endif
