#if canImport(UIKit)
import QuartzCore

/// The app runs at the display's full rate (120 Hz on ProMotion iPhones). `Info.plist` opts in
/// (`CADisableMinimumFrameDurationOnPhone`); every display link we own asks for the same range here
/// so none of them is left at the system's default. Apple: "Optimizing ProMotion refresh rates for
/// iPhone 13 Pro and iPad Pro" (developer.apple.com/documentation/quartzcore/optimizing-promotion-refresh-rates-for-iphone-13-pro-and-ipad-pro).
enum FrameRate {
    /// 80-120 Hz, preferring 120: the stack never settles for a lower tier while we animate.
    static let promotion = CAFrameRateRange(minimum: 80, maximum: 120, preferred: 120)
}
#endif
