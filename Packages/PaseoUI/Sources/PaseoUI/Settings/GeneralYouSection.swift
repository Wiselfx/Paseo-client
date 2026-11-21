#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// General → You: the name used in the home greeting and the sidebar avatar.
struct GeneralYouSection: View {
    @AppStorage(PaseoSettingsKeys.yourName) private var name = ""

    var body: some View {
        Section {
            HStack(spacing: Space.sm) {
                Text("Your name")
                    .font(.paseo(.body))
                    .foregroundStyle(Palette.ink)
                Spacer(minLength: Space.sm)
                TextField("Your name", text: $name)
                    .font(.paseo(.body))
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.words)
            }
            .padding(.horizontal, Space.lg)
            .frame(minHeight: 44)
            .panelRow()
        } header: {
            Text("You")
        } footer: {
            Text("Used in the greeting on the home screen and the sidebar avatar.")
        }
    }
}
#endif
