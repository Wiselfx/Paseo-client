#if canImport(UIKit)
import SwiftUI

/// A GitHub link as a row card: the slug, kind and glyph before the forge lookup answers
/// (`state` nil), and the looked-up title with a state pill once it has (C7). The card above
/// owns the Safari presentation; the row only asks to open.
struct GitHubLinkRow: View {
    let glyph: String
    let title: String
    let slug: String
    /// The forge's state for the link, nil before the lookup answers.
    let state: String?
    let url: String
    let onOpen: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: onOpen) {
            if let state {
                PaseoRowCard(
                    glyph: glyph, title: title,
                    meta: "\(slug) · \(stateLabel(state))",
                    accessory: StatePill(stateLabel(state), tone: stateTone(state)))
            } else {
                PaseoRowCard(glyph: glyph, title: title, meta: "github.com")
            }
        }
        .buttonStyle(PaseoCardButtonStyle(reduceMotion: reduceMotion))
        .paseoCardMenu(
            openTitle: "Open",
            onOpen: onOpen,
            copyTitle: "Copy link",
            copyText: url,
            externalTitle: "Open on GitHub",
            externalURL: URL(string: url))
        .paseoCardAccessibility(
            kind: "GitHub link", title: title,
            meta: state.map { "\(slug) \(stateLabel($0))" } ?? "github.com", isButton: true)
    }

    private func stateLabel(_ state: String) -> String {
        return switch state.lowercased() {
        case "open": "Open"
        case "closed": "Closed"
        case "merged": "Merged"
        case "draft": "Draft"
        default: state
        }
    }

    private func stateTone(_ state: String) -> StatePill.Tone {
        return switch state.lowercased() {
        case "open", "merged": .success
        case "closed": .failure
        default: .neutral
        }
    }
}
#endif
