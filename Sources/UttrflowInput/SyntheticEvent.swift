public import CoreGraphics

/// The mark this app stamps on every key event it posts, so its own tap and monitor ignore its own typing.
public enum SyntheticEvent {
    /// A value no ordinary event carries, kept out of zero so an untagged event is never mistaken for ours.
    public static let sentinel: Int64 = 0x5554_5246_4C4F_5721

    /// Stamps an event as this app's own, before it is posted.
    public static func tag(_ event: CGEvent) {
        event.setIntegerValueField(.eventSourceUserData, value: sentinel)
    }

    /// Whether this event is one this app posted, which its own tap and monitor must never act on.
    public static func isOurs(_ event: CGEvent) -> Bool {
        event.getIntegerValueField(.eventSourceUserData) == sentinel
    }
}
