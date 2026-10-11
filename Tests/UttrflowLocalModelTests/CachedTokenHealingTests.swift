import Foundation
import MLXLMCommon
import Testing
import Tokenizers

@testable import UttrflowLocalModel

@Suite("Token healing with the pinned byte-level tokenizers already on disk", .serialized)
struct CachedTokenHealingTests {
    private static let enabled =
        ProcessInfo.processInfo.environment["UTTRFLOW_BYTE_TOKENIZER_PROOF"] == "1"
    private static let llama = snapshot(for: .llama32)
    private static let qwen = snapshot(for: .qwen3)

    @Test(
        "Llama's real vocabulary preserves word starts and masks newline tokens",
        .enabled(
            if: enabled && llama != nil,
            "needs the pinned Llama tokenizer and UTTRFLOW_BYTE_TOKENIZER_PROOF=1")
    )
    func llamaWordAndLineBoundaries() async throws {
        try await check(try #require(Self.llama))
    }

    @Test(
        "Qwen's real vocabulary preserves word starts and masks newline tokens",
        .enabled(
            if: enabled && qwen != nil, "needs the pinned Qwen tokenizer and UTTRFLOW_BYTE_TOKENIZER_PROOF=1")
    )
    func qwenWordAndLineBoundaries() async throws {
        try await check(try #require(Self.qwen))
    }

    private static func snapshot(for model: LocalModel) -> URL? {
        let repository = "models--" + model.identifier.replacingOccurrences(of: "/", with: "--")
        let folder = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".cache/huggingface/hub")
            .appending(path: repository).appending(path: "snapshots").appending(path: model.revision)
        return ["tokenizer.json", "tokenizer_config.json"].allSatisfy {
            FileManager.default.isReadableFile(atPath: folder.appending(path: $0).path)
        } ? folder : nil
    }

    private func check(_ folder: URL) async throws {
        let tokenizer = CachedHealingTokenizer(upstream: try await AutoTokenizer.from(modelFolder: folder))
        let vocabulary = TokenHealing.Vocabulary(
            tokenizer: tokenizer, endOfTurn: [], endingIds: [], prefixIndex: .init())
        let word = try #require(tokenizer.convertTokenToId("Ġthe"))
        let newline = try #require(tokenizer.convertTokenToId("Ċ"))
        let decodedWord = tokenizer.decode(tokenIds: [word], skipSpecialTokens: false)
        let decodedNewline = tokenizer.decode(tokenIds: [newline], skipSpecialTokens: false)
        #expect(decodedWord == " the")
        #expect(decodedNewline == "\n")
        #expect(vocabulary.bytes[word] == Array(decodedWord.utf8))
        #expect(vocabulary.bytes[word].first == 0x20)
        #expect(vocabulary.startsNewWord[word])
        #expect(vocabulary.bytes[newline] == [0x0A])
        #expect(vocabulary.ending.contains(newline))
        if let eos = tokenizer.eosTokenId { #expect(vocabulary.ending.contains(eos)) }
        var healing = TokenHealing(vocabulary: vocabulary, owed: decodedWord, wordComplete: false)
        let owingMask = healing.mask(width: vocabulary.bytes.count)
        let owing = try #require(owingMask)
        #expect(owing[word] == 0)
        healing.took(vocabulary.bytes[word])
        #expect(healing.owed.isEmpty)
        #expect(!healing.isFree)
        let continuingMask = healing.mask(width: vocabulary.bytes.count)
        let continuing = try #require(continuingMask)
        #expect(continuing[newline] == -.infinity)
        #expect(continuing[word].isFinite)
    }
}

private struct CachedHealingTokenizer: MLXLMCommon.Tokenizer {
    let upstream: any Tokenizers.Tokenizer

    func encode(text: String, addSpecialTokens: Bool) -> [Int] {
        upstream.encode(text: text, addSpecialTokens: addSpecialTokens)
    }

    func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String {
        upstream.decode(tokens: tokenIds, skipSpecialTokens: skipSpecialTokens)
    }

    func convertTokenToId(_ token: String) -> Int? { upstream.convertTokenToId(token) }
    func convertIdToToken(_ id: Int) -> String? { upstream.convertIdToToken(id) }
    var bosToken: String? { upstream.bosToken }
    var eosToken: String? { upstream.eosToken }
    var unknownToken: String? { upstream.unknownToken }

    func applyChatTemplate(
        messages: [[String: any Sendable]], tools: [[String: any Sendable]]?,
        additionalContext: [String: any Sendable]?
    ) throws -> [Int] {
        try upstream.applyChatTemplate(messages: messages, tools: tools, additionalContext: additionalContext)
    }
}
