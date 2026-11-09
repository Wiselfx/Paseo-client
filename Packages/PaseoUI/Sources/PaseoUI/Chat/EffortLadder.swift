#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// The reasoning-effort ladder (M7i, `effort` in DSH): a compact Faster ↔ Smarter control for a
/// model's ranked thinking levels.
///
/// Levels are ordered by a strength table ported from DSH's `ladder.ts` — `none`/`off` at the
/// floor, `minimal` … `max` up top. If a provider's options aren't all ranked levels (or fewer
/// than two exist), callers should fall back to the plain list — see `EffortLadder.ranked`.
struct EffortLadder: View {
    let options: [ProviderThinkingOption]
    /// nil when the provider default is in force.
    let selectedId: String?
    let onSelect: (String?) -> Void

    private let typography = ClaudeTypography()

    /// Effort id → strength, larger is stronger. Ported from DSH's EFFORT_STRENGTH
    /// (`effort/ladder.ts`); `auto` is a provider "let the model decide" flag and ranks as none.
    static let strength: [String: Int] = [
        "none": 0, "off": 0, "auto": 0,
        "minimal": 1,
        "light": 2,
        "low": 3,
        "medium": 4,
        "high": 5, "on": 5,
        "xhigh": 6,
        "max": 7,
        "ultra": 8,
    ]

    /// The options as a ladder, weakest → strongest. Nil when they aren't ranked levels.
    static func ranked(_ options: [ProviderThinkingOption]) -> [ProviderThinkingOption]? {
        guard options.count >= 2 else { return nil }
        guard options.allSatisfy({ strength[$0.id.lowercased()] != nil }) else { return nil }
        return options.sorted { strengthRank($0.id) < strengthRank($1.id) }
    }

    private static func strengthRank(_ id: String) -> Int {
        strength[id.lowercased()] ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // The provider default row: level in force when the user hasn't picked one.
            Button {
                Haptics.selection()
                onSelect(nil)
            } label: {
                HStack(spacing: 10) {
                    Circle()
                        .stroke(selectedId == nil ? ClaudePalette.orange : ClaudePalette.tertiaryInk, lineWidth: 1.5)
                        .frame(width: 18, height: 18)
                        .overlay {
                            if selectedId == nil {
                                Circle().fill(ClaudePalette.orange).frame(width: 8, height: 8)
                            }
                        }
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Provider default")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(ClaudePalette.ink)
                        Text("Use the provider's level for this model")
                            .font(.system(size: 12))
                            .foregroundStyle(ClaudePalette.secondaryInk)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selectedId == nil ? .isSelected : [])

            // The ladder itself.
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Faster")
                        .font(typography.sans(11, weight: .medium))
                        .foregroundStyle(ClaudePalette.tertiaryInk)
                    Spacer()
                    Text("Smarter")
                        .font(typography.sans(11, weight: .medium))
                        .foregroundStyle(ClaudePalette.secondaryInk)
                }
                GeometryReader { geometry in
                    let count = options.count
                    let inset: CGFloat = 26
                    let trackWidth = max(1, geometry.size.width - inset * 2)
                    let selectedIndex = options.firstIndex(where: { $0.id == selectedId })
                    ZStack(alignment: .leading) {
                        // The bare track.
                        Capsule()
                            .fill(ClaudePalette.adaptive(light: 0.90, dark: 0.24))
                            .frame(height: 3)
                            .padding(.horizontal, inset)
                        // The accent fill, up to the current rung.
                        if let selectedIndex {
                            Capsule()
                                .fill(ClaudePalette.orange)
                                .frame(width: trackWidth * CGFloat(selectedIndex) / CGFloat(max(count - 1, 1)), height: 3)
                                .padding(.leading, inset)
                        }
                        // The rungs, placed on the same grid as the track and fill.
                        ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                            rung(index: index, option: option, selectedIndex: selectedIndex, total: count)
                                .offset(
                                    x: inset + trackWidth * CGFloat(index) / CGFloat(max(count - 1, 1)) - 22
                                )
                        }
                    }
                }
                .frame(height: 56)
            }
        }
    }

    private func rung(index: Int, option: ProviderThinkingOption, selectedIndex: Int?, total: Int) -> some View {
        let isCurrent = selectedIndex == index
        let reached = selectedIndex.map { index <= $0 } ?? false
        return VStack(spacing: 4) {
            Button {
                Haptics.selection()
                onSelect(option.id)
            } label: {
                Circle()
                    .fill(isCurrent ? ClaudePalette.orange : (reached ? ClaudePalette.orange.opacity(0.55) : ClaudePalette.adaptive(light: 0.80, dark: 0.35)))
                    .frame(width: isCurrent ? 16 : 10, height: isCurrent ? 16 : 10)
                    .frame(width: 44, height: 24)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(option.label), effort level \(index + 1) of \(total)")
            .accessibilityAddTraits(isCurrent ? [.isSelected] : [])
            Text(option.label)
                .font(typography.mono(9))
                .foregroundStyle(isCurrent ? ClaudePalette.ink : ClaudePalette.tertiaryInk)
                .lineLimit(1)
        }
        .frame(width: 44)
    }
}
#endif
