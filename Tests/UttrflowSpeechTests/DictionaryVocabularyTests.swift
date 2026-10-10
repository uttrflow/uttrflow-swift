// Tests the dictionary-backed vocabulary source.
import Foundation
import Testing
import WhisperKit

@testable import UttrflowCore
import UttrflowDictionary
@testable import UttrflowSpeech

private struct DictionaryPromptTokenizer: PromptTokenizer {
    let firstSpecialToken = 50_257
    func encode(text: String) -> [Int] { text.unicodeScalars.map { Int($0.value) } }
}

private struct BytePromptTokenizer: PromptTokenizer {
    let firstSpecialToken = 50_257
    func encode(text: String) -> [Int] { text.utf8.map { Int($0) } }
}

private struct WhisperDictionaryPromptTokenizer: PromptTokenizer {
    let tokenizer: any WhisperTokenizer
    var firstSpecialToken: Int { tokenizer.specialTokens.specialTokenBegin }
    func encode(text: String) -> [Int] { tokenizer.encode(text: text) }
}

private actor MutableDictionaryReading {
    private var entries: [DictionaryEntry]

    init(entries: [DictionaryEntry]) {
        self.entries = entries
    }

    func replace(with entries: [DictionaryEntry]) {
        self.entries = entries
    }

    func snapshot(now: Date) -> (entries: [DictionaryEntry], index: PhoneticIndex, now: Date) {
        (entries, PhoneticIndex(entries: entries), now)
    }
}

@Suite("DictionaryVocabulary")
struct DictionaryVocabularyTests {
    private static let now = Date(timeIntervalSince1970: 1_700_000_000)
    private static let installedTokenizerFolder = FileSystemSpeechModelStore.defaultRoot()
        .appending(path: SpeechModel.default.variant, directoryHint: .isDirectory)
    private static let hasInstalledTokenizer = TokenizerAssets.arePresent(in: installedTokenizerFolder)

    private func entry(_ word: String, daysOld: Double = 0, timesUsed: Int = 0) -> DictionaryEntry {
        DictionaryEntry(
            word: word,
            origin: .added,
            firstSeen: Self.now.addingTimeInterval(-daysOld * 86_400),
            timesUsed: timesUsed
        )
    }

    /// The `n`th of a run of invented words that each sound different: a digit has no sound, so "Older1" and "Older2" are one entry.
    private static func distinct(_ n: Int) -> String {
        let sounds = Array("pktflmnrs")
        let first = sounds[n / 81 % 9].uppercased()
        return "\(first)a\(sounds[n / 9 % 9])e\(sounds[n % 9])o"
    }

    private func source(
        limit: Int = WorkingSet.defaultLimit,
        entries: [DictionaryEntry]
    ) -> DictionaryVocabulary {
        DictionaryVocabulary(limit: limit) { (entries, PhoneticIndex(entries: entries), Self.now) }
    }

    @Test("offers the dictionary ranked, best first")
    func ranksByValue() async {
        let words = await source(
            entries: [entry("Seldom", daysOld: 300), entry("Often", timesUsed: 40)]
        ).vocabulary(favouring: .unknown)

        // Seldom is old and never kept, so it is not worth its decoder steps.
        #expect(words == ["Often"])
    }

    @Test("favours what the frontmost app is showing")
    func favoursScreen() async {
        let words = await source(
            entries: [entry("Often", timesUsed: 40), entry("PaymentSheet")]
        ).vocabulary(favouring: AppContext(documentName: "PaymentSheet.swift"))

        #expect(words.first == "PaymentSheet")
    }

    @Test("stops at the limit it was given")
    func honoursLimit() async {
        let words = await source(
            limit: 2, entries: (0..<10).map { entry(Self.distinct($0)) }
        ).vocabulary(favouring: .unknown)

        #expect(words.count == 2)
    }

    @Test("keeps only the highest-ranked spelling for one pronunciation")
    func collapsesPhoneticDuplicates() async {
        let better = entry("color", timesUsed: 40)
        let duplicate = entry("colour")
        let distinct = entry("invoice", timesUsed: 2)
        let betterKeys = Set(WordSound(of: better.soundsLike).keys)
        let duplicateKeys = Set(WordSound(of: duplicate.soundsLike).keys)
        #expect(!betterKeys.isDisjoint(with: duplicateKeys))

        let words = await source(limit: 3, entries: [duplicate, distinct, better])
            .vocabulary(favouring: .unknown)

        #expect(words == ["color", "invoice"])
    }

    @Test("an empty dictionary asks for no biasing at all")
    func emptyDictionary() async {
        #expect(await source(entries: []).vocabulary(favouring: .unknown).isEmpty)
    }

    @Test("packs a newly added word before 40 older used entries")
    func recentAdditionSurvivesOlderUsage() async {
        let old = (0..<40).map { entry(Self.distinct($0), daysOld: 10, timesUsed: 1) }
        let newest = entry("Maelis", daysOld: 1)
        let words = await source(entries: old + [newest]).vocabulary(favouring: .unknown)
        let packing = VocabularyPrompt.packing(for: words, using: DictionaryPromptTokenizer())

        #expect(words.first == "Maelis")
        #expect(packing.words.first == "Maelis")
        #expect(packing.tokens?.count ?? 0 <= VocabularyPrompt.maximumTokens)
        #expect(packing.words.count < words.count)
    }

    @Test("the longest spelling the dictionary keeps fits the prompt even at one token per byte")
    func longestKeptSpellingFitsPrompt() {
        let longest = String(repeating: "x", count: PhoneticIndex.maximumBytesPerEntry)
        let packing = VocabularyPrompt.packing(for: [longest], using: BytePromptTokenizer())
        #expect(packing.words == [longest])
    }

    @Test(.enabled(if: Self.hasInstalledTokenizer))
    func recentAdditionSurvivesWithWhisperTokenizer() async throws {
        let older = (0..<40).map { entry(Self.distinct($0), daysOld: 10, timesUsed: 1) }
        let newest = entry("Maelis", daysOld: 1)
        let words = await source(limit: 96, entries: older + [newest]).vocabulary(favouring: .unknown)
        let tokenizer = try await ModelUtilities.loadTokenizer(
            for: .largev3, additionalSearchPaths: [Self.installedTokenizerFolder])
        let packing = VocabularyPrompt.packing(
            for: words, using: WhisperDictionaryPromptTokenizer(tokenizer: tokenizer))

        #expect(words.first == "Maelis")
        #expect(packing.words.first == "Maelis")
        #expect(packing.tokens?.count ?? 0 <= VocabularyPrompt.maximumTokens)
        #expect(packing.words.count < words.count)
    }

    @Test("reads additions, renames and removals on the next vocabulary request")
    func refreshesDictionaryForEachRequest() async {
        let reading = MutableDictionaryReading(entries: [entry("OldName")])
        let source = DictionaryVocabulary(limit: 96) {
            await reading.snapshot(now: Self.now)
        }

        #expect(await source.vocabulary(favouring: .unknown) == ["OldName"])

        await reading.replace(with: [entry("Renamed"), entry("NewWord")])
        let afterEdit = await source.vocabulary(favouring: .unknown)
        #expect(Set(afterEdit) == ["Renamed", "NewWord"])

        await reading.replace(with: [entry("NewWord")])
        #expect(await source.vocabulary(favouring: .unknown) == ["NewWord"])
    }
}
