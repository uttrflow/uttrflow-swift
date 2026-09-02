/// Says how long a dictation has left, the way somebody reading it in a hurry needs it.
public enum RemainingTime: Sendable {
    /// The countdown shown while a recording approaches its cap, or `nil` when it is not.
    public static func phrase(for advice: DictationAdvice) -> String? {
        guard case .approaching(let remaining) = advice else { return nil }
        let seconds = Int(remaining.components.seconds)
        guard seconds > 0 else { return "seconds left" }
        if seconds >= 60 {
            let minutes = (seconds + 59) / 60
            return "\(minutes) min left"
        }
        // Rounded up to ten, because a figure ticking every second reads as an alarm.
        return "\(Swift.max(10, (seconds + 9) / 10 * 10)) sec left"
    }
}
