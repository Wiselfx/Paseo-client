import WidgetKit

extension WidgetFamily {
    /// The Lock Screen families, which take the system's accessory background rather than
    /// the Home Screen fill.
    var isAccessory: Bool {
        switch self {
        case .accessoryRectangular, .accessoryCircular, .accessoryInline: true
        default: false
        }
    }
}
