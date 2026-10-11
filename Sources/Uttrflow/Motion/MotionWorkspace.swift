// What the motion budget reads of the system workspace, behind a seam a test can fake.

import AppKit

/// The Reduce Motion setting and the centre that announces its change.
@MainActor
protocol MotionWorkspace {
    var reducesMotion: Bool { get }
    var notificationCenter: NotificationCenter { get }
}

/// The shared workspace of this Mac.
@MainActor
struct SystemWorkspace: MotionWorkspace {
    var reducesMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    var notificationCenter: NotificationCenter { NSWorkspace.shared.notificationCenter }
}
