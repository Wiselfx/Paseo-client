#if canImport(UIKit)
import PaseoStore
import SwiftUI

// MARK: - Confirmation

/// "Connect to this host?" with the three rows (Host = serverId, Key fingerprint, Relay =
/// endpoint), upstream wording verbatim. Exact-match links never reach here.
public struct HostConfirmationPairingSheet: View {
    public let offer: ConnectionOffer
    public let kind: HostConfirmationKind
    /// True while a connect attempt is in flight: Connect is disabled (one attempt at a
    /// time, S1), with a spinner in place of the label.
    public var isAttempting: Bool
    public var onConnect: () -> Void

    public init(
        offer: ConnectionOffer, kind: HostConfirmationKind, isAttempting: Bool = false,
        onConnect: @escaping () -> Void
    ) {
        self.offer = offer
        self.kind = kind
        self.isAttempting = isAttempting
        self.onConnect = onConnect
    }
    @Environment(\.dismiss) private var dismiss

    public var body: some View {
        SheetScaffold("Connect to this host?", detents: .large) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(kind == .changedConnection
                        ? "This link changes how you connect to this host. The host will be able to run code in this app and reach your other connected hosts. Only connect if you recognize it."
                        : "This host will be able to run code in this app and reach your other connected hosts. Only connect if you recognize it.")
                        .font(.paseo(.callout))
                        .foregroundStyle(Palette.secondaryInk)
                    RowGroup {
                        HostConfirmationDetailRow(label: "Host", value: offer.serverID)
                        RowDivider()
                        HostConfirmationDetailRow(
                            label: "Key fingerprint",
                            value: HostConfirmation.keyFingerprint(offer.daemonPublicKeyB64))
                        RowDivider()
                        HostConfirmationDetailRow(label: "Relay", value: offer.relayEndpoint)
                    }
                    HStack(spacing: 10) {
                        Button("Cancel") { dismiss() }
                            .font(.paseo(.callout, weight: .medium))
                            .buttonStyle(.bordered)
                            .frame(maxWidth: .infinity)
                            .accessibilityIdentifier("pairing.confirm.cancel")
                        Button {
                            onConnect()
                        } label: {
                            Text("Connect")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.paseoPrimary(isWorking: isAttempting))
                        .disabled(isAttempting)
                        .accessibilityIdentifier("pairing.confirm.connect")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .scrollIndicators(.hidden)
        }
    }
}
#endif
