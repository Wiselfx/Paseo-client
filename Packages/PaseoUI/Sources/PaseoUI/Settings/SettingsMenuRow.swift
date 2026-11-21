#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// A settings row whose trailing value opens a menu (font sizes, scrollback, chat display).
/// The menu's tap target is the whole R4 row.
struct SettingsMenuRow<MenuContent: View>: View {
    private let title: String
    private let value: String
    private let menu: MenuContent

    init(_ title: String, value: String, @ViewBuilder menu: () -> MenuContent) {
        self.title = title
        self.value = value
        self.menu = menu()
    }

    var body: some View {
        Menu {
            menu
        } label: {
            ListRow(title: title, accessory: ListRow.Accessory.value(value))
        }
        .panelRow()
        .accessibilityLabel("\(title), currently \(value)")
    }
}
#endif
