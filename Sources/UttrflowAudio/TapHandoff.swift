// The bounded queue that carries converted samples off the microphone tap's real-time thread.
private import Dispatch
private import Foundation
private import Synchronization

/// Hands samples from the tap to a consumer thread through preallocated storage. See Docs/audio-capture.md.
final class TapHandoff: @unchecked Sendable {
    /// Two seconds of canonical audio plus room for each block's length marker.
    static let defaultCapacity = 32_768

    private let capacity: Int
    /// Written only by the producer and read only by the consumer, ordered by the two counters below.
    private let ring: UnsafeMutablePointer<Float>
    /// Slots ever written, published with release so the consumer sees the samples before the count.
    private let written = Atomic<Int>(0)
    /// Slots ever read, published with release so the producer may reuse them.
    private let read = Atomic<Int>(0)
    /// Samples refused because the consumer fell a whole capacity behind, never queued or reordered.
    private let dropped = Atomic<Int>(0)
    private let stopping = Atomic<Bool>(false)
    private let wake = DispatchSemaphore(value: 0)
    private let finished = DispatchSemaphore(value: 0)
    private let deliver: @Sendable ([Float]) -> Void

    /// Starts the consumer thread, which calls `deliver` once per pushed block, in order.
    init(capacity: Int = TapHandoff.defaultCapacity, deliver: @escaping @Sendable ([Float]) -> Void) {
        self.capacity = capacity
        self.deliver = deliver
        ring = UnsafeMutablePointer<Float>.allocate(capacity: capacity)
        ring.initialize(repeating: 0, count: capacity)
        let thread = Thread { [self] in consume() }
        thread.name = "Uttrflow tap handoff"
        thread.qualityOfService = .userInitiated
        thread.start()
    }

    deinit { ring.deallocate() }

    /// Samples refused because the queue was full.
    var droppedSamples: Int { dropped.load(ordering: .relaxed) }

    /// Copies one block in and wakes the consumer; allocates nothing, takes no lock, and drops the block when full.
    @discardableResult
    func push(_ samples: UnsafeBufferPointer<Float>) -> Bool {
        push { part in part(samples) }
    }

    /// Copies the parts `fill` lends into one block, so a callback converted in chunks still arrives as one block.
    @discardableResult
    func push(_ fill: ((UnsafeBufferPointer<Float>) -> Void) -> Void) -> Bool {
        let head = written.load(ordering: .relaxed)
        let free = capacity - (head - read.load(ordering: .acquiring)) - 1
        var count = 0
        var refused = 0
        fill { part in
            guard refused == 0, count + part.count <= free else {
                refused += part.count
                return
            }
            copy(part, to: head + 1 + count)
            count += part.count
        }
        guard refused == 0 else {
            dropped.add(count + refused, ordering: .relaxed)
            return false
        }
        guard count > 0 else { return true }
        ring[head % capacity] = Float(bitPattern: UInt32(count))
        written.store(head + count + 1, ordering: .releasing)
        wake.signal()
        return true
    }

    /// Delivers everything already pushed, then stops the consumer thread and waits for it.
    func finish() {
        stopping.store(true, ordering: .releasing)
        wake.signal()
        finished.wait()
    }

    private func copy(_ samples: UnsafeBufferPointer<Float>, to slot: Int) {
        guard let base = samples.baseAddress else { return }
        let start = slot % capacity
        let first = Swift.min(samples.count, capacity - start)
        (ring + start).update(from: base, count: first)
        ring.update(from: base + first, count: samples.count - first)
    }

    private func consume() {
        while true {
            wake.wait()
            deliverPending()
            if stopping.load(ordering: .acquiring) {
                deliverPending()
                break
            }
        }
        finished.signal()
    }

    /// Delivers each whole block the producer has published, one call per block so the meter keeps its clock.
    private func deliverPending() {
        var tail = read.load(ordering: .relaxed)
        let head = written.load(ordering: .acquiring)
        while tail < head {
            let count = Int(ring[tail % capacity].bitPattern)
            var block = [Float](repeating: 0, count: count)
            block.withUnsafeMutableBufferPointer { into in
                for index in 0..<count { into[index] = ring[(tail + 1 + index) % capacity] }
            }
            tail += count + 1
            read.store(tail, ordering: .releasing)
            deliver(block)
        }
    }
}
