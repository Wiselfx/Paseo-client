#if canImport(UIKit)
import SwiftUI

/// A small state capsule: the tone color at 0.14 behind its ink.
struct StatePill: View {
    enum Tone {
        case neutral
        case success
        case failure
        case warning
    }

    private let text: String
    private let tone: Tone

    init(_ text: String, tone: Tone) {
        self.text = text
        self.tone = tone
    }

    var body: some View {
        Text(text)
            .font(.paseo(.caption2, weight: .medium))
            .foregroundStyle(ink)
            .lineLimit(1)
            .padding(.horizontal, Space.sm)
            .padding(.vertical, 3)
            .background(color.opacity(0.14), in: .capsule)
    }

    private var color: Color {
        switch tone {
        case .neutral: Palette.secondaryInk
        case .success: Palette.successInk
        case .failure: Palette.failureInk
        case .warning: Palette.warning
        }
    }

    private var ink: Color {
        switch tone {
        case .neutral: Palette.ink
        case .success: Palette.successInk
        case .failure: Palette.failureInk
        case .warning: Palette.warning
        }
    }
}

#Preview("Light") {
    HStack(spacing: Space.sm) {
        StatePill("Neutral", tone: .neutral)
        StatePill("Success", tone: .success)
        StatePill("Failure", tone: .failure)
        StatePill("Warning", tone: .warning)
    }
    .padding()
    .background(Palette.background)
    .preferredColorScheme(.light)
}

#Preview("Dark") {
    HStack(spacing: Space.sm) {
        StatePill("Neutral", tone: .neutral)
        StatePill("Success", tone: .success)
        StatePill("Failure", tone: .failure)
        StatePill("Warning", tone: .warning)
    }
    .padding()
    .background(Palette.background)
    .preferredColorScheme(.dark)
}
#endif
