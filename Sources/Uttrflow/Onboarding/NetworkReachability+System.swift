import Foundation
import UttrflowUX
import Network

/// Whether this Mac has a route to the internet, as the sign-in page asks it.
///
/// A monitor rather than a reachability test against a host: the question is only ever
/// "is it worth drawing the buttons live", and answering it by pinging somebody would
/// mean a network request to decide whether to make a network request.
///
/// It starts optimistic. The first path report arrives a moment after the monitor does,
/// and being briefly wrong in the direction of "try it" costs the user one failed
/// attempt that lands on the offline page anyway — whereas being briefly wrong the other
/// way greys out three buttons on a Mac that is perfectly online.
final class SystemNetworkReachability: NetworkReachability, @unchecked Sendable {
    private let monitor = NWPathMonitor()
    private let lock = NSLock()
    private var latest = true

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            self?.set(path.status == .satisfied)
        }
        monitor.start(queue: DispatchQueue(label: "com.uttrflow.reachability"))
    }

    deinit {
        monitor.cancel()
    }

    /// `@unchecked Sendable` with a lock rather than an actor, because the sign-in page
    /// asks this synchronously while deciding what to draw, and a question answered from
    /// a stored boolean has nothing to suspend for.
    var isReachable: Bool {
        lock.withLock { latest }
    }

    private func set(_ reachable: Bool) {
        lock.withLock { latest = reachable }
    }
}
