// The encrypted write path seals the one JSON encoding it records, rather than encoding the list again.

import CryptoKit
import Foundation
import Synchronization
import Testing

@testable import UttrflowClipboard
@testable import UttrflowCore

@Suite("Clipboard encrypted write encoding")
struct ClipboardWriteOptimizationTests {
    private struct Keys: StoreKeyProviding {
        let value = SymmetricKey(size: .bits256)
        func key(createIfMissing: Bool) throws -> SymmetricKey { value }
    }

    private func encryptedStore() -> EncryptedStore {
        EncryptedStore(keys: Keys())
    }

    @Test("an encrypted clipboard save records one JSON payload that opens to the saved clips")
    func encryptedSaveReusesEncodedPayload() async throws {
        let file = TemporaryFile()
        let encrypted = encryptedStore()
        let store = ClipboardStore(file: file.url, encryptedStore: encrypted)
        let subject = Clip(text: "encoded once", kind: .text, copiedAt: noon)
        let tally = StoreWriteTally()

        try await ClipboardStore.$writes.withValue(tally) {
            try await store.record(subject, keeping: week())
        }

        #expect(tally.count == 1)
        #expect(tally.written.count == 1)
        let envelope = try Data(contentsOf: file.url)
        #expect(try encrypted.open(envelope, for: file.url.lastPathComponent) == tally.written[0])
        let reopened = ClipboardStore(file: file.url, encryptedStore: encrypted)
        #expect(await reopened.clips(keeping: week()).map(\.id) == [subject.id])
    }

    @Test("after a failed encrypted write, the next save persists the complete history")
    func failedWriteIsRetried() async throws {
        let file = TemporaryFile()
        let attempts = Mutex(0)
        let encrypted = EncryptedStore(
            keys: Keys(),
            writeFile: { data, url in
                let attempt = attempts.withLock { count in
                    count += 1
                    return count
                }
                if attempt == 1 { throw CocoaError(.fileWriteUnknown) }
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: url, options: .atomic)
            })
        let store = ClipboardStore(file: file.url, encryptedStore: encrypted)
        let first = Clip(text: "first", kind: .text, copiedAt: noon)
        let second = Clip(text: "second", kind: .text, copiedAt: noon.addingTimeInterval(1))

        await #expect(throws: ClipboardStoreError.couldNotWrite) {
            try await store.record(first, keeping: week())
        }
        try await store.record(second, keeping: week())

        let reopened = ClipboardStore(file: file.url, encryptedStore: encrypted)
        #expect(await reopened.clips(keeping: week()).map(\.text) == ["second", "first"])
    }

    @Test("benchmark a new copy with five thousand encrypted history clips")
    func benchmarkFiveThousandClipSave() async throws {
        guard ProcessInfo.processInfo.environment["UTTRFLOW_CLIPBOARD_BENCHMARK"] == "1" else {
            return
        }

        func sample() async throws -> (
            noOpElapsed: Duration, noOpWrites: Int, elapsed: Duration, writes: Int, bytes: Int
        ) {
            let file = TemporaryFile()
            try FileManager.default.createDirectory(
                at: file.url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encrypted = encryptedStore()
            let seeded = (0..<5_000).map { index in
                Clip(
                    text: "item \(index) " + String(repeating: "synthetic clipboard payload ", count: 70),
                    kind: .text, copiedAt: noon.addingTimeInterval(-Double(index)),
                    lastUsedOrder: UInt64(5_000 - index))
            }
            try encrypted.write(ClipboardIndex(clips: seeded), to: file.url)
            #expect(try Data(contentsOf: file.url).count > 9_000_000)
            let budget = ClipboardBudget(
                ceiling: 20_000_000,
                copied: ClipboardTier(bytes: 12_000_000, items: 5_100, days: 100),
                dictation: ClipboardTier(bytes: 1_000_000, items: 100, days: 100),
                images: ClipboardTier(bytes: 1_000_000, items: 100, days: 100),
                largestClip: 100_000, largestPicture: 10_000_000,
                pictureEdge: 4_096, disk: 100_000_000)
            let retention = ClipRetention(days: 100, now: noon)
            let store = ClipboardStore(file: file.url, budget: budget, encryptedStore: encrypted)
            #expect(await store.clips(keeping: retention).count == 5_000)
            let noOpStart = ContinuousClock.now
            let noOpTally = StoreWriteTally()
            try await ClipboardStore.$writes.withValue(noOpTally) {
                try await store.setAlias(nil, of: seeded[4_999].id, keeping: retention)
            }
            let noOpElapsed = noOpStart.duration(to: ContinuousClock.now)
            #expect(noOpTally.count == 0)
            let newCopy = Clip(
                text: "a genuinely new synthetic clipboard item",
                kind: .text, copiedAt: noon.addingTimeInterval(1))

            let start = ContinuousClock.now
            let tally = StoreWriteTally()
            try await ClipboardStore.$writes.withValue(tally) {
                try await store.record(newCopy, keeping: retention)
            }
            #expect(tally.count == 1)
            #expect(tally.written.reduce(0) { $0 + $1.count } > 9_000_000)
            #expect(await store.clips(keeping: retention).count == 5_001)
            return (
                noOpElapsed, noOpTally.count, start.duration(to: ContinuousClock.now), tally.count,
                tally.written.reduce(0) { $0 + $1.count }
            )
        }

        _ = try await sample()  // Warm the code path before collecting five measured samples.
        var samples:
            [(
                noOpElapsed: Duration, noOpWrites: Int, elapsed: Duration, writes: Int, bytes: Int
            )] = []
        for _ in 0..<5 { samples.append(try await sample()) }
        samples.sort { $0.elapsed < $1.elapsed }
        let median = samples[samples.count / 2]
        print(
            "CLIPBOARD_BENCHMARK count=5000 encrypted=true pool=history samples=5 "
                + "newCopyMedian=\(median.elapsed) writes=\(median.writes) jsonBytes=\(median.bytes) "
                + "noOpMedian=\(samples.map(\.noOpElapsed).sorted()[samples.count / 2]) "
                + "noOpWrites=\(median.noOpWrites)"
        )
    }
}
