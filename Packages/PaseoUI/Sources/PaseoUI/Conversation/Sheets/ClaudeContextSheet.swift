#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// The composer's context-window details, fed by `ConversationStore.contextUsage` — the
/// host's snapshot values and the live window fields from the stream. No placeholder numbers:
/// rows only appear when the host reports them, and agents with no usage get a calm line.
struct ClaudeContextSheet: View {
    let store: ConversationStore

    var body: some View {
        SheetScaffold("Context", detents: .mediumLarge) {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.lg) {
                    if let usage = store.contextUsage {
                        // A session with a window gets the meter; a session the provider reports
                        // without one keeps its figures and gets upstream's `contextWindow.noData`
                        // line where the percentage would be. Only a host that reports nothing at
                        // all falls through to the empty state (H3 §1).
                        if let percent = usage.percentUsed {
                            ContextMeterRow(percent: percent, maxTokens: usage.maxTokens)
                        } else {
                            ContextNoWindowRow()
                        }
                        ContextDetailsSection(usage: usage)
                        ContextTurnChartsSection(points: store.recentTurnUsage)
                        CostByModelSection(usage: usage)
                    } else {
                        EmptyState(
                            title: "No context data",
                            message: "This agent's host does not report context usage yet."
                        )
                        .padding(.horizontal, Space.lg)
                        .padding(.top, Space.xl)
                    }
                }
                .padding(.bottom, Space.xl)
            }
            .scrollIndicators(.hidden)
        }
    }

    static func tokenCount(_ value: Int) -> String {
        PaseoFormat.compactCount(value)
    }

    static func percentValue(_ value: Double) -> String {
        PaseoFormat.percent(value)
    }

    static func cost(_ value: Double, fractionDigits: Int = 2) -> String {
        value.formatted(.currency(code: "USD").precision(.fractionLength(fractionDigits)))
    }

    static func modelName(_ key: String) -> String {
        key.isEmpty ? "model" : key
    }
}
#endif
