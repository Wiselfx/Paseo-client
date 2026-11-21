#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// The drawing surface: one `CAShapeLayer`, one display link, a snapshot of the ring per tick.
///
/// 30 Hz is enough for a mic meter and a third of the cost of 90/120 Hz. The path is replaced
/// rather than animated (the implicit animation is disabled), so a tick is a snapshot + a path
/// build, no allocation of backing stores.
final class WaveformMeterView: UIView {
    override class var layerClass: AnyClass { CAShapeLayer.self }

    private var link: CADisplayLink?
    private var tickTarget: WaveformTickTarget?
    private var buffer: LiveWaveformBuffer?
    private var isActive = false
    private var rowBarCount: Int?
    private var barWidth: CGFloat = ComposerMetrics.waveformBarWidth
    private var barGap: CGFloat = ComposerMetrics.waveformBarGap
    private var maxBarHeight: CGFloat = ComposerMetrics.waveformHeight
    private var reduceMotion = false
    private var accessibilityText: String?
    private var resolvedBarCount = 1
    /// The last frame we drew, so a 120 Hz display still draws 30 times a second.
    private var lastDraw: CFTimeInterval = 0
    private var lastAccessibilityUpdate: CFTimeInterval = 0

    private static let tickInterval = 1.0 / 120.0

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        isUserInteractionEnabled = false
        clipsToBounds = true
        contentMode = .redraw
        isAccessibilityElement = false
    }

    required init?(coder: NSCoder) {
        return nil
    }

    // MARK: Inputs (from `updateUIView`)

    func apply(
        buffer: LiveWaveformBuffer, isActive: Bool, barCount: Int?, barWidth: CGFloat,
        barGap: CGFloat, maxBarHeight: CGFloat, tint: UIColor, reduceMotion: Bool,
        accessibilityText: String?
    ) {
        let changedShape =
            self.buffer !== buffer || self.rowBarCount != barCount
            || self.barWidth != barWidth || self.barGap != barGap
            || self.maxBarHeight != maxBarHeight || self.reduceMotion != reduceMotion
        self.buffer = buffer
        self.rowBarCount = barCount
        self.barWidth = barWidth
        self.barGap = barGap
        self.maxBarHeight = maxBarHeight
        self.reduceMotion = reduceMotion
        self.accessibilityText = accessibilityText
        if let shape = layer as? CAShapeLayer {
            shape.fillColor = tint.cgColor
            shape.strokeColor = nil
        }
        isAccessibilityElement = accessibilityText != nil
        accessibilityLabel = accessibilityText
        accessibilityTraits = .updatesFrequently
        if changedShape { recomputeBarCount() }
        self.isActive = isActive
        if isActive {
            start()
        } else {
            stop()
        }
        draw(at: Date.now.timeIntervalSince1970)
    }

    // MARK: Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        recomputeBarCount()
        draw(at: Date.now.timeIntervalSince1970)
    }

    /// Slot count for the width we were given: once per layout, never per tick.
    private func recomputeBarCount() {
        let count: Int
        if let rowBarCount {
            count = max(rowBarCount, 1)
        } else {
            let step = barWidth + barGap
            count = step > 0 && bounds.width > 0
                ? max(1, Int((bounds.width + barGap) / step))
                : 1
        }
        resolvedBarCount = count
    }

    // MARK: Display link

    private func start() {
        guard link == nil else {
            link?.isPaused = false
            return
        }
        let target = WaveformTickTarget(view: self)
        let link = CADisplayLink(target: target, selector: #selector(WaveformTickTarget.tick(_:)))
        // The whole app runs at 120 Hz (`FrameRate`); the waveform draws every frame too.
        link.preferredFrameRateRange = FrameRate.promotion
        link.add(to: .main, forMode: .common)
        self.tickTarget = target
        self.link = link
    }

    func stop() {
        link?.invalidate()
        link = nil
        tickTarget = nil
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        // A meter that left the hierarchy must not keep ticking (and a display link retains its
        // target, so nothing else would ever stop it).
        if window == nil { stop() } else if isActive { start() }
    }

    func tick(_ link: CADisplayLink) {
        let now = Date.now.timeIntervalSince1970
        // Wall-clock instants, not `link.timestamp`: the audio thread stamps pushes with the
        // same clock, and the two must agree for the scroll progress to mean anything.
        guard lastDraw == 0 || now - lastDraw >= Self.tickInterval * 0.5 else { return }
        lastDraw = now
        draw(at: now)
    }

    // MARK: Drawing

    private func draw(at now: TimeInterval) {
        guard let shape = layer as? CAShapeLayer else { return }
        guard let buffer, bounds.width > 0, bounds.height > 0 else {
            setPath(nil, on: shape)
            return
        }
        let snapshot = buffer.snapshot(count: resolvedBarCount, at: now)
        guard !snapshot.levels.isEmpty else {
            setPath(nil, on: shape)
            return
        }
        let path = UIBezierPath()
        if reduceMotion {
            // No lateral motion: one bar whose height follows the level, centred.
            let height = barHeight(snapshot.levels[snapshot.levels.count - 1])
            let rect = CGRect(
                x: (bounds.width - barWidth) / 2, y: (bounds.height - height) / 2,
                width: barWidth, height: height)
            path.append(UIBezierPath(roundedRect: rect, cornerRadius: barWidth / 2))
        } else {
            let step = barWidth + barGap
            for (index, level) in snapshot.levels.enumerated() {
                // Newest at the trailing edge, each older bar one slot further left, and every
                // bar keeps moving left as its own age grows — so the row scrolls smoothly at
                // the display's cadence, whatever rate the capture source publishes at.
                let x = bounds.width - barWidth - CGFloat(snapshot.slots[index]) * step
                guard x + barWidth > 0, x < bounds.width else { continue }
                let height = barHeight(level)
                let rect = CGRect(
                    x: x, y: (bounds.height - height) / 2, width: barWidth, height: height)
                path.append(UIBezierPath(roundedRect: rect, cornerRadius: barWidth / 2))
            }
        }
        setPath(path.cgPath, on: shape)
        updateAccessibilityValue(level: snapshot.levels[snapshot.levels.count - 1])
    }

    /// 3 pt is the floor: a silent row is a row of dots, never nothing.
    private func barHeight(_ level: Float) -> CGFloat {
        max(barWidth, CGFloat(level) * maxBarHeight)
    }

    /// `CAShapeLayer.path` is animatable; the meter is not. Disable the implicit transaction so a
    /// tick replaces the row instead of easing towards it.
    private func setPath(_ path: CGPath?, on shape: CAShapeLayer) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shape.path = path
        CATransaction.commit()
    }

    /// Once a second, not per frame: VoiceOver reads the number on demand, and the accessibility
    /// tree is not rebuilt 30 times a second.
    private func updateAccessibilityValue(level: Float) {
        guard accessibilityText != nil else { return }
        let now = Date.now.timeIntervalSince1970
        guard lastAccessibilityUpdate == 0 || now - lastAccessibilityUpdate >= 1 else { return }
        lastAccessibilityUpdate = now
        accessibilityValue = "\(Int((Double(level) * 100).rounded())) percent"
    }
}
#endif
