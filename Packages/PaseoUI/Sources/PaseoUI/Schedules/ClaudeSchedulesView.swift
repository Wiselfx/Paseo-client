#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// The Schedules screen: list what the daemon runs on a cadence, inspect a schedule's prompt and
/// run history, create or edit one, pause/resume, run once, delete. Backed by `SchedulesStore`
/// (`session.schedules`). Schedules have no push events, so the list polls on a timer while the
/// screen is open, and every page inspects/loads on appear. The page stack is hand-rolled — the
/// screen is a sheet, so there is no navigation bar.
struct ClaudeSchedulesView: View {
    let session: HostSession

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let typography = ClaudeTypography()

    /// What the editor opens with: nothing (a new schedule), or a stored schedule to edit. A
    /// heartbeat (`agent` target) edits only name, prompt, cadence and max runs.
    struct EditorSeed: Hashable {
        var stored: StoredSchedule?
        var isHeartbeat: Bool

        static let empty = EditorSeed(stored: nil, isHeartbeat: false)

        var title: String {
            guard stored != nil else { return "New schedule" }
            return isHeartbeat ? "Edit heartbeat" : "Edit schedule"
        }

        var scheduleId: String? { stored?.id }
    }

    enum Page: Hashable {
        case list
        case detail(String)
        case editor(EditorSeed)
    }

    @State private var page: Page = .list
    @State private var pendingDelete: ScheduleSummary?
    @State private var toast: String?

    private var schedules: SchedulesStore { session.schedules }

    var body: some View {
        VStack(spacing: 0) {
            switch page {
            case .list:
                SchedulesListPage(
                    session: session, typography: typography, onClose: { dismiss() },
                    onOpen: { page = .detail($0) },
                    onNew: { page = .editor(.empty) },
                    showToast: showToast)
            case .detail(let id):
                ScheduleDetailPage(
                    session: session, typography: typography, scheduleId: id,
                    onBack: { page = .list },
                    onEdit: { seed in page = .editor(seed) },
                    onDelete: { summary in pendingDelete = summary },
                    showToast: showToast)
                .id(id)
            case .editor(let seed):
                ScheduleEditorPage(
                    session: session, typography: typography, seed: seed,
                    onBack: { page = seed.scheduleId.map { .detail($0) } ?? .list },
                    onCreated: { id in page = .detail(id) },
                    showToast: showToast)
                .id(seed)
            }
        }
        .background(ClaudePalette.background)
        .foregroundStyle(ClaudePalette.ink)
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .onAppear { Task { await schedules.load() } }
        .confirmationDialog(
            "Delete schedule?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                guard let summary = pendingDelete else { return }
                pendingDelete = nil
                Task {
                    if await schedules.delete(summary.id) {
                        showToast("Schedule deleted")
                        page = .list
                    } else {
                        showToast(schedules.actionError ?? "Couldn't delete the schedule.")
                    }
                }
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("Runs that already started finish, but no new runs will be created.")
        }
        .overlay(alignment: .bottom) { toastView }
    }

    private var toastView: some View {
        Group {
            if let toast {
                Text(toast)
                    .font(typography.sans(13))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .glassEffect()
                    .padding(.bottom, 18)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
    }

    private func showToast(_ text: String) {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { toast = text }
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { toast = nil }
        }
    }
}
#endif
