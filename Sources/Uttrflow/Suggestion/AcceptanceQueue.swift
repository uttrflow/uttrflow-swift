import Foundation
import UttrflowPredict
import UttrflowPredictCapture

/// Serializes corpus writes away from the draw path, with a bounded queue that fails closed on overflow.
@MainActor
final class AcceptanceQueue {
    static let maximumPendingWrites = 128
    static let maximumPendingBytes = 512 * 1_024
    static let maximumWriteBytes = 64 * 1_024

    private struct Write {
        let bytes: Int
        let run: @Sendable () async -> Void
    }

    private var pending: [Write] = []
    private var worker: Task<Void, Never>?
    private var outstandingWrites = 0
    private var outstandingBytes = 0
    private var forgetCount = 0
    private var overflowPending = false
    private var requiresFreshBaseline = false
    private let abandonField: @Sendable () async -> Void

    init(abandonField: @escaping @Sendable () async -> Void = {}) {
        self.abandonField = abandonField
    }

    /// Queues `work` behind earlier writes and returns at once; saturated writes are dropped.
    @discardableResult
    func enqueue(_ work: @escaping @Sendable () async -> Void, estimatedBytes: Int = 256) -> Bool {
        guard forgetCount == 0 else { return false }
        guard admits(estimatedBytes) else {
            markOverflow()
            return false
        }
        append(Write(bytes: estimatedBytes, run: work))
        return true
    }

    /// Queues an ordered capture batch, restoring from overflow only at a fresh, safely marked baseline.
    @discardableResult
    func enqueueCapture(
        _ events: [CaptureEvent], in reading: FieldReading, using capture: CaptureSession
    ) -> Bool {
        guard forgetCount == 0, !events.isEmpty else { return false }
        let queuedEvents: [CaptureEvent]
        if requiresFreshBaseline {
            guard let baseline = safeBaseline(in: events) else { return false }
            queuedEvents = baseline
        } else {
            queuedEvents = events
        }
        let bytes = Self.estimatedBytes(for: queuedEvents, reading: reading)
        guard admits(bytes) else {
            markOverflow()
            return false
        }
        append(
            Write(bytes: bytes) {
                for event in queuedEvents { _ = try? await capture.handle(event, in: reading) }
            })
        if requiresFreshBaseline { requiresFreshBaseline = false }
        return true
    }

    /// Waits until every admitted write and any overflow reset has finished.
    func drained() async {
        while let worker { await worker.value }
    }

    /// Closes admission before waiting for earlier writes and their overflow reset.
    func beginForgetting() async {
        forgetCount += 1
        await drained()
    }

    /// Reopens admission after the corpus and in-memory copies have been cleared.
    func finishForgetting() {
        forgetCount = max(0, forgetCount - 1)
    }

    static func estimatedBytes(for events: [CaptureEvent], reading: FieldReading) -> Int {
        let metadata = [
            reading.bundleIdentifier, reading.role, reading.subrole, reading.identifier,
            reading.placeholder, reading.accessibilityDescription, reading.document,
            reading.windowTitle, reading.applicationName,
        ]
        let surface = reading.surface
        let surfaceMetadata = [
            surface?.bundleIdentifier, surface?.role, surface?.locator, surface?.scope,
        ]
        let eventText = events.compactMap { event -> String? in
            switch event {
            case .keystroke(let line, _): line
            case .typed(let text, _): text
            default: nil
            }
        }
        let metadataBytes = (metadata + surfaceMetadata).compactMap { $0 }
            .reduce(0) { $0 + $1.utf8.count }
        let eventBytes = eventText.reduce(0) { $0 + $1.utf8.count }
        return 256 + events.count * 128 + metadataBytes + eventBytes
    }

    static func estimatedBytes(
        for strings: [String?], itemCount: Int = 1, surface: Surface? = nil
    ) -> Int {
        let surfaceMetadata = [
            surface?.bundleIdentifier, surface?.role, surface?.locator, surface?.scope,
        ]
        let payloadBytes = (strings + surfaceMetadata).compactMap { $0 }
            .reduce(0) { $0 + $1.utf8.count }
        return 256 + itemCount * 128 + payloadBytes
    }

    private func admits(_ bytes: Int) -> Bool {
        bytes > 0 && bytes <= Self.maximumWriteBytes
            && outstandingWrites < Self.maximumPendingWrites
            && outstandingBytes <= Self.maximumPendingBytes - bytes
            && !overflowPending
    }

    private func append(_ write: Write) {
        pending.append(write)
        outstandingWrites += 1
        outstandingBytes += write.bytes
        startWorkerIfNeeded()
    }

    private func markOverflow() {
        overflowPending = true
        startWorkerIfNeeded()
    }

    private func startWorkerIfNeeded() {
        guard worker == nil else { return }
        worker = Task { await drainPendingWrites() }
    }

    private func drainPendingWrites() async {
        while true {
            if !pending.isEmpty {
                let next = pending.removeFirst()
                await next.run()
                outstandingWrites -= 1
                outstandingBytes -= next.bytes
                continue
            }
            guard overflowPending else { break }
            await abandonField()
            requiresFreshBaseline = true
            overflowPending = false
        }
        worker = nil
        if !pending.isEmpty || overflowPending { startWorkerIfNeeded() }
    }

    private func safeBaseline(in events: [CaptureEvent]) -> [CaptureEvent]? {
        guard
            let index = events.firstIndex(where: {
                guard case .keystroke(let line, _) = $0 else { return false }
                return line.isEmpty
            })
        else { return nil }
        return Array(events.dropFirst(index))
    }
}
