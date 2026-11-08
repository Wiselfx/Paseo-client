import SwiftUI
import PaseoUI

@main
struct PaseoClientApp: App {
    @State private var model = AppModel()

    init() { Typeset.registerFonts() }

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .tint(Palette.accent)
        }
    }
}
