import CoreGraphics

/// A frozen display frame at native pixel resolution. `frame` uses AppKit global points with a
/// bottom-left origin; `image` rows start at the top of that display.
struct DisplayShot {
    let screenID: CGDirectDisplayID
    let frame: CGRect
    let scale: CGFloat
    let image: CGImage
}
