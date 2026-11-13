// Fixing a word from a History row, and saving a word from the editor.
import Foundation
import UttrflowCore
import UttrflowDictionary
import UttrflowUX

extension AppDelegate {
    /// Opens the editor on a written spelling from one dictation, remembering that dictation for a retry.
    func fixWord(_ written: String, from dictation: UUID) {
        // The wrong spelling is the recogniser's reading of the sound, so it fills "Say it like"; the editor focuses "Write it as".
        actionNotice = nil
        fixingDictation = dictation
        mainWindow?.show(.dictionary)
        editWord(DictionaryDraft(pronunciation: written))
    }

    /// Saves a new word, closing the editor once it is in and offering a retry when the fix came from kept audio.
    func saveWord(_ word: String, pronunciation: String, applications: [String]) {
        intentWork = Task { [weak self] in
            guard let self else { return }
            do throws(DictionaryStoreError) {
                try await dictionary.add(
                    word: word, pronunciation: pronunciation, at: Date(), applications: applications)
                editWord(nil)
                if let id = fixingDictation, await recordings.keepsFinished(id, now: Date()) {
                    actionNotice = .retryAfterFix(saving: word, recording: id)
                }
                fixingDictation = nil
            } catch {
                Self.log.error("could not add word: \(error.userMessage, privacy: .public)")
                wordRefusal = error.userMessage
                refreshMainWindow()
            }
        }
    }
}
