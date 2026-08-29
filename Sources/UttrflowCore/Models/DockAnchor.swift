/// Where the floating button parks.
///
/// Lives here because it is both a saved preference and a thing on screen: the
/// settings store and the panel would otherwise each define their own.
public enum DockAnchor: String, Sendable, Equatable, CaseIterable, Codable {
    case bottomLeft
    case bottomCentre
    /// The corner least likely to hold something the user is reading. The default.
    case bottomRight
    /// Parked halfway up the right-hand edge; the button turns vertical there.
    case rightEdge
}
