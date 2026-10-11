// Resizing the quick panel by its border: which edge the pointer is on, and the frame a drag makes.
public import Foundation

/// Which part of the panel's border the pointer is on; eight, since a corner drags both dimensions.
public enum PanelEdge: Sendable, Equatable, CaseIterable {
    /// The four sides.
    case left, right, top, bottom
    /// The four corners.
    case topLeft, topRight, bottomLeft, bottomRight

    /// Whether dragging this edge moves the origin: AppKit's is bottom-left, so growing left or down does.
    var movesOrigin: (x: Bool, y: Bool) { (sign.width < 0, sign.height < 0) }

    /// Whether dragging this edge changes the width.
    var changesWidth: Bool { sign.width != 0 }

    /// Whether dragging this edge changes the height.
    var changesHeight: Bool { sign.height != 0 }

    /// Which way the width grows when the pointer moves in +x, and the height in +y.
    var sign: (width: CGFloat, height: CGFloat) {
        switch self {
        case .left: (-1, 0)
        case .right: (1, 0)
        case .top: (0, 1)
        case .bottom: (0, -1)
        case .topLeft: (-1, 1)
        case .topRight: (1, 1)
        case .bottomLeft: (-1, -1)
        case .bottomRight: (1, -1)
        }
    }
}

/// The arithmetic of dragging the panel's edge, in AppKit coordinates. See Docs/ux-panel-geometry.md.
public enum PanelResize {
    /// How far inside the border counts as being on it; six points, see Docs/ux-panel-geometry.md.
    public static let grip: CGFloat = 6

    /// The smallest the panel may be dragged, set by the sheet card's width and two rows of list.
    public static let minimum = CGSize(width: 380, height: 300)

    /// Which edge a point in the view's coordinates is on; `isFlipped` says whether `y` grows downwards.
    public static func edge(
        at point: CGPoint, in size: CGSize, grip: CGFloat = grip, isFlipped: Bool = false
    ) -> PanelEdge? {
        // Outside the panel is not an edge; claiming it would let a click aimed elsewhere resize this.
        guard point.x >= 0, point.y >= 0, point.x <= size.width, point.y <= size.height else {
            return nil
        }
        // Everything below is in AppKit's coordinates, so the flip is undone once, here.
        let y = isFlipped ? size.height - point.y : point.y
        let left = point.x <= grip
        let right = point.x >= size.width - grip
        let bottom = y <= grip
        let top = y >= size.height - grip

        switch (left, right, top, bottom) {
        // A panel narrower than two grips reports both sides; left wins so the answer is stable.
        case (true, _, true, _): return .topLeft
        case (true, _, _, true): return .bottomLeft
        case (_, true, true, _): return .topRight
        case (_, true, _, true): return .bottomRight
        case (true, _, _, _): return .left
        case (_, true, _, _): return .right
        case (_, _, true, _): return .top
        case (_, _, _, true): return .bottom
        default: return nil
        }
    }

    /// The eight bands of border, corners last so they win the overlap; shared with the hit test.
    public static func borders(
        in size: CGSize, grip: CGFloat = grip, isFlipped: Bool = false
    ) -> [(rect: CGRect, edge: PanelEdge)] {
        let (width, height) = (size.width, size.height)
        let upright: [(rect: CGRect, edge: PanelEdge)] = [
            (CGRect(x: 0, y: grip, width: grip, height: height - 2 * grip), .left),
            (CGRect(x: width - grip, y: grip, width: grip, height: height - 2 * grip), .right),
            (CGRect(x: grip, y: 0, width: width - 2 * grip, height: grip), .bottom),
            (CGRect(x: grip, y: height - grip, width: width - 2 * grip, height: grip), .top),
            (CGRect(x: 0, y: 0, width: grip, height: grip), .bottomLeft),
            (CGRect(x: width - grip, y: 0, width: grip, height: grip), .bottomRight),
            (CGRect(x: 0, y: height - grip, width: grip, height: grip), .topLeft),
            (CGRect(x: width - grip, y: height - grip, width: grip, height: grip), .topRight),
        ]
        guard isFlipped else { return upright }
        return upright.map { band in
            (
                rect: CGRect(
                    x: band.rect.minX, y: height - band.rect.maxY,
                    width: band.rect.width, height: band.rect.height),
                edge: band.edge
            )
        }
    }

    /// The frame a drag has arrived at, measured from where the drag started so clamping does not trail.
    public static func resized(
        _ frame: CGRect, dragging edge: PanelEdge, by delta: CGSize,
        minimum: CGSize = minimum, within visible: CGRect? = nil
    ) -> CGRect {
        let sign = edge.sign
        let width =
            edge.changesWidth
            ? max(frame.width + sign.width * delta.width, minimum.width) : frame.width
        let height =
            edge.changesHeight
            ? max(frame.height + sign.height * delta.height, minimum.height) : frame.height

        // The edge opposite the one being dragged does not move, so a resize feels like pulling the border.
        let moves = edge.movesOrigin
        let origin = CGPoint(
            x: moves.x ? frame.maxX - width : frame.minX,
            y: moves.y ? frame.maxY - height : frame.minY)

        return held(
            CGRect(origin: origin, size: CGSize(width: width, height: height)),
            dragging: edge, within: visible)
    }

    /// Fits a resized frame on the usable screen while preserving the opposite edges when possible.
    private static func held(
        _ frame: CGRect, dragging edge: PanelEdge, within visible: CGRect?
    ) -> CGRect {
        guard let visible else { return frame }
        let right = min(max(frame.maxX, visible.minX), visible.maxX)
        let top = min(max(frame.maxY, visible.minY), visible.maxY)
        let left = min(max(frame.minX, visible.minX), visible.maxX)
        let bottom = min(max(frame.minY, visible.minY), visible.maxY)
        let width = min(frame.width, edge.movesOrigin.x ? right - visible.minX : visible.maxX - left)
        let height =
            min(frame.height, edge.movesOrigin.y ? top - visible.minY : visible.maxY - bottom)
        let x = edge.movesOrigin.x ? right - width : left
        let y = edge.movesOrigin.y ? top - height : bottom

        return CGRect(x: x, y: y, width: width, height: height)
    }
}
