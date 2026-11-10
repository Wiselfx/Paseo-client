#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// The Schedules sheet: `SheetScaffold` provides the header and the `NavigationStack`, so the
/// detail and editor pages push and swipe-back returns to the list. Backed by `SchedulesStore`
/// (`session.schedules`). Schedules have no push events, so the list polls while it is on
/// screen and the app is active.
struct ClaudeSchedulesView: View {
    let session: HostSession

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

    /// A pushed page. The editor is pushed through `editorRequest` instead, because its triggers
    /// are buttons (menu items, the toolbar), not rows.
    enum Route: Hashable {
        case detail(String)
        case editor(EditorSeed)
    }

    @State private var editorRequest: EditorSeed?

    var body: some View {
        SheetScaffold("Schedules", detents: .large) {
            SchedulesListPage(session: session, onNew: { editorRequest = .empty })
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .detail(let id):
                        ScheduleDetailPage(session: session, scheduleId: id)
                    case .editor(let seed):
                        ScheduleEditorPage(session: session, seed: seed)
                    }
                }
                .navigationDestination(item: $editorRequest) { seed in
                    ScheduleEditorPage(session: session, seed: seed)
                }
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            editorRequest = .empty
                        } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel("New schedule")
                        .accessibilityIdentifier("schedules.new")
                    }
                }
        }
    }
}
#endif
