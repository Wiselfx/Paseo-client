#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// Settings → General: appearance, fonts, your name, feedback, notifications and chat display.
/// A local page: everything here is `@AppStorage`, so there is nothing to refresh (PLAN §RE).
/// Each section owns only the keys it reads, so changing one setting re-evaluates one section.
struct GeneralPage: View {
    var body: some View {
        PageList {
            GeneralAppearanceSection()
            GeneralFontsSection()
            GeneralYouSection()
            GeneralFeedbackSection()
            GeneralNotificationsSection()
            GeneralPermissionsSection()
            GeneralPrivacySection()
            GeneralChatSection()
        }
        .inlinePageTitle("General")
    }
}
#endif
