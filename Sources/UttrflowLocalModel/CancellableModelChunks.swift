import Foundation
import MLXLMCommon

/// Keeps a model cache exclusively between serial container operations for one pass.
final class ModelCacheTransfer: @unchecked Sendable {
    var layers: [KVCache]?

    init(_ layers: [KVCache]? = nil) {
        self.layers = layers
    }

    func obtain(
        from source: PromptChunkInput.CacheSource, kept: [KVCache]?, warm: [KVCache]?,
        model: any LanguageModel
    ) -> [KVCache] {
        if let layers { return layers }
        let next: [KVCache] =
            switch source {
            case .empty: model.newCache(parameters: nil)
            case .kept: kept ?? model.newCache(parameters: nil)
            case .warm: warm?.map { $0.copy() } ?? model.newCache(parameters: nil)
            }
        layers = next
        return next
    }
}

/// Runs bounded model operations separately so each completed chunk releases the container slot.
enum CancellableModelChunks {
    /// The largest input passed to one serialized model operation.
    static let tokenLimit = 128

    @discardableResult
    static func run<Input: Sendable, Output: Sendable>(
        _ input: [Input], chunkSize: Int = tokenLimit,
        perform: @escaping @Sendable (ArraySlice<Input>) async throws -> Output
    ) async throws -> [Output] {
        guard chunkSize > 0 else { preconditionFailure("Chunk size must be positive") }
        var output: [Output] = []
        output.reserveCapacity((input.count + chunkSize - 1) / chunkSize)
        var start = 0
        while start < input.count {
            try Task.checkCancellation()
            let end = min(start + chunkSize, input.count)
            output.append(try await perform(input[start..<end]))
            start = end
            try Task.checkCancellation()
        }
        return output
    }
}

struct PromptChunkInput: Sendable {
    enum CacheSource: Sendable, Equatable {
        case empty
        case kept
        case warm
    }

    let allTokens: [Int]
    let remainingTokens: [Int]
    let cacheSource: CacheSource
}
