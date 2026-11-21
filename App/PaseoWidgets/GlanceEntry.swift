import Foundation
import WidgetKit

/// One timeline entry: the App Group snapshot at that moment, or nil when there is none.
struct GlanceEntry: TimelineEntry {
    let date: Date
    let snapshot: GlanceMirror?
}
