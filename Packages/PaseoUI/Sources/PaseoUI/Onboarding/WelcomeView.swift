#if canImport(UIKit)
import SwiftUI

/// First run with no saved host (M1b): the Paseo mark, one line, and the connection methods.
/// Direct (host/port form) plus the relay methods — Scan QR / Paste pairing link (R18).
/// Remote SSH stays desktop-only. "Settings" opens a pre-connect appearance sheet; the full Settings
/// screen needs a host. Shown once, before the first successful connection; the flag flips in
/// `AppModel.performConnect`.
public struct WelcomeView<DirectForm: View>: View {
    /// The direct-connection form (M1b's `ConnectView`), revealed by the primary tile.
    let directForm: DirectForm
    /// Scan QR / Paste pairing link tiles (R18); nil hides the tiles (previews).
    var onScan: (() -> Void)?
    var onPaste: (() -> Void)?

    @State private var stage: Stage = .welcome
    @State private var showAppearance = false

    enum Stage { case welcome, directForm }

    public init(
        onScan: (() -> Void)? = nil, onPaste: (() -> Void)? = nil,
        @ViewBuilder directForm: () -> DirectForm
    ) {
        self.onScan = onScan
        self.onPaste = onPaste
        self.directForm = directForm()
    }

    public var body: some View {
        Group {
            switch stage {
            case .welcome:
                WelcomeHome(
                    onScan: onScan, onPaste: onPaste,
                    onDirect: { stage = .directForm }, onAppearance: { showAppearance = true })
            case .directForm:
                VStack(spacing: 0) {
                    HStack {
                        Button {
                            stage = .welcome
                        } label: {
                            Label("Welcome", systemImage: "chevron.left")
                                .font(.paseo(.callout, weight: .medium))
                                .foregroundStyle(Palette.secondaryInk)
                                .frame(minHeight: 44)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("welcome.back")
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    directForm
                }
            }
        }
        .background(Palette.background.ignoresSafeArea())
        .foregroundStyle(Palette.ink)
        .sheet(isPresented: $showAppearance) { WelcomeAppearanceSheet() }
    }
}
#endif
