#if canImport(UIKit)
    import SwiftUI

    /// Settings presentation backed by host-owned state. Uncaptured destinations may be supplied by the host.
    public struct ClaudeSettingsView: View {
        @Binding private var state: ClaudeSettingsState
        public var appearance: ClaudeAppearance
        private var destinationContent: ((ClaudeSettingsDestination) -> AnyView?)?
        private let action: (ClaudeSettingsAction) -> Void
        @Environment(\.dismiss) private var dismiss
        public init(
            state: Binding<ClaudeSettingsState>, appearance: ClaudeAppearance,
            destinationContent: ((ClaudeSettingsDestination) -> AnyView?)? = nil,
            action: @escaping (ClaudeSettingsAction) -> Void
        ) {
            _state = state
            self.appearance = appearance
            self.destinationContent = destinationContent
            self.action = action
        }
        public var body: some View {
            VStack(spacing: 0) {
                header
                if let destination = state.destination, let content = destinationContent?(destination) {
                    content
                } else if state.destination == .notifications {
                    ClaudeNotificationSettingsView(preferences: state.notifications, action: action)
                } else if state.destination == .connectors {
                    ClaudeSettingsConnectorsView(state: state.connectors) { action(.connector($0)) }
                } else if state.destination == .code {
                    ClaudeCodeSettingsView(state: state.codePreferences) { action(.codePreference($0)) }
                } else if state.destination == .usage {
                    ClaudeUsageSettingsView(state: state.usage) { action(.usage($0)) }
                } else if let destination = state.destination {
                    Spacer()
                    Text(destination.rawValue).font(.title2)
                    Spacer()
                } else {
                    root
                }
            }.background(ClaudePalette.background).foregroundStyle(ClaudePalette.ink).tint(ClaudePalette.ink)
                .environment(\.symbolVariants, .none)
                .preferredColorScheme(appearance == .system ? nil : appearance == .dark ? .dark : .light)
                .presentationDetents([.large]).presentationCornerRadius(40).presentationDragIndicator(.hidden)
                .onDisappear { action(.close) }
                .sheet(
                    item: Binding(
                        get: { state.connectors.presentation },
                        set: { if $0 == nil { action(.connector(.catalog(.dismiss))) } })
                ) { presentation in
                    ClaudeConnectorCatalogView(state: state.connectors.catalog, presentation: presentation) {
                        action(.connector(.catalog($0)))
                    }.presentationDetents([.large]).presentationCornerRadius(40).presentationDragIndicator(.hidden)
                }
        }
        private var header: some View {
            ZStack {
                if state.destination == .connectors {
                    Text(
                        state.connectors.showingAllTools
                            ? "All tools"
                            : (state.connectors.tool?.name ?? state.connectors.connector?.name ?? "Connectors")
                    ).font(.system(size: 17, weight: .semibold)).lineLimit(1).padding(.horizontal, 54)
                } else {
                    Text(state.destination?.rawValue ?? "Settings").font(.system(size: 17, weight: .semibold))
                }
                HStack {
                    Button {
                        if state.destination == nil {
                            action(.close)
                            dismiss()
                        } else if state.destination == .connectors {
                            action(.connector(.back))
                        } else {
                            action(.back)
                        }
                    } label: {
                        Image(systemName: state.destination == nil ? "xmark" : "chevron.left").font(
                            .system(size: 21, weight: .light)
                        ).frame(width: 44, height: 44)
                    }.glassEffect(in: .circle).accessibilityLabel(state.destination == nil ? "Close settings" : "Back")
                        .accessibilityIdentifier("settings.back")
                    Spacer()
                    if state.destination == .connectors, state.connectors.connector == nil {
                        Menu {
                            Button {
                                action(.connector(.openCatalog))
                            } label: {
                                Label("Browse connectors", systemImage: "square.grid.2x2")
                            }
                            Button {
                                action(.connector(.openCustom))
                            } label: {
                                Label("Add custom connector", systemImage: "square.grid.2x2")
                            }
                        } label: {
                            Image(systemName: "plus").font(.system(size: 21, weight: .light)).frame(
                                width: 44, height: 44)
                        }.glassEffect(in: .circle).accessibilityLabel("Add connector").accessibilityIdentifier(
                            "settings.connectors.add")
                    } else if state.destination == .usage {
                        HStack(spacing: 0) {
                            Button {
                                action(.usage(.refresh))
                            } label: {
                                Image(systemName: "arrow.clockwise").font(.system(size: 21, weight: .light)).frame(
                                    width: 50, height: 44)
                            }.accessibilityLabel("Refresh usage").accessibilityIdentifier("settings.usage.refresh")
                            Button {
                                action(.usage(.openLink(.usageHelp, state.usage.usageHelpURL)))
                            } label: {
                                Image(systemName: "info").font(.system(size: 21)).frame(width: 50, height: 44)
                            }.accessibilityLabel("Usage information").accessibilityIdentifier("settings.usage.info")
                        }.glassEffect(in: .capsule)
                    } else if state.destination == nil {
                        Menu {
                            if !state.versionLabel.isEmpty {
                                Text(state.versionLabel)
                                Divider()
                            }
                            ForEach(ClaudeSettingsInfoLink.allCases, id: \.self) { link in
                                if link == .support { Divider() }
                                Button {
                                    action(.infoLink(link))
                                } label: {
                                    Label(
                                        link.rawValue,
                                        systemImage: link == .licenses ? "doc.text" : "arrow.up.right.square")
                                }
                            }
                        } label: {
                            Image(systemName: "info").font(.system(size: 21)).frame(width: 44, height: 44)
                        }.glassEffect(in: .circle).accessibilityLabel("About").accessibilityIdentifier("settings.about")
                    }
                }
            }.frame(height: 44).padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 0)
        }
        private var root: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    sectionLabel("Account")
                    RowGroup {
                        settingsRow(.usage, symbol: "chart.xyaxis.line")
                        rowDivider
                        settingsRow(.notifications, symbol: "bell")
                    }
                    sectionLabel("App")
                    RowGroup {
                        settingsRow(.code, symbol: "chevron.left.forwardslash.chevron.right")
                        rowDivider
                        settingsRow(.connectors, symbol: "square.grid.2x2")
                        rowDivider
                        settingsRow(.voice, symbol: "waveform")
                        rowDivider
                        Toggle(isOn: Binding(get: { state.hapticsEnabled }, set: { action(.setHaptics($0)) })) {
                            Label("Haptic feedback", systemImage: "iphone.gen3.radiowaves.left.and.right").font(
                                .system(size: 17))
                        }.tint(.blue).padding(.horizontal, 16).frame(height: 52).accessibilityIdentifier(
                            "settings.haptics")
                    }
                    sectionLabel("Appearance")
                    HStack(spacing: 10) {
                        ForEach([ClaudeAppearance.light, .dark, .system], id: \.self) { choice in
                            Button {
                                action(.setAppearance(choice))
                            } label: {
                                VStack(spacing: 9) {
                                    ThemeThumbnail(appearance: choice).frame(height: 68).overlay {
                                        RoundedRectangle(cornerRadius: 14).stroke(
                                            appearance == choice ? Color.blue : .clear, lineWidth: 2)
                                    }
                                    Text(choice.rawValue).font(.system(size: 14)).foregroundStyle(
                                        appearance == choice ? .blue : ClaudePalette.secondary)
                                }
                            }.buttonStyle(.plain).accessibilityLabel("\(choice.rawValue) appearance")
                                .accessibilityAddTraits(appearance == choice ? [.isSelected] : [])
                                .accessibilityIdentifier("settings.appearance." + choice.rawValue)
                        }
                    }.padding(16).background(ClaudePalette.panel, in: .rect(cornerRadius: 28))
                }.padding(.horizontal, 16).padding(.top, 26).padding(.bottom, 20)
            }.accessibilityIdentifier("settings.root.scroll")
        }
        private var rowDivider: some View { Divider().padding(.leading, 56).padding(.trailing, 16) }
        private func sectionLabel(_ title: String) -> some View {
            Text(title).font(.system(size: 15)).foregroundStyle(ClaudePalette.secondary).padding(.leading, 16).padding(
                .top, 8
            ).padding(.bottom, -8)
        }
        private func settingsRow(
            _ destination: ClaudeSettingsDestination, symbol: String, value: String = "", tint: Color? = nil,
            chevron: Bool = true
        ) -> some View {
            Button {
                action(.open(destination))
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: symbol).font(.system(size: 20, weight: .light)).frame(width: 26).foregroundStyle(
                        tint ?? ClaudePalette.ink.opacity(0.75))
                    Text(destination.rawValue).frame(maxWidth: .infinity, alignment: .leading)
                    if !value.isEmpty { Text(value).foregroundStyle(ClaudePalette.secondary) }
                    if chevron {
                        Image(systemName: "chevron.right").font(.system(size: 15)).foregroundStyle(
                            ClaudePalette.secondary)
                    }
                }.font(.system(size: 17)).foregroundStyle(tint ?? ClaudePalette.ink).padding(.horizontal, 16).frame(
                    height: 51
                ).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("settings.route." + destination.rawValue)
        }
    }
#endif
