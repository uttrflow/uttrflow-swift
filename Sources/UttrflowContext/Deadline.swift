/// Holds an answer to a time, so a read into another application can never hold the loop.
public enum Deadline {
    /// The work's answer if it arrives within the allowance, else nothing, the work left to finish on its own.
    public static func first<Answer: Sendable>(
        withinMilliseconds allowance: Int, of work: @escaping @Sendable () async -> Answer?
    ) async -> Answer? {
        await withTaskGroup(of: Answer?.self, returning: Answer?.self) { group in
            group.addTask { await work() }
            group.addTask {
                try? await Task.sleep(for: .milliseconds(max(allowance, 1)))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}
