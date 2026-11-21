import AppIntents

/// App Shortcuts with plain names.
struct PaseoShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenAgentIntent(),
            phrases: [
                "Open \(.applicationName) agent",
                "Show \(.applicationName) agent",
            ],
            shortTitle: "Open agent",
            systemImageName: "message")
        AppShortcut(
            intent: NewAgentIntent(),
            phrases: [
                "New \(.applicationName) agent",
                "Start \(.applicationName) agent",
            ],
            shortTitle: "New agent",
            systemImageName: "plus.message")
    }
}
