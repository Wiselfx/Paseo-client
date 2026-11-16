// features: F01 F16
// Fixture: launch reads nothing slow in init; fonts are registered in one call.
import SwiftUI

@main
struct GoodApp: App {
    @State private var model = GoodAppModel()
    @State private var notifications = NotificationCoordinator()

    var body: some Scene {
        WindowGroup { Text("x") }
    }
}

enum GoodFonts {
    static func register(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        CTFontManagerRegisterFontURLs(urls as CFArray, .process, true, nil)
    }
}
