import Testing

@testable import UttrflowLocalModel

private actor SlowModelChunk {
    private var continuation: CheckedContinuation<Void, Never>?
    private var waiting: CheckedContinuation<Void, Never>?
    private var held = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private(set) var completed: [Int] = []
    private(set) var nextPassStarted = false

    func perform(_ chunk: ArraySlice<Int>) async {
        await acquire()
        defer { release() }
        if chunk.first == 1 {
            await withCheckedContinuation {
                continuation = $0
                waiting?.resume()
                waiting = nil
            }
        }
        completed.append(contentsOf: chunk)
    }

    func waitForSlowChunk() async {
        guard continuation == nil else { return }
        await withCheckedContinuation { waiting = $0 }
    }

    func finishSlowChunk() {
        continuation?.resume()
        continuation = nil
    }

    func beginNextPass() async {
        await acquire()
        defer { release() }
        nextPassStarted = true
    }

    private func acquire() async {
        if !held {
            held = true
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    private func release() {
        if waiters.isEmpty {
            held = false
        } else {
            waiters.removeFirst().resume()
        }
    }
}

@Suite("Cancellable model chunks")
struct CancellableModelChunksTests {
    @Test("A stale pass releases the slot after one slow chunk and does not start the next chunk")
    func cancellationReleasesSlotBetweenChunks() async {
        let model = SlowModelChunk()
        let stale = Task {
            try await CancellableModelChunks.run([1, 2, 3], chunkSize: 1) { chunk in
                await model.perform(chunk)
            }
        }
        await model.waitForSlowChunk()
        stale.cancel()
        let next = Task { await model.beginNextPass() }
        await model.finishSlowChunk()
        await next.value
        _ = await stale.result

        #expect(await model.completed == [1])
        #expect(await model.nextPassStarted)
    }

    @Test("Completed chunks preserve their outputs and never exceed the configured token bound")
    func completedOutputsRemainOrderedAndBounded() async throws {
        let inputs = Array(0..<11)
        let chunks = try await CancellableModelChunks.run(inputs, chunkSize: 4) { chunk in
            #expect(chunk.count <= 4)
            return Array(chunk)
        }

        #expect(chunks.flatMap { $0 } == inputs)
        #expect(chunks.map(\.count) == [4, 4, 3])
    }
}
