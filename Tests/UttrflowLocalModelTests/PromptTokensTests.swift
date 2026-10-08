// Tests that a prompt tokenised from its frame and its cached lines is token for token the chat template's own.

import Foundation
import Hub
import Synchronization
import Testing
import Tokenizers
import UttrflowPredict

@testable import UttrflowLocalModel
import UttrflowTestSupport

/// A template shaped like Gemma 3's: the instructions and a blank line open the first turn, and the message is trimmed.
private let gemmaTemplate =
    "{{ bos_token }}{% if messages[0]['role'] == 'system' %}"
    + "{% set first = messages[0]['content'] + '\\n\\n' %}{% set turns = messages[1:] %}"
    + "{% else %}{% set first = '' %}{% set turns = messages %}{% endif %}"
    + "{% for message in turns %}{{ '<start_of_turn>' + message['role'] + '\\n' + (first if loop.first else '') }}"
    + "{{ message['content'] | trim }}{{ '<end_of_turn>\\n' }}{% endfor %}"
    + "{% if add_generation_prompt %}{{ '<start_of_turn>model\\n' }}{% endif %}"

/// A template that places the message as it is, untrimmed.
private let plainTemplate =
    "{{ bos_token }}{% for message in messages %}"
    + "{{ '<start_of_turn>' + message['role'] + '\\n' + message['content'] + '<end_of_turn>\\n' }}"
    + "{% endfor %}{{ '<start_of_turn>model\\n' }}"

/// A template whose words run on from the message with no added token between them.
private let runOnTemplate =
    "{% for message in messages %}{{ message['content'] + ' said so.\\n' }}{% endfor %}"

/// A small tokenizer shaped like Gemma's: line breaks, space runs and markers as added tokens, and merges that cross words.
private struct Fixture {
    static let markers = [
        "<pad>", "<eos>", "<bos>", "<unk>", "<start_of_turn>", "<end_of_turn>", "[multimodal]",
    ]
    static let runs =
        (1...8).map { String(repeating: "\n", count: $0) } + ["▁▁", "▁▁▁", "\t", "\t\t"]
    static let merges = [
        ("e", "n"), ("en", "d"), ("_", "o"), ("_o", "f"), ("▁", "t"), ("h", "e"), ("▁t", "he"), ("a", "l"),
        ("al", "p"), ("alp", "h"), ("alph", "a"), ("r", "n"), (".", "▁"), ("o", "r"), ("▁", "a"),
    ]
    static let singles =
        Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.,:;!?'\"-_<>/()*=[]▁é\r").map(
            String.init)

    static func tokenizer(
        template: String = gemmaTemplate, stripping: Bool = false, withLineBreak: Bool = true
    ) throws -> (PreTrainedTokenizer, [AddedToken]) {
        let added = (markers + runs).filter { withLineBreak || $0 != "\n" }
        var vocabulary: [String: Int] = [:]
        for token in added + singles + merges.map({ $0.0 + $0.1 }) where vocabulary[token] == nil {
            vocabulary[token] = vocabulary.count
        }
        let addedEntries: [[String: Any]] = added.map {
            [
                "id": vocabulary[$0] ?? 0, "content": $0, "lstrip": stripping && $0 == "<end_of_turn>",
                "rstrip": false, "normalized": false, "special": $0.hasPrefix("<"),
            ]
        }
        let data: [String: Any] = [
            "added_tokens": addedEntries,
            "normalizer": ["type": "Replace", "pattern": ["String": " "], "content": "▁"],
            "pre_tokenizer": [
                "type": "Split", "pattern": ["String": " "], "behavior": "MergedWithPrevious",
                "invert": false,
            ],
            "post_processor": [
                "type": "TemplateProcessing",
                "single": [
                    ["SpecialToken": ["id": "<bos>", "type_id": 0]], ["Sequence": ["id": "A", "type_id": 0]],
                ],
                "pair": [
                    ["SpecialToken": ["id": "<bos>", "type_id": 0]], ["Sequence": ["id": "A", "type_id": 0]],
                ],
            ],
            "model": [
                "type": "BPE", "vocab": vocabulary, "merges": merges.map { "\($0.0) \($0.1)" },
                "unk_token": "<unk>",
            ],
        ]
        let config: [String: Any] = [
            "tokenizer_class": "GemmaTokenizer", "bos_token": "<bos>", "eos_token": "<eos>",
            "unk_token": "<unk>", "chat_template": template,
        ]
        let tokenizer = try PreTrainedTokenizer(
            tokenizerConfig: Config(config as [NSString: Any]), tokenizerData: Config(data as [NSString: Any])
        )
        let tokens = added.map { AddedToken(content: $0, lstrip: stripping && $0 == "<end_of_turn>") }
        return (tokenizer, tokens)
    }
}

/// What a pass hands the tokenizer, the way `MLXCandidateScorer` asks for it.
private func render(_ message: String, with tokenizer: some Tokenizer) throws -> [Int] {
    try tokenizer.applyChatTemplate(messages: [
        ["role": "system", "content": MLXCandidateScorer.instructions], ["role": "user", "content": message],
    ])
}

/// How many times the template was rendered.
private final class Renders: Sendable {
    private let count = Mutex(0)
    var value: Int { count.withLock { $0 } }
    func add() { count.withLock { $0 += 1 } }
}

/// The frame read from a tokenizer, with renders counted.
private func frame(
    for tokenizer: some Tokenizer, added: [AddedToken], renders: Renders? = nil
) async
    -> PromptTokens?
{
    await PromptTokens(
        addedTokens: added,
        render: {
            renders?.add()
            return try render($0, with: tokenizer)
        },
        encode: { tokenizer.encode(text: $0, addSpecialTokens: false) },
        tokenText: { tokenizer.convertIdToToken($0) })
}

/// Pieces a random message is built from, weighted to the characters that sit on a boundary.
private let pieces = [
    "alpha", "the", " ", "  ", "\n", "\n\n", "\n\n\n\n\n\n\n\n\n\n\n", "\t", "\t\t\t", "▁", "▁▁", "<", ">",
    "<end_of_turn>", "<start_of_turn>", "<end_of", "end", "_of", "turn", "é", "e\u{301}", "\r\n", "\r",
    "[multimodal]", "of", "x", ".", ". ", "😀", "<eos", "model", "SELECT * FROM u", "git che",
]

private func randomMessage(_ random: inout Seeded) -> String {
    (0..<Int.random(in: 1...14, using: &random)).map { _ in random.pick(pieces) }.joined()
}

/// A prompt built from a frame and cached lines against the whole template, over boundary cases and random messages.
@Suite("The prompt's tokens from its frame and its lines")
struct PromptTokensTests {
    @Test(
        "Every random message, with the cache shared across them, tokenises exactly as the whole template does."
    )
    func randomMessagesAreTokenIdentical() async throws {
        let (tokenizer, added) = try Fixture.tokenizer()
        let prompt = try #require(await frame(for: tokenizer, added: added))
        #expect(prompt.trims)
        var random = Seeded(seed: 427)
        var fast = 0
        let total = 3_000
        for _ in 0..<total {
            let message = randomMessage(&random)
            let whole = try render(message, with: tokenizer)
            if let tokens = prompt.tokens(
                for: message, encode: { tokenizer.encode(text: $0, addSpecialTokens: false) })
            {
                fast += 1
                #expect(tokens == whole, "message \(message.debugDescription)")
            }
        }
        // Only a message empty once trimmed has no frame answer here, since no added token joins across this frame.
        #expect(fast > total * 9 / 10)
    }

    @Test(
        "A message that could join the frame's added tokens is sent the long way, and every one the frame answers is identical.",
        arguments: [
            "\nline", "▁▁line", "<start_of_turn>x", "<", "line<", "line<end_of_turn", "line\n", "line▁",
            "line\t",
            "\t\tx", "x\n\n\n\n\n\n\n\n\n\ny", "e\u{301}", "\r\nx\r\n", "   ", "",
        ])
    func boundaryMessages(message: String) async throws {
        let (tokenizer, added) = try Fixture.tokenizer()
        let prompt = try #require(await frame(for: tokenizer, added: added))
        let tokens = prompt.tokens(
            for: message, encode: { tokenizer.encode(text: $0, addSpecialTokens: false) })
        if let tokens { try #expect(tokens == render(message, with: tokenizer)) }
        if PromptTokens.trimmed(message).isEmpty { #expect(tokens == nil) }
    }

    @Test(
        "An untrimmed template is read as untrimmed, and a message opening on a line break is refused, not guessed."
    )
    func untrimmedTemplate() async throws {
        let (tokenizer, added) = try Fixture.tokenizer(template: plainTemplate)
        let prompt = try #require(await frame(for: tokenizer, added: added))
        #expect(!prompt.trims)
        #expect(
            prompt.tokens(for: "\nx", encode: { tokenizer.encode(text: $0, addSpecialTokens: false) }) == nil)
        var random = Seeded(seed: 7)
        for _ in 0..<500 {
            let message = randomMessage(&random)
            guard
                let tokens = prompt.tokens(
                    for: message, encode: { tokenizer.encode(text: $0, addSpecialTokens: false) })
            else { continue }
            try #expect(tokens == render(message, with: tokenizer), "message \(message.debugDescription)")
        }
    }

    @Test("Without a line-break token, or with a token that swallows whitespace, there is no frame to trust.")
    func refusesTokenizersWithoutHardLineBreaks() async throws {
        let (plain, withoutBreak) = try Fixture.tokenizer(withLineBreak: false)
        #expect(await frame(for: plain, added: withoutBreak) == nil)
        let (stripping, stripped) = try Fixture.tokenizer(stripping: true)
        #expect(await frame(for: stripping, added: stripped) == nil)
        let (tokenizer, added) = try Fixture.tokenizer()
        let mixed = added + [AddedToken(content: "x\n")]
        #expect(await frame(for: tokenizer, added: mixed) == nil)
    }

    @Test("A template that fails, or places no added token around the message, gives no frame.")
    func refusesUnframedTemplates() async throws {
        let (tokenizer, added) = try Fixture.tokenizer()
        let failing = await PromptTokens(
            addedTokens: added, render: { _ in throw CancellationError() }, encode: { _ in [] },
            tokenText: { _ in nil })
        #expect(failing == nil)
        let unframed = await PromptTokens(
            addedTokens: added, render: { tokenizer.encode(text: "say " + $0, addSpecialTokens: false) },
            encode: { tokenizer.encode(text: $0, addSpecialTokens: false) },
            tokenText: { tokenizer.convertIdToToken($0) })
        #expect(unframed == nil)
        let (runOn, runOnAdded) = try Fixture.tokenizer(template: runOnTemplate)
        #expect(await frame(for: runOn, added: runOnAdded) == nil)
        let lying = await PromptTokens(
            addedTokens: added, render: { try render($0 + "!", with: tokenizer) },
            encode: { tokenizer.encode(text: $0, addSpecialTokens: false) },
            tokenText: { tokenizer.convertIdToToken($0) })
        #expect(lying == nil)
    }

    @Test(
        "The next keystroke's pass renders nothing and tokenises only the line that changed, never the instructions or the screen."
    )
    func aKeystrokeTokenisesOnlyItsLine() async throws {
        let (tokenizer, added) = try Fixture.tokenizer()
        let renders = Renders()
        let prompt = try #require(await frame(for: tokenizer, added: added, renders: renders))
        let atLoad = renders.value
        let register = Register(
            isMultiline: true, typicalLength: 9, isConversational: true, symbolShare: 0.02,
            usesSentenceCase: false)
        let situation = GenerationSituation(
            application: "Chat", windowTitle: "Planning",
            surroundings: "Sam: the draft looks fine\nSam: can we move the review\nSam: to Thursday?",
            recentLines: ["on my way"])
        let encode = { (text: String) in tokenizer.encode(text: text, addSpecialTokens: false) }
        let first = CompletionPromptBuilder.message(
            typed: "Sure, Thursday wo", in: situation, register: register)
        try #expect(prompt.tokens(for: first, encode: encode) == render(first, with: tokenizer))
        let before = prompt.tally
        let second = CompletionPromptBuilder.message(
            typed: "Sure, Thursday wor", in: situation, register: register)
        let tokens = prompt.tokens(for: second, encode: encode)
        try #expect(tokens == render(second, with: tokenizer))
        let paid = prompt.tally
        #expect(renders.value == atLoad)
        #expect(paid.encodes - before.encodes == 1)
        // The whole template would hand the tokenizer the instructions and the message, well over a thousand characters.
        let changed = Set(PromptTokens.chunks(of: second)).subtracting(PromptTokens.chunks(of: first))
        #expect(changed.count == 1)
        #expect(paid.characters - before.characters == changed.first?.count)
        #expect(paid.characters - before.characters < 20)
    }

    @Test("Two spellings Swift calls equal but the tokenizer reads apart are cached apart.")
    func canonicallyEqualLinesAreCachedApart() async throws {
        let (tokenizer, added) = try Fixture.tokenizer()
        let prompt = try #require(await frame(for: tokenizer, added: added))
        let encode = { (text: String) in tokenizer.encode(text: text, addSpecialTokens: false) }
        for message in ["x\n\u{E9}", "x\ne\u{301}", "\u{E9}", "e\u{301}"] {
            try #expect(prompt.tokens(for: message, encode: encode) == render(message, with: tokenizer))
        }
    }

    @Test("A full line cache drops its least recently used line and still answers exactly.")
    func cacheDropsLeastRecentlyUsed() async throws {
        let (tokenizer, added) = try Fixture.tokenizer()
        let prompt = try #require(await frame(for: tokenizer, added: added))
        let encode = { (text: String) in tokenizer.encode(text: text, addSpecialTokens: false) }
        for index in 0...(PromptTokens.lineCapacity + 3) {
            let message = "line \(index)\nshared"
            try #expect(prompt.tokens(for: message, encode: encode) == render(message, with: tokenizer))
        }
        // The line every message shares stays cached, while the first line, unused since, went back to the tokenizer.
        let before = prompt.tally.encodes
        _ = prompt.tokens(for: "fresh\nshared", encode: encode)
        #expect(prompt.tally.encodes == before + 1)
        try #expect(
            prompt.tokens(for: "line 0\nshared", encode: encode) == render("line 0\nshared", with: tokenizer))
        #expect(prompt.tally.encodes == before + 2)
    }

    @Test("A message is cut after each run of line breaks and nowhere else.")
    func chunks() {
        #expect(PromptTokens.chunks(of: "a\nb\n\n\nc") == ["a\n", "b\n\n\n", "c"])
        #expect(PromptTokens.chunks(of: "\n\na") == ["\n\n", "a"])
        #expect(PromptTokens.chunks(of: "ab\n") == ["ab\n"])
        #expect(PromptTokens.chunks(of: "x\r\ny") == ["x\r\n", "y"])
        #expect(PromptTokens.chunks(of: "").isEmpty)
    }

    @Test(
        "The characters that would join a frame token are exactly those some added token continues it with.")
    func joiningCharacters() {
        let contents = ["\n", "\n\n", "\n\n\n", "<end_of_turn>", "a<end"]
        #expect(PromptTokens.joining(after: "\n\n", among: contents) == ["\n"])
        #expect(PromptTokens.joining(after: "<end_of_turn>", among: contents).isEmpty)
        #expect(PromptTokens.joining(before: "<end_of_turn>", among: contents) == ["a"])
        #expect(PromptTokens.joining(before: "\n", among: contents) == ["\n"])
    }

    @Test("The added tokens are read from a tokenizer file, and a missing or unreadable one gives nothing.")
    func readsAddedTokens() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "tokenizer.json")
        try Data(
            #"{"added_tokens":[{"id":0,"content":"\n","lstrip":false,"rstrip":true,"special":false}],"model":{}}"#
                .utf8
        ).write(to: file)
        #expect(AddedToken.read(fromTokenizerFile: file) == [AddedToken(content: "\n", rstrip: true)])
        try Data("{}".utf8).write(to: file)
        #expect(AddedToken.read(fromTokenizerFile: file) == nil)
        #expect(AddedToken.read(fromTokenizerFile: directory.appending(path: "absent.json")) == nil)
    }

    /// How many moments to prove against the suggestion model's own tokenizer, set only where it is on disk; a debug build takes seconds a case.
    static let gemmaCases = ProcessInfo.processInfo.environment["UTTRFLOW_TOKENIZER_PROOF"].flatMap {
        Int($0)
    }

    /// The suggestion model's snapshot, when this Mac has it.
    static let gemmaSnapshot = CachedSnapshot.complete(
        identifier: LocalModel.gemma3.identifier, revision: LocalModel.gemma3.revision,
        in: FileManager.default.homeDirectoryForCurrentUser.appending(path: ".cache/huggingface/hub"),
        minimumWeightBytes: 0)

    @Test(
        "With Gemma 3's own tokenizer, prompts for random moments and tails are token-identical.",
        .enabled(
            if: gemmaCases != nil && gemmaSnapshot != nil, "set UTTRFLOW_TOKENIZER_PROOF with Gemma 3 on disk"
        ))
    func gemmaTokenizerIsTokenIdentical() async throws {
        let folder = try #require(Self.gemmaSnapshot)
        let tokenizer = try await AutoTokenizer.from(modelFolder: folder)
        let added = try #require(AddedToken.read(fromTokenizerFile: folder.appending(path: "tokenizer.json")))
        let prompt = try #require(await frame(for: tokenizer, added: added))
        var random = Seeded(seed: 427)
        let encode = { (text: String) in tokenizer.encode(text: text, addSpecialTokens: false) }
        var fast = 0
        for _ in 0..<(Self.gemmaCases ?? 0) {
            let register = Register(
                isMultiline: random.chance(0.5), typicalLength: 9, isConversational: random.chance(0.5),
                symbolShare: 0.02, usesSentenceCase: false)
            let screen = (0..<Int.random(in: 0...6, using: &random)).map { _ in randomMessage(&random) }
            let situation = GenerationSituation(
                application: random.pick(["Mail", "Terminal", "Chat"]),
                surroundings: screen.isEmpty ? nil : screen.joined(separator: "\n"),
                recentLines: random.chance(0.5) ? [randomMessage(&random)] : [])
            let message = CompletionPromptBuilder.message(
                typed: randomMessage(&random), in: situation, register: register)
            let whole = try render(message, with: tokenizer)
            guard let tokens = prompt.tokens(for: message, encode: encode) else { continue }
            fast += 1
            #expect(tokens == whole, "message \(message.debugDescription)")
        }
        #expect(fast * 2 > (Self.gemmaCases ?? 0))
    }
}
