// The measurements the quick panel is drawn to.

import SwiftUI

/// The measurements the approved design is drawn to.
enum QuickPanelMetrics {
    static let width: CGFloat = 420
    static let height: CGFloat = 560
    static let corner: CGFloat = 16
    static let controlHeight: CGFloat = 34
    /// The search field, taller than the microphone beside it so it leads the panel.
    static let searchHeight: CGFloat = 42
    /// The kind filters' segments and the collection chips beside them.
    static let segmentHeight: CGFloat = 22
    static let chipRowHeight: CGFloat = 28
    /// How far the aurora's band reaches and how much of it sits above the panel's top edge.
    static let auroraHeight: CGFloat = 260
    static let auroraRise: CGFloat = 150
    /// Every row the same height, so arrow-key counting stays right.
    static let rowHeight: CGFloat = 34
}
