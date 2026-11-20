#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// One provider's detail page, pushed under Providers. The page itself is `ProviderDetailSheet`.
struct ProviderPage: View {
    let session: HostSession
    let providerID: String

    var body: some View {
        ProviderDetailSheet(session: session, providerID: providerID)
    }
}
#endif
