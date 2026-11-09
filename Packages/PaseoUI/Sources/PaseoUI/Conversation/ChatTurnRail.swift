#if canImport(UIKit)
import Foundation
import PaseoStore
import SwiftUI

/// One prompt in the chat outline: the daemon's index entry, or a loaded turn in fallback.
struct ChatOutlineItem: Identifiable, Hashable {
    /// The prompt's timeline position (its user row's `seqStart`).
    let seq: Int
    /// What the rail's preview bubble and the sheet show.
    let preview: String
    var id: Int { seq }
}

/// U5: the prompt rail — the iPhone port of upstream's `ChatOutlineRail`
/// (`packages/app/src/agent-stream/chat-outline/rail.web.tsx`).
///
/// No plate, no material, no reserved margin: a column of tick marks hugging the trailing edge,
/// drawn over the transcript. Only the ticks are visible; the column itself is a 24 pt touch
/// strip that magnifies the slots around the finger and previews the prompt under it.
///
/// Dragging along it feels like an iOS picker wheel (the user's request): one selection tick per
/// slot crossing, prepared on touch-down, throttled on dense rails; releasing on a prompt jumps
/// there with one light impact; dragging off the rail gives nothing.
struct ChatOutlineRail: View {
    let items: [ChatOutlineItem]
    let activeSeq: Int?
    /// Height of the transcript viewport, for the slot math and the 80% column.
    let viewportHeight: CGFloat
    /// Shown while scrolling and briefly after; the touch strip is live only while it shows.
    let isRevealed: Bool
    let onJump: (Int) -> Void
    let onReveal: () -> Void

    /// Everything but the panel-width rule comes from `rail.web.tsx:13-22`. The strip is the touch
    /// target; the pills sit at its trailing edge (upstream grows them rightward from the left).
    static let stripWidth: CGFloat = 24
    static let slotHeight: CGFloat = 8
    static let restingPillHeight: CGFloat = 2
    static let magnifiedPillHeight: CGFloat = 4
    static let restingPillWidth: CGFloat = 10
    static let activePillWidth: CGFloat = 18
    static let magnifiedPillWidth: CGFloat = 26
    static let previewWidth: CGFloat = 260
    static let previewHeight: CGFloat = 48
    static let previewGap: CGFloat = 4
    /// Upstream shows the rail for two prompts; the sheet's "Jump to message" uses four, and a
    /// rail for three messages is noise (UX spec §4.3).
    static let minimumPrompts = 4
    /// Upstream's `OUTLINE_MAGNIFY_RADIUS` (`chat-outline/model.ts:13`).
    static let magnifyRadius = 3
    /// Dense rails tick at most this often, so a fast drag stays crisp instead of buzzing.
    static let tickInterval: TimeInterval = 0.035

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hoveredIndex: Int?
    @State private var isTouching = false
    @State private var lastTickAt: Date?

    private let typography = ClaudeTypography()

    /// Upstream slots tile the rail with no gaps and shrink when they don't fit
    /// (`rail.web.tsx:204-212`): `flexBasis: 8`, `flexShrink: 1` over an 80% column.
    private var slot: CGFloat {
        guard !items.isEmpty else { return Self.slotHeight }
        return min(Self.slotHeight, max(1, viewportHeight * 0.8 / CGFloat(items.count)))
    }

    private var railHeight: CGFloat { slot * CGFloat(items.count) }

    var body: some View {
        rail
    }

    private var rail: some View {
        ZStack(alignment: .topTrailing) {
            slots
            if let index = hoveredIndex, items.indices.contains(index) {
                previewBubble(items[index].preview)
                    .offset(x: -(Self.stripWidth + Self.previewGap), y: previewOffset(index))
            }
        }
        .frame(width: Self.stripWidth, height: railHeight)
        // The touch strip is exactly the tick column; the trailing padding only insets it from
        // the screen edge, so the transcript keeps the rest.
        .contentShape(.rect)
        .padding(.trailing, 8)
        .opacity(isRevealed || isTouching ? 1 : 0)
        // Hidden, the strip gives the edge back to scrolling (a right thumb lives there); it is
        // live whenever the ticks show, like grabbing the system scroll indicator.
        .allowsHitTesting(isRevealed || isTouching)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: isRevealed)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hoveredIndex)
        .gesture(scrub)
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("transcript.turnRail")
        .accessibilityLabel("Jump to message")
        .accessibilityValue(accessibilityPosition)
    }

    private var slots: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                slotView(index: index, item: item)
            }
        }
        .frame(width: Self.stripWidth, height: railHeight)
    }

    private func slotView(index: Int, item: ChatOutlineItem) -> some View {
        let magnification: CGFloat =
            reduceMotion ? 0 : (hoveredIndex.map { Self.promptMagnification(index - $0) } ?? 0)
        let isActive = item.seq == activeSeq
        let restingWidth = isActive ? Self.activePillWidth : Self.restingPillWidth
        let width = restingWidth + magnification * (Self.magnifiedPillWidth - restingWidth)
        let height =
            Self.restingPillHeight
            + magnification * (Self.magnifiedPillHeight - Self.restingPillHeight)
        return HStack(spacing: 0) {
            Spacer(minLength: 0)
            Capsule(style: .continuous)
                .fill(magnification > 0 || isActive ? ClaudePalette.ink : ClaudePalette.tertiaryInk)
                .frame(width: width, height: height)
        }
        .frame(width: Self.stripWidth, height: slot)
    }

    private func previewBubble(_ text: String) -> some View {
        Text(text)
            .font(typography.sans(13))
            .foregroundStyle(ClaudePalette.ink)
            .lineLimit(2)
            .truncationMode(.tail)
            .padding(.horizontal, 12)
            .frame(width: Self.previewWidth, height: Self.previewHeight, alignment: .leading)
            .background(.ultraThinMaterial, in: .rect(cornerRadius: 12))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func previewOffset(_ index: Int) -> CGFloat {
        (CGFloat(index) + 0.5) * slot - Self.previewHeight / 2
    }

    // MARK: Gesture

    /// The picker wheel. `minimumDistance: 0` so touch-down already picks a slot; a finger that
    /// wanders left of the strip or past either end cancels, and release there does nothing.
    private var scrub: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                if !isTouching {
                    isTouching = true
                    onReveal()
                    Haptics.prepare()
                    hoveredIndex = nil
                    lastTickAt = nil
                }
                updateHover(at: value.location)
            }
            .onEnded { value in
                let index = slotIndex(at: value.location)
                isTouching = false
                hoveredIndex = nil
                lastTickAt = nil
                guard let index else { return }
                Haptics.light()
                onJump(items[index].seq)
            }
    }

    private func updateHover(at point: CGPoint) {
        guard let index = slotIndex(at: point) else {
            if hoveredIndex != nil { hoveredIndex = nil }
            return
        }
        guard hoveredIndex != index else { return }
        hoveredIndex = index
        tick()
    }

    /// Zero-based slot under a point, or nil when the finger left the strip. The strip tolerates
    /// straying a little past its ends (upstream's hover leaves only outside the rail); past that
    /// it is a cancel.
    private func slotIndex(at point: CGPoint) -> Int? {
        guard !items.isEmpty else { return nil }
        guard point.y >= -12, point.y <= railHeight + 12 else { return nil }
        guard point.x >= -Self.stripWidth / 2 else { return nil }
        let clamped = min(max(point.y, 0), railHeight - 0.001)
        let index = Int(clamped / slot)
        return min(max(index, 0), items.count - 1)
    }

    private func tick() {
        let now = Date()
        // Dense rails (slots under ~6 pt) would buzz; sparse ones tick on every crossing.
        if slot < 6, let lastTickAt, now.timeIntervalSince(lastTickAt) < Self.tickInterval { return }
        lastTickAt = now
        Haptics.selection()
    }

    private var accessibilityPosition: String {
        guard let index = items.firstIndex(where: { $0.seq == activeSeq }) else {
            return "\(items.count)"
        }
        return "\(index + 1) of \(items.count)"
    }

    // MARK: Pure math (upstream `chat-outline/model.ts:13-27`)

    /// Dock-style falloff: 1 under the finger, easing to 0 at the radius. The raised cosine has
    /// no corner at either end, so sweeping reads as one bulge travelling with the finger.
    static func promptMagnification(_ slotDistance: Int) -> CGFloat {
        let distance = abs(slotDistance)
        guard distance < magnifyRadius else { return 0 }
        let radius = Double(magnifyRadius)
        return CGFloat((1 + cos(Double.pi * Double(distance) / radius)) / 2)
    }
}

/// U5: "Jump to message" — the chat outline's prompts, every one of them.
///
/// The list is the daemon's index for the whole conversation (UX spec §4.3), so opening the sheet
/// never pages history in: choosing an unloaded prompt fetches just its window.
struct ChatTurnNavSheet: View {
    let store: ConversationStore
    let items: [ChatOutlineItem]
    let activeSeq: Int?
    let onJump: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    private let typography = ClaudeTypography()

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Jump to message", close: { dismiss() })
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        row(index: index, item: item)
                        if item.id != items.last?.id {
                            ClaudeDivider().padding(.leading, 56)
                        }
                    }
                    if store.promptOutline.isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .accessibilityLabel("Loading earlier messages")
                    }
                }
                .padding(.vertical, 4)
            }
            .background(ClaudePalette.background)
        }
        .presentationDetents([.medium, .large])
        .task { store.promptOutline.refresh(timelineEpoch: store.timeline.epoch) }
    }

    private func row(index: Int, item: ChatOutlineItem) -> some View {
        let isCurrent = item.seq == activeSeq
        return Button {
            Haptics.selection()
            onJump(item.seq)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                Text(PaseoFormat.integer(index + 1))
                    .font(typography.mono(12, weight: isCurrent ? .semibold : .regular))
                    .foregroundStyle(isCurrent ? ClaudePalette.ink : ClaudePalette.secondaryInk)
                    .frame(width: 32, height: 32)
                    .background(isCurrent ? ClaudePalette.ink.opacity(0.10) : .clear, in: .circle)
                Text(item.preview)
                    .font(typography.sans(14))
                    .foregroundStyle(isCurrent ? ClaudePalette.ink : ClaudePalette.secondaryInk)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 8)
                if isCurrent {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(ClaudePalette.ink)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 48)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("turnNav.\(index + 1)")
        .accessibilityLabel(isCurrent ? "Message \(index + 1), current" : "Jump to message \(index + 1)")
    }
}
#endif
