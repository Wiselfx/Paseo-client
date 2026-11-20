#if canImport(UIKit)
import SwiftUI
import UIKit

/// One drawer surface: the display's corner shape, its own canvas, a hairline that fades with
/// progress, and the shadow that gives it depth (R5 §2, E2 §1). The clipping lives on
/// `contentView`, so the card's own layer can cast a shadow without `masksToBounds`.
@MainActor
final class ShellCardView: UIView {
    /// The card's rounded, clipping content. Hosting views go here; the card itself is only the
    /// shadow-carrying container.
    let contentView = UIView()

    private let hairline = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerRadius = EdgeDrawer.cornerRadius
        layer.cornerCurve = .continuous
        layer.masksToBounds = false
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowRadius = EdgeDrawer.shadowRadius
        layer.shadowOffset = EdgeDrawer.leadingShadowOffset
        layer.shadowOpacity = 0

        contentView.layer.cornerRadius = EdgeDrawer.cornerRadius
        contentView.layer.cornerCurve = .continuous
        contentView.layer.masksToBounds = true
        addSubview(contentView)

        hairline.fillColor = nil
        hairline.lineWidth = 0.5
        hairline.opacity = 0
        contentView.layer.addSublayer(hairline)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    var hairlineOpacity: Float {
        get { hairline.opacity }
        set { hairline.opacity = newValue }
    }

    /// Written per frame by the container while a finger or a settle drives the surface.
    var shadowOpacity: Float {
        get { layer.shadowOpacity }
        set { layer.shadowOpacity = newValue }
    }

    func applyColors(in traits: UITraitCollection) {
        // Resolved against the card's own traits: a layer's `cgColor` is a snapshot, so dark and
        // pure black are read again on every trait change.
        contentView.backgroundColor = UIColor(Palette.background).resolvedColor(with: traits)
        hairline.strokeColor = UIColor(Palette.ink)
            .withAlphaComponent(0.1)
            .resolvedColor(with: traits)
            .cgColor
    }

    /// Called from `ShellContainerController.viewDidLayoutSubviews` only: an explicit path keeps
    /// the shadow off the per-frame offscreen render.
    func updateShadowPath() {
        guard bounds.width > 0, bounds.height > 0 else { return }
        layer.shadowPath = Path(
            roundedRect: bounds, cornerRadius: EdgeDrawer.cornerRadius, style: .continuous
        ).cgPath
    }

    func updateHairlinePath() {
        let inset = contentView.bounds.insetBy(dx: 0.25, dy: 0.25)
        guard inset.width > 0, inset.height > 0 else { return }
        hairline.path = Path(
            roundedRect: inset, cornerRadius: EdgeDrawer.cornerRadius, style: .continuous
        ).cgPath
    }
}
#endif
