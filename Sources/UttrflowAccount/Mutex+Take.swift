internal import Synchronization

extension Mutex where Value: Sendable {
    /// Returns what `keyPath` holds and leaves `nil` in its place, as one locked step.
    func take<Taken: Sendable>(_ keyPath: WritableKeyPath<Value, Taken?>) -> Taken? {
        withLock { state in
            defer { state[keyPath: keyPath] = nil }
            return state[keyPath: keyPath]
        }
    }
}
