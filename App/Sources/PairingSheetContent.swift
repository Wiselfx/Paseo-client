import PaseoStore
import PaseoUI
import SwiftUI

/// The content of the pairing sheet: one view per step of `RootView.PairingSheet`, so the
/// root's body routes to it and the root keeps the flow logic. The root passes its actions in;
/// nothing here touches the model.
struct PairingSheetContent: View {
    let sheet: RootView.PairingSheet
    let isAttempting: Bool
    /// The daemon's shown name for the password title.
    let hostName: (ConnectionOffer) -> String
    /// A scanned or pasted pairing payload.
    let onPayload: (String) -> Void
    let onUsePaste: () -> Void
    /// Connect with the staged offer: the typed password (nil when none was asked for) and
    /// whether it came from the password sheet.
    let onPair: (RootView.PendingPairing, String?, Bool) -> Void
    let onChooseHost: (RootView.HostChoice, DeepLinkHost) -> Void

    var body: some View {
        switch sheet {
        case .scan:
            PairScanSheet(
                onScanned: { payload in
                    onPayload(payload)
                },
                onUsePaste: onUsePaste)
        case .paste(let error):
            PastePairingSheet(error: error) { payload in
                onPayload(payload)
            }
        case .confirm(let pending):
            HostConfirmationPairingSheet(
                offer: pending.offer, kind: pending.kind,
                isAttempting: isAttempting
            ) {
                onPair(pending, nil, false)
            }
        case .password(let pending, let error):
            PairingPasswordSheet(
                host: hostName(pending.offer),
                error: error,
                isAttempting: isAttempting
            ) { entered in
                onPair(pending, entered, true)
            }
        case .chooseHost(let choice):
            HostChooserSheet(hosts: choice.hosts) { host in
                onChooseHost(choice, host)
            }
        }
    }
}
