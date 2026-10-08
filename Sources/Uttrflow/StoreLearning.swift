// The pipeline's learning seams, wired to the real dictionary and snippet stores.

import Foundation
import UttrflowAI
import UttrflowCore
import UttrflowDictionary
import UttrflowPipeline

/// Counts a finished dictation back into the two stores it drew on.
struct StoreCounters: DictationLearning {
    let dictionary: PersonalDictionaryStore
    let snippets: SnippetStore
    /// Told the entries a landed dictation used, after the dictionary counted them, so the ledger sees the same set.
    var noteUses: @Sendable ([UUID]) async -> Void = { _ in }
    /// Told the provisional entries a landed dictation wrote and the text it inserted, for ``EditAwayWatch``.
    var watchEdits: @Sendable ([EditAway.Applied], String) async -> Void = { _, _ in }

    func recordUse(ofEntries ids: [UUID], writtenIn text: String) async throws(DictationChangeError) {
        let entries = await dictionary.allEntries()
        let used = DictionaryAppearances.used(entries, applied: ids, writtenIn: text)
        guard !used.isEmpty else { return }
        // Taken before counting, since this use may be the one that promotes a word out of provisional.
        let provisional = entries.filter { $0.isProvisional && used.contains($0.id) }
            .map { EditAway.Applied(entryID: $0.id, word: $0.word) }
        do {
            _ = try await dictionary.recordUse(of: used)
        } catch {
            throw .storeRefused
        }
        await noteUses(used)
        if !provisional.isEmpty { await watchEdits(provisional, text) }
    }

    func recordUse(ofSnippets ids: [UUID]) async throws(DictationChangeError) {
        do {
            _ = try await snippets.recordUse(of: ids, at: Date())
        } catch {
            throw .storeRefused
        }
    }
}

/// Teaches the dictionary from a finished dictation, and is the only place the two targets meet.
struct LearnedVocabulary: VocabularyLearning {
    let dictionary: PersonalDictionaryStore
    let didLearn: @Sendable ([DictionaryEntry]) async -> Void
    /// The newest lines the user types in the dictation's application; read for sightings, never kept.
    let typedLines: @Sendable (AppContext) async -> [String]

    init(
        dictionary: PersonalDictionaryStore,
        didLearn: @escaping @Sendable ([DictionaryEntry]) async -> Void = { _ in },
        typedLines: @escaping @Sendable (AppContext) async -> [String] = { _ in [] }
    ) {
        self.dictionary = dictionary
        self.typedLines = typedLines
        self.didLearn = didLearn
    }

    func learn(
        heard: String, wrote: String, seeing context: AppContext
    ) async throws(DictationChangeError) {
        do {
            let entries = try await dictionary.learn(
                heard: heard, wrote: wrote, seeing: context, typed: await typedLines(context), at: Date())
            await didLearn(entries)
        } catch {
            throw .storeRefused
        }
    }
}
