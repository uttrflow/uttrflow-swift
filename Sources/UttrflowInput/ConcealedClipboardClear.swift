/// Clears a secret from the clipboard after a delay, and only if nothing else has been copied since.
public struct ConcealedClipboardClear: Sendable {
    /// Waits for the delay; replaced in tests so no test sleeps.
    private let sleep: @Sendable (Duration) async throws -> Void

    /// The sleeper defaults to the real clock.
    public init(
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.sleep = sleep
    }

    /// Seconds a secret stays on the clipboard unless the person chooses otherwise.
    public static let defaultSeconds = 60

    /// Schedules the clear for one write; `nil` when off or the write's generation is unknown.
    @discardableResult
    public func schedule(
        on pasteboard: any Pasteboard, writtenAt changeCount: Int?, afterSeconds seconds: Int
    ) -> Task<Bool, Never>? {
        guard seconds > 0, let changeCount else { return nil }
        let sleep = sleep
        return Task.detached {
            do { try await sleep(.seconds(seconds)) } catch { return false }
            return pasteboard.discardContents(ifUnchangedSince: changeCount)
        }
    }
}
