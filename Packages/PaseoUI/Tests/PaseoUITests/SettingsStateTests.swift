import Foundation
import Testing
@testable import PaseoUI

private func settingsConnectorFixture() -> ClaudeSettingsConnectorState {
    .init(
        discovery: true,
        connectors: [
            .init(
                id: "connected", name: "Host connector", connected: true,
                tools: [
                    .init(id: "a", name: "A", permission: .approval), .init(id: "b", name: "B", permission: .blocked)
                ]), .init(id: "offline", name: "Available")
        ], toolDescriptions: ["connected": ["a": "Host description"]])
}

@Test func notificationPreferencesToggleIndependentlyAndIdempotently() {
    var state = ClaudeSettingsState()
    for preference in ClaudeNotificationPreference.allCases {
        state.reduce(.setNotification(preference, true))
        state.reduce(.setNotification(preference, true))
        #expect(state.notifications.enabled == [preference])
        state.reduce(.setNotification(preference, false))
        #expect(state.notifications.enabled.isEmpty)
    }
    #expect(ClaudeNotificationPreference.groups.flatMap { $0 } == ClaudeNotificationPreference.allCases)
}
@Test func notificationPreferencesRoundTripForHostPersistence() throws {
    let preferences = ClaudeNotificationPreferences(enabled: [.replies, .dispatchMessages, .codePermissions])
    let restored = try JSONDecoder().decode(ClaudeNotificationPreferences.self, from: JSONEncoder().encode(preferences))
    #expect(restored == preferences)
}
@Test func usageUnknownValuesAreDistinctFromZeroAndFiniteValuesAreClamped() {
    for invalid in [Double.nan, .infinity, -.infinity] {
        let meter = ClaudeUsageMeter(id: "m", title: "Meter", usedPercentage: invalid)
        #expect(meter.fractionUsed == nil)
        #expect(meter.usageLabel == "—")
        #expect(ClaudeUsageCredit(id: "c", title: "Credit", usedPercentage: invalid).fractionUsed == nil)
    }
    #expect(ClaudeUsageMeter(id: "m", title: "Meter").fractionUsed == nil)
    #expect(ClaudeUsageMeter(id: "m", title: "Meter", usedPercentage: 0).usageLabel == "0% used")
    for (input, output) in [(-4.0, 0.0), (25.5, 0.255), (999.0, 1.0)] {
        #expect(ClaudeUsageMeter(id: "m", title: "Meter", usedPercentage: input).fractionUsed == output)
        #expect(ClaudeUsageCredit(id: "c", title: "Credit", usedPercentage: input).fractionUsed == output)
    }
}
@Test func usageHostRequestsDoNotChangeBalancesConsentOrNavigation() {
    var state = ClaudeSettingsState()
    state.usage = .init(creditsEnabled: true, balanceLabel: "18 credits")
    state.reduce(.open(.usage))
    let original = state
    for action in [
        ClaudeUsageAction.refresh, .requestPurchase, .requestCreditsEnabled(false), .requestCreditsEnabled(true),
        .openLink(.usageHelp, nil), .openLink(.creditsHelp, URL(string: "https://example.com/help"))
    ] {
        state.reduce(.usage(action))
        #expect(state == original)
    }
}
@Test func usageHostDataIsPreservedAcrossNewSessionWithoutInventedDefaults() {
    var session = SessionState()
    #expect(session.settings.usage.currentSession == nil)
    #expect(session.settings.usage.weekly.isEmpty)
    #expect(session.settings.usage.balanceLabel == "—")
    #expect(!session.settings.usage.creditsEnabled)
    let value = ClaudeUsageState(
        weekly: [.init(id: "custom", title: "Host model", usedPercentage: 50)], creditsEnabled: true,
        balanceLabel: "Host amount", credits: [.init(id: "c", title: "Host transaction")],
        usageHelpURL: URL(string: "https://example.com/help"))
    session.settings.usage = value
    session.reduce(.settings(.open(.usage)))
    session.reduce(.newSession)
    #expect(session.settings.usage == value)
    #expect(session.settings.destination == nil)
}

@Test func codePreferenceSizeClampsFinitePositionsAndIgnoresNonfiniteChanges() {
    var state = ClaudeCodePreferences()
    #expect(state.transcriptSizePosition == 0.5)
    for (input, output) in [(-1.0, 0.0), (0.33, 0.33), (4.0, 1.0)] {
        state.reduce(.transcriptSizePosition(input))
        #expect(state.transcriptSizePosition == output)
    }
    for value in [Double.nan, .infinity, -.infinity] {
        state.reduce(.transcriptSizePosition(value))
        #expect(state.transcriptSizePosition == 1)
        #expect(ClaudeCodePreferences(transcriptSizePosition: value).transcriptSizePosition == 0.5)
    }
}
@Test func codePreferencesPersistIndependentlyWithoutBundledFonts() throws {
    var state = ClaudeCodePreferences()
    state.reduce(.transcriptFont(.anthropicSans))
    state.reduce(.codeFont(.jetBrainsMono))
    state.reduce(.wrapLongLines(true))
    #expect(state.transcriptSizePosition == 0.5)
    #expect(try JSONDecoder().decode(ClaudeCodePreferences.self, from: JSONEncoder().encode(state)) == state)
    var session = SessionState()
    session.settings.codePreferences = state
    session.reduce(.settings(.open(.code)))
    session.reduce(.newSession)
    #expect(session.settings.codePreferences == state)
    session.reduce(.settings(.codePreference(.wrapLongLines(false))))
    #expect(!session.settings.codePreferences.wrapLongLines)
    #expect(session.settings.codePreferences.codeFont == .jetBrainsMono)
}
@Test func codePreferenceDecoderSanitizesHostPosition() throws {
    let json = Data(
        "{\"transcriptSizePosition\":30,\"transcriptFont\":\"System\",\"codeFont\":\"SF Mono\",\"wrapLongLines\":false}"
            .utf8)
    #expect(try JSONDecoder().decode(ClaudeCodePreferences.self, from: json).transcriptSizePosition == 1)
}

@Test func settingsConnectorRequestsNeverMutateHostConnectionOrPolicies() {
    var state = settingsConnectorFixture()
    let original = state
    for action in [
        ClaudeSettingsConnectorAction.requestDiscovery(false), .requestConnect("offline"), .requestCatalog,
        .requestAllTools("connected"), .requestPermission(connector: "connected", tool: "a", permission: .allowed)
    ] {
        state.reduce(action)
        #expect(state == original)
    }
}
@Test func settingsConnectorNavigationValidatesHostRecordsAndBackHierarchy() {
    var state = settingsConnectorFixture()
    state.reduce(.openConnector("offline"))
    #expect(state.connector == nil)
    state.reduce(.openConnector("missing"))
    #expect(state.connector == nil)
    state.reduce(.openConnector("connected"))
    state.reduce(.openTool("missing"))
    #expect(state.tool == nil)
    state.reduce(.openTool("a"))
    #expect(state.toolDescription == "Host description")
    state.reduce(.back)
    #expect(state.tool == nil)
    #expect(state.connector != nil)
    state.reduce(.back)
    #expect(state.connector == nil)
}
@Test func settingsConnectorCloseAndHostRemovalCannotExposeStalePermission() {
    var session = SessionState()
    session.settings.connectors = settingsConnectorFixture()
    session.reduce(.settings(.open(.connectors)))
    session.reduce(.settings(.connector(.openConnector("connected"))))
    session.reduce(.settings(.connector(.openTool("a"))))
    session.reduce(.newSession)
    #expect(session.settings.connectors.tool == nil)
    #expect(session.settings.connectors.discovery)
    var state = settingsConnectorFixture()
    state.reduce(.openConnector("connected"))
    state.reduce(.openTool("a"))
    state.connectors = []
    #expect(state.tool == nil)
    #expect(state.toolDescription.isEmpty)
}

@Test func connectorCatalogFiltersIntersectAndSortStably() {
    var state = ClaudeConnectorCatalogState(
        items: [
            .init(id: "b", name: "Beta", detail: "Health notes", categories: ["Health"], ranks: [.popular: 2]),
            .init(id: "a", name: "Alpha", categories: ["Work"], ranks: [.popular: 1]),
            .init(id: "c", name: "Gamma", detail: "Health study", categories: ["Health"], ranks: [.popular: 2])
        ], categories: ["Health", "Work"])
    state.reduce(.sort(.popular))
    #expect(state.visibleItems.map(\.id) == ["a", "b", "c"])
    state.reduce(.category("Health"))
    state.reduce(.search("  STUDY "))
    #expect(state.visibleItems.map(\.id) == ["c"])
    state.reduce(.category("Unknown"))
    #expect(state.category == "Health")
    state.reduce(.search(""))
    state.reduce(.category(nil))
    state.reduce(.sort(.alphabetical))
    #expect(state.visibleItems.map(\.id) == ["a", "b", "c"])
    state.reduce(.search("No match"))
    #expect(state.visibleItems.isEmpty)
}
@Test func customConnectorValidationRejectsNonHTTPSCredentialsAndBlankDrafts() {
    var state = ClaudeConnectorCatalogState()
    state.reduce(.editName("  "))
    state.reduce(.editURL("https://example.com/mcp"))
    #expect(!state.draft.canSubmit)
    state.reduce(.editName("Example"))
    #expect(state.draft.canSubmit)
    for value in [
        "", "http://example.com", "https://", "https://user:pass@example.com", "https://example.com/#fragment",
        "https://ex ample.com", "file:///tmp/a"
    ] {
        state.reduce(.editURL(value))
        #expect(!state.draft.canSubmit)
    }
    state.reduce(.editURL(" https://example.com/mcp?version=1 "))
    #expect(state.draft.canSubmit)
    let original = state
    state.reduce(.requestCustom(name: "Example", url: state.draft.validatedURL!))
    #expect(state == original)
    state.reduce(.dismiss)
    #expect(state.draft == ClaudeCustomConnectorDraft())
}
@Test func catalogConnectionRequestsAndBulkPoliciesAreHostOwned() {
    var state = settingsConnectorFixture()
    state.catalog = .init(items: [.init(id: "a", name: "A")])
    state.reduce(.openCatalog)
    let rows = state.catalog.items
    state.reduce(.catalog(.requestConnect("a")))
    #expect(state.catalog.items == rows)
    state.reduce(.catalog(.dismiss))
    #expect(state.presentation == nil)
    state.reduce(.openConnector("connected"))
    state.reduce(.openAllTools)
    #expect(state.showingAllTools)
    #expect(state.connector?.commonPermission == nil)
    let connectors = state.connectors
    state.reduce(.requestAllPermissions(connector: "connected", permission: .allowed))
    #expect(state.connectors == connectors)
    state.reduce(.back)
    #expect(!state.showingAllTools)
    #expect(state.connector != nil)
    state.reduce(.back)
    state.reduce(.openAllTools)
    #expect(!state.showingAllTools)
}
@Test func catalogCloseAndNewSessionClearDraftWithoutChangingHostData() {
    var session = SessionState()
    session.settings.connectors = settingsConnectorFixture()
    session.reduce(.settings(.open(.connectors)))
    session.reduce(.settings(.connector(.openCustom)))
    session.reduce(.settings(.connector(.catalog(.editName("Draft")))))
    #expect(session.settings.connectors.catalog.draft.name == "Draft")
    let rows = session.settings.connectors.connectors
    session.reduce(.newSession)
    #expect(session.settings.connectors.presentation == nil)
    #expect(session.settings.connectors.catalog.draft.name.isEmpty)
    #expect(session.settings.connectors.connectors == rows)
    session.reduce(.settings(.connector(.catalog(.editName("Stale")))))
    #expect(session.settings.connectors.catalog.draft.name.isEmpty)
}
@Test func bulkPolicyNavigationCannotOutliveHostConnector() {
    var state = settingsConnectorFixture()
    state.reduce(.openConnector("connected"))
    state.reduce(.openAllTools)
    #expect(state.showingAllTools)
    state.connectors = []
    #expect(!state.showingAllTools)
    #expect(state.connector == nil)
    state.connectors = settingsConnectorFixture().connectors
    state.reduce(.openConnector("connected"))
    #expect(!state.showingAllTools)
    state.reduce(.openAllTools)
    state.reduce(.openTool("a"))
    #expect(!state.showingAllTools)
    #expect(state.tool?.id == "a")
}
