// Whether this Mac is online, from a path monitor.

import Foundation
import UttrflowUX
import Network

/// Whether this Mac has a route to the internet, from a path monitor; optimistic until the first report.
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

    /// A lock rather than an actor, because the sign-in page asks this synchronously while drawing.
    var isReachable: Bool {
        lock.withLock { latest }
    }

    private func set(_ reachable: Bool) {
        lock.withLock { latest = reachable }
    }
}
