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

    func recordUse(ofEntries ids: [UUID], writtenIn text: String) async throws(DictationChangeError) {
        let used = DictionaryAppearances.used(await dictionary.allEntries(), applied: ids, writtenIn: text)
        guard !used.isEmpty else { return }
        do {
            _ = try await dictionary.recordUse(of: used)
        } catch {
            throw .storeRefused
        }
        await noteUses(used)
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

    init(
        dictionary: PersonalDictionaryStore,
        didLearn: @escaping @Sendable ([DictionaryEntry]) async -> Void = { _ in }
    ) {
        self.dictionary = dictionary
        self.didLearn = didLearn
    }

    func learn(
        heard: String, wrote: String, seeing context: AppContext
    ) async throws(DictationChangeError) {
        do {
            let entries = try await dictionary.learn(
                heard: heard, wrote: wrote, seeing: context, at: Date())
            await didLearn(entries)
        } catch {
            throw .storeRefused
        }
    }
}
