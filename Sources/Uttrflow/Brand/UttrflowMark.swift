import SwiftUI

/// The Uttrflow mark: a lowercase *u* with deliberately uneven stems, a letter and a
/// waveform at once.
///
/// Drawn rather than loaded. The mark is one round-capped stroke on a 100×100 grid, so a
/// path costs less than a raster at every size and stays exact at all of them — and the
/// stem tops are parameters, which is what lets a caller animate them.
///
/// The same geometry ships in the identity kit as `svg/mark/` and `code/tokens.json`;
/// change it in one place and re-export, rather than editing either copy by hand.
struct UttrflowMark: Shape {
    /// Where the short left stem starts, on the grid. Smaller is taller.
    var leftTop: CGFloat = 37
    /// Where the tall right stem starts.
    var rightTop: CGFloat = 21

    /// The drawn bounds on the grid — not the full 100×100, which the mark does not fill.
    static let gridBox = CGRect(x: 19, y: 14, width: 62, height: 72)
    static let aspectRatio: CGFloat = 62.0 / 72.0
    /// Stroke weight on the grid, so a rendered size can derive its own.
    static let strokeUnits: CGFloat = 14

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(leftTop, rightTop) }
        set {
            leftTop = newValue.first
            rightTop = newValue.second
        }
    }

    /// The stroke width that pairs with a given rendered height.
    static func lineWidth(forHeight height: CGFloat) -> CGFloat {
        height / gridBox.height * strokeUnits
    }

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width / Self.gridBox.width, rect.height / Self.gridBox.height)
        let originX = rect.midX - Self.gridBox.midX * scale
        let originY = rect.midY - Self.gridBox.midY * scale
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: originX + x * scale, y: originY + y * scale)
        }

        var path = Path()
        path.move(to: point(26, leftTop))
        path.addLine(to: point(26, 55))
        path.addArc(
            center: point(50, 55), radius: 24 * scale,
            startAngle: .degrees(180), endAngle: .degrees(0), clockwise: true)
        path.addLine(to: point(74, rightTop))
        return path
    }
}
