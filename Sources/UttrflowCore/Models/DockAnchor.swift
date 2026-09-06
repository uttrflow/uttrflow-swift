/// Where the floating button parks; in Core because the settings store and the panel both need it.
public enum DockAnchor: String, Sendable, Equatable, CaseIterable, Codable {
    /// The bottom-left corner.
    case bottomLeft
    /// Centred along the bottom edge.
    case bottomCentre
    /// The corner least likely to hold something the user is reading. The default.
    case bottomRight
    /// Parked halfway up the right-hand edge; the button turns vertical there.
    case rightEdge
}
