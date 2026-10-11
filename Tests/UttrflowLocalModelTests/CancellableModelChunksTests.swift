import MLX
import MLXLMCommon
import MLXNN
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

/// A model that only hands out caches, since no test here evaluates one.
private final class CacheOnlyModel: Module, LanguageModel {
    func prepare(_ input: LMInput, cache: [any KVCache], windowSize: Int?) throws -> PrepareResult {
        .tokens(input.text)
    }

    func newCache(parameters: GenerateParameters?) -> [any KVCache] { [KVCacheSimple(), KVCacheSimple()] }
}

@Suite("The cache a pass keeps between model operations")
struct ModelCacheTransferTests {
    private let model = CacheOnlyModel()

    @Test("A transfer holds the layers it was given and none when it was given none.")
    func holdsGivenLayers() {
        #expect(ModelCacheTransfer().layers == nil)
        #expect(ModelCacheTransfer([KVCacheSimple()]).layers?.count == 1)
    }

    @Test("An empty source starts a fresh cache from the model, and later asks get the same layers back.")
    func emptySourceAsksTheModel() {
        let transfer = ModelCacheTransfer()
        let first = transfer.obtain(from: .empty, kept: nil, warm: nil, model: model)
        #expect(first.count == 2)
        let again = transfer.obtain(from: .kept, kept: [KVCacheSimple()], warm: nil, model: model)
        #expect(again.count == 2)
    }

    @Test("A kept source reuses the kept layers, or starts fresh when none were kept.")
    func keptSource() {
        #expect(
            ModelCacheTransfer().obtain(from: .kept, kept: [KVCacheSimple()], warm: nil, model: model).count
                == 1)
        #expect(ModelCacheTransfer().obtain(from: .kept, kept: nil, warm: nil, model: model).count == 2)
    }

    @Test("A warm source copies the warm layers, or starts fresh when there are none.")
    func warmSource() {
        #expect(
            ModelCacheTransfer().obtain(from: .warm, kept: nil, warm: [KVCacheSimple()], model: model).count
                == 1)
        #expect(ModelCacheTransfer().obtain(from: .warm, kept: nil, warm: nil, model: model).count == 2)
    }
}
