#if canImport(UIKit)
import SwiftUI

/// The rotating home greetings, ported verbatim from DSH's
/// `packages/client/src/features/home/greetings.ts`. Wording is unchanged; when the optional
/// "Your name" setting is empty, lines that need a name are dropped before the draw.
enum ClaudeGreeting {
    static let weekdays = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

    struct Slot: Sendable {
        let from: Int
        let to: Int
        let lines: [String]
    }

    static let slots: [Slot] = [
        Slot(from: 5, to: 12, lines: [
            "Good morning, {name}!",
            "Happy {weekday}, {name}.",
            "What are you working on?",
            "Morning, {name}. What’s first?",
            "Fresh start, {name}?",
        ]),
        Slot(from: 12, to: 14, lines: [
            "What’s on the agenda today?",
            "Good afternoon, {name}.",
            "Midday check-in, {name}?",
        ]),
        Slot(from: 14, to: 18, lines: [
            "Coffee and Claude time?",
            "Good afternoon, {name}.",
            "How’s the day going, {name}?",
            "Afternoon, {name}. What’s next?",
        ]),
        Slot(from: 18, to: 22, lines: [
            "Evening, how are things?",
            "Good evening, {name}.",
            "How was your day, {name}?",
            "Winding down, or just getting started?",
        ]),
        Slot(from: 22, to: 29, lines: [
            "You are here!",
            "Hello, night owl.",
            "Burning the midnight oil, {name}?",
            "Still up, {name}?",
        ]),
    ]

    static let anytime = [
        "Back at it, {name}?",
        "Welcome back, {name}.",
        "Hey there, {name}.",
        "What shall we build?",
    ]

    /// One classic hero welcome: the current slot's pool and the any-hour lines, picked by `draw`
    /// in [0, 1). The caller holds the draw, so the line stays put between passes and changes only
    /// when the draw or the slot does.
    static func pick(username: String, draw: Double, date: Date = Date()) -> String {
        let name = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date)
        let clock = hour < 5 ? hour + 24 : hour
        var lines = anytime
        for slot in slots where clock >= slot.from && clock < slot.to {
            lines = slot.lines + anytime
        }
        if name.isEmpty {
            lines = lines.filter { !$0.contains("{name}") }
        }
        guard !lines.isEmpty else { return "What shall we build?" }
        let index = min(lines.count - 1, Int(floor(draw * Double(lines.count))))
        let weekdayIndex = min(weekdays.count - 1, max(0, calendar.component(.weekday, from: date) - 1))
        return lines[max(0, index)]
            .replacingOccurrences(of: "{name}", with: name)
            .replacingOccurrences(of: "{weekday}", with: weekdays[weekdayIndex])
    }
}

/// The Claude asterisk: twelve tapered rays around a shared centre.
struct ClaudeAsteriskMark: Shape {
    var rays: Int = 12

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        guard radius > 0, rays > 0 else { return path }
        let inner = radius * 0.06
        let baseHalf = radius * 0.07
        for index in 0..<rays {
            let angle = CGFloat(index) / CGFloat(rays) * .pi * 2 - .pi / 2
            let direction = CGPoint(x: cos(angle), y: sin(angle))
            let perpendicular = CGPoint(x: -sin(angle), y: cos(angle))
            let base = CGPoint(x: center.x + direction.x * inner, y: center.y + direction.y * inner)
            let tip = CGPoint(x: center.x + direction.x * radius, y: center.y + direction.y * radius)
            path.move(
                to: CGPoint(
                    x: base.x + perpendicular.x * baseHalf, y: base.y + perpendicular.y * baseHalf))
            path.addLine(to: tip)
            path.addLine(to: CGPoint(
                x: base.x - perpendicular.x * baseHalf, y: base.y - perpendicular.y * baseHalf))
            path.closeSubpath()
        }
        return path
    }
}

/// The home state: the mark above a serif greeting, both rising in on the DSH tokens.
struct ClaudeHomeHero: View {
    var hint: String?

    @AppStorage(PaseoSettingsKeys.yourName) private var name = ""
    @State private var draw = Double.random(in: 0..<1)
    @State private var markIn = false
    @State private var greetingIn = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let typography = ClaudeTypography()

    private var greeting: String { ClaudeGreeting.pick(username: name, draw: draw) }

    var body: some View {
        VStack(spacing: 20) {
            ClaudeAsteriskMark()
                .fill(ClaudePalette.orange)
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)
                .modifier(ClaudeHeroRise(visible: markIn, reduceMotion: reduceMotion))

            VStack(spacing: 8) {
                Text(greeting)
                    .font(typography.serif(26, relativeTo: .title))
                    .foregroundStyle(ClaudePalette.ink)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("home.greeting")
                if let hint {
                    Text(hint)
                        .font(typography.sans(15))
                        .foregroundStyle(ClaudePalette.secondaryInk)
                        .multilineTextAlignment(.center)
                }
            }
            .modifier(ClaudeHeroRise(visible: greetingIn, reduceMotion: reduceMotion))
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            if reduceMotion {
                withAnimation(.easeOut(duration: ClaudeMotion.rise)) {
                    markIn = true
                    greetingIn = true
                }
            } else {
                withAnimation(
                    .timingCurve(0.22, 1, 0.36, 1, duration: ClaudeMotion.rise)
                ) { markIn = true }
                withAnimation(
                    .timingCurve(0.22, 1, 0.36, 1, duration: ClaudeMotion.rise)
                        .delay(ClaudeMotion.stagger)
                ) { greetingIn = true }
            }
        }
    }
}

private struct ClaudeHeroRise: ViewModifier {
    let visible: Bool
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .offset(y: reduceMotion || visible ? 0 : ClaudeMotion.riseDistance)
            .blur(radius: reduceMotion || visible ? 0 : ClaudeMotion.enterBlur)
    }
}
#endif
