/// Decides whether a disabled event tap is turned back on, giving up only on repeats close in time.
enum TapDisableWindow {
    /// How close two disables must be to count as the same fault, so sleep and wake do not add up.
    static let windowNanoseconds: UInt64 = 60 * 1_000_000_000

    /// How many disables within the window are tolerated before the tap is left off.
    static let limit = 2

    /// The new repeat count and whether to re-enable, from the last disable and the current one.
    static func decide(last: UInt64, now: UInt64, count: Int) -> (count: Int, reEnable: Bool) {
        let within = last != 0 && now &- last < windowNanoseconds
        let next = within ? count + 1 : 1
        return (next, next < limit)
    }
}
