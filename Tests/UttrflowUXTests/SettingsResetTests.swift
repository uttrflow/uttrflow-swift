import Foundation
@testable import UttrflowClipboard
import UttrflowCore
import UttrflowDictionary
import UttrflowHistory
import UttrflowSettings
import Testing

@testable import UttrflowUX

// MARK: - Fixtures

/// Every shape the counts can take, swept by each suite that reads a sentence built from them.
enum SettingsPersonalisationFixtures {
    static let nothing = SettingsPersonalisation.nothing
    static let onlyLearned = SettingsPersonalisation(
        learnedWords: 34, addedWords: 0, transcripts: 0)
    static let onlyAdded = SettingsPersonalisation(learnedWords: 0, addedWords: 12, transcripts: 0)
    static let onlyTranscripts = SettingsPersonalisation(
        learnedWords: 0, addedWords: 0, transcripts: 9)
    static let singular = SettingsPersonalisation(learnedWords: 1, addedWords: 1, transcripts: 1)
    static let plenty = SettingsPersonalisation(learnedWords: 34, addedWords: 12, transcripts: 142)

    static let every: [SettingsPersonalisation] = [
        nothing, onlyLearned, onlyAdded, onlyTranscripts, singular, plenty,
    ]
}

/// A directory of its own per test, so nothing here reaches the runner's own files.
private func inATemporaryDirectory(
    _ body: (URL) async throws -> Void
) async throws {
    let directory = URL.temporaryDirectory.appending(
        path: "uttrflow-reset-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer {
        // Permissions go back first, or a read-only directory is one nothing can remove.
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path())
        try? FileManager.default.removeItem(at: directory)
    }
    try await body(directory)
}

private func entry(_ word: String, _ origin: WordOrigin) -> DictionaryEntry {
    DictionaryEntry(word: word, origin: origin, firstSeen: Date(timeIntervalSince1970: 0))
}

/// Two of everything, so a reset that keeps the wrong kind is visible rather than ambiguous.
private let mixedDictionary = [
    entry("kubectl", .added), entry("Nikhil", .learned), entry("Aarav", .observed),
    entry("Bengaluru", .added), entry("terraform", .learned),
]

// MARK: - What a level means

@Suite("A level of forgetting")
struct SettingsResetLevelTests {
    @Test("forgetting keeps the dictionary; resetting empties it")
    func targetsSayWhichDictionaryTheyMean() {
        #expect(SettingsReset.learnedWords.targets == [.learnedWords])
        #expect(SettingsReset.everything.targets.contains(.everyWord))
        #expect(SettingsReset.everything.targets.contains(.history))
        #expect(SettingsReset.everything.targets.contains(.preferences))
    }

    /// Every level, listed rather than enumerated because one of them names an application.
    static let everyLevel: [SettingsReset] = [
        .learnedWords, .everything, .suggestions(inApplication: "com.example.editor"),
    ]

    /// The switch is exhaustive, so a sixth level cannot be added without this failing to build.
    @Test("every level there is appears in the list this suite sweeps")
    func everyLevelIsSwept() {
        for level in Self.everyLevel {
            switch level {
            case .learnedWords, .everything, .suggestions: continue
            }
        }
        #expect(Set(Self.everyLevel).count == Self.everyLevel.count)
    }

    /// Two opinions about the dictionary in one reset would leave the count describing only one.
    @Test("never holds two opinions about the dictionary at once")
    func noLevelBothKeepsAndEmpties() {
        for reset in Self.everyLevel {
            let targets = reset.targets
            #expect(
                !(targets.contains(.learnedWords) && targets.contains(.everyWord)),
                "\(reset) both keeps and empties the dictionary")
            for target in targets {
                #expect(
                    targets.count(where: { $0 == target }) == 1, "\(reset) repeats a target")
            }
            #expect(!targets.isEmpty, "\(reset) removes nothing")
        }
    }

    /// A dialogue in front of a recoverable action teaches people to dismiss dialogues.
    @Test("asks only before the one that cannot be undone")
    func onlyTheIrreversibleOneAsks() {
        #expect(!SettingsReset.learnedWords.isConfirmed)
        #expect(SettingsReset.everything.isConfirmed)
    }
}

// MARK: - Counting

@Suite("What there is to forget")
struct SettingsPersonalisationTests {
    @Test("counts everything the app inferred as learned, and only the user's own as added")
    func splitsTheDictionaryTheWayTheResetDoes() {
        let counts = SettingsPersonalisation(entries: mixedDictionary, transcripts: 7)
        #expect(counts.learnedWords == 3)
        #expect(counts.addedWords == 2)
        #expect(counts.words == 5)
        #expect(counts.transcripts == 7)
        #expect(!counts.isEmpty)
    }

    @Test("a fresh install has nothing of anybody in it")
    func nothingIsNothing() {
        #expect(SettingsPersonalisation.nothing.isEmpty)
        #expect(SettingsPersonalisation.nothing.words == 0)
        #expect(SettingsPersonalisation(entries: [], transcripts: 0).isEmpty)
        // Transcripts alone are still something, even with an empty dictionary.
        #expect(!SettingsPersonalisation(entries: [], transcripts: 1).isEmpty)
    }
}

// MARK: - The stores

@Suite("The files a reset reaches")
struct FilePersonalisationStoreTests {
    private func stores(
        in directory: URL
    ) -> (PersonalDictionaryStore, DictationHistoryStore) {
        (
            PersonalDictionaryStore(file: directory.appending(path: "dictionary.json")),
            DictationHistoryStore(file: directory.appending(path: "history.json"))
        )
    }

    /// The clipboard the reset now also clears, in its own file per test.
    private func clipboardStore(in directory: URL) -> ClipboardStore {
        ClipboardStore(file: directory.appending(path: "clipboard.json"))
    }

    private func fill(
        _ dictionary: PersonalDictionaryStore, _ history: DictationHistoryStore, now: Date
    ) async throws {
        for entry in mixedDictionary { try await dictionary.add(entry) }
        for index in 0..<4 {
            try await history.append(
                DictationRecord(text: "one \(index)", when: now),
                keeping: Retention(days: 7, now: now))
        }
    }

    @Test("counts what is actually on disk")
    func countsWhatIsThere() async throws {
        try await inATemporaryDirectory { directory in
            let now = Date()
            let (dictionary, history) = stores(in: directory)
            try await fill(dictionary, history, now: now)

            let counts = await FilePersonalisationStore(
                dictionary: dictionary, history: history,
                clipboard: clipboardStore(in: directory)
            )
            .personalisation(keeping: Retention(days: 7, now: now))
            #expect(counts == SettingsPersonalisation(learnedWords: 3, addedWords: 2, transcripts: 4))
        }
    }

    /// Transcripts already promised deleted are not counted again; the number shown is what is there.
    @Test("does not count transcripts the promise has already retired")
    func expiredTranscriptsAreNotCounted() async throws {
        try await inATemporaryDirectory { directory in
            let now = Date()
            let (dictionary, history) = stores(in: directory)
            try await history.append(
                DictationRecord(text: "old", when: now.addingTimeInterval(-40 * 86_400)),
                keeping: Retention(days: 90, now: now))

            let counts = await FilePersonalisationStore(
                dictionary: dictionary, history: history,
                clipboard: clipboardStore(in: directory)
            )
            .personalisation(keeping: Retention(days: 7, now: now))
            #expect(counts.transcripts == 0)
        }
    }

    /// The heart of the third level: hand-added words survive, guesses do not, history is untouched.
    @Test("forgetting keeps the words the user added and drops the rest")
    func forgettingKeepsWhatWasTaught() async throws {
        try await inATemporaryDirectory { directory in
            let now = Date()
            let (dictionary, history) = stores(in: directory)
            try await fill(dictionary, history, now: now)
            let store = FilePersonalisationStore(
                dictionary: dictionary, history: history,
                clipboard: clipboardStore(in: directory))

            try await store.carryOut(.learnedWords)

            let left = await dictionary.allEntries()
            #expect(left.map(\.word).sorted() == ["Bengaluru", "kubectl"])
            #expect(left.allSatisfy { $0.origin == .added })
            let untouched = await history.records(keeping: Retention(days: 7, now: now))
            #expect(untouched.count == 4)
        }
    }

    @Test("resetting leaves nothing of the user on this Mac")
    func resettingLeavesNothing() async throws {
        try await inATemporaryDirectory { directory in
            let now = Date()
            let (dictionary, history) = stores(in: directory)
            try await fill(dictionary, history, now: now)
            let store = FilePersonalisationStore(
                dictionary: dictionary, history: history,
                clipboard: clipboardStore(in: directory))

            try await store.carryOut(.everything)

            let counts = await store.personalisation(keeping: Retention(days: 7, now: now))
            #expect(counts == .nothing)
        }
    }

    /// A disk that refuses is not a reset that happened, and looking cannot tell them apart.
    @Test("reports a disk that would not take the change")
    func aRefusedWriteIsReported() async throws {
        try await inATemporaryDirectory { directory in
            let (dictionary, history) = stores(in: directory)
            for entry in mixedDictionary { try await dictionary.add(entry) }
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o500], ofItemAtPath: directory.path())

            let store = FilePersonalisationStore(
                dictionary: dictionary, history: history,
                clipboard: clipboardStore(in: directory))
            await #expect(throws: SettingsResetFailure.self) {
                try await store.carryOut(.learnedWords)
            }
        }
    }
}

// MARK: - Asking, and being asked

@Suite("Asking for something to be forgotten")
struct SettingsRemovalRequestTests {
    private func session(
        _ personalisation: SettingsPersonalisation = SettingsPersonalisationFixtures.plenty
    ) -> SettingsSession {
        SettingsSession(settings: .default, personalisation: personalisation)
    }

    /// The destructive button on a row, as the window would hand it back.
    private func button(
        _ tab: SettingsTab, _ id: String, in session: SettingsSession
    )
        -> SettingsRemoval?
    {
        var session = session
        session.tab = tab
        let row = session.presentation.pane.groups.flatMap(\.rows).first { $0.id == id }
        guard case .removal(let removal)? = row?.control else { return nil }
        return removal
    }

    @Test("forgetting what was learned happens at once, because it is recoverable")
    func forgettingNeedsNoDialogue() throws {
        var session = session()
        let removal = try #require(button(.dictation, "forgetLearned", in: session))

        #expect(session.request(removal) == .learnedWords)
        #expect(session.pendingRemoval == nil)
        #expect(session.rejection == nil)
    }

    @Test("resetting asks first, and asking removes nothing")
    func resettingAsksFirst() throws {
        var session = session()
        let removal = try #require(button(.privacy, "resetPersonalisation", in: session))

        #expect(session.request(removal) == nil)
        #expect(session.pendingRemoval == removal)
        #expect(session.rejection == nil)
    }

    /// A question that is dismissed is a question that removes nothing.
    @Test("a confirmation that is dismissed removes nothing")
    func dismissingRemovesNothing() throws {
        var session = session()
        let removal = try #require(button(.privacy, "resetPersonalisation", in: session))
        session.request(removal)

        session.dismissRemoval()

        // Nothing was asked of the stores, and nothing changed.
        #expect(session.pendingRemoval == nil)
        #expect(session.personalisation == SettingsPersonalisationFixtures.plenty)
        #expect(session.settings == .default)
    }

    @Test("a confirmation that is accepted hands back the level to carry out")
    func confirmingHandsBackTheLevel() throws {
        var session = session()
        let removal = try #require(button(.privacy, "resetPersonalisation", in: session))
        session.request(removal)

        #expect(session.confirm(removal) == .everything)
        #expect(session.pendingRemoval == nil)
    }

    /// The answer survives either order of the dialogue closing and its button acting.
    @Test("the answer survives the question being cleared first")
    func answeringDoesNotDependOnTheDialogueClosingLast() throws {
        var session = session()
        let removal = try #require(button(.privacy, "resetPersonalisation", in: session))
        session.request(removal)

        session.dismissRemoval()
        #expect(session.confirm(removal) == .everything)
    }

    /// Only a removal that asks can be answered; one with no question behind it cannot.
    @Test("refuses to confirm something that was never asked")
    func nothingUnaskedCanBeConfirmed() throws {
        var session = session()
        let forget = try #require(button(.dictation, "forgetLearned", in: session))
        #expect(session.confirm(forget) == nil)
    }

    /// The row greys and the request refuses from one function, so neither can outlive the other.
    @Test("refuses to forget what was never learned, and says so on the row first")
    func nothingLearnedIsRefusedAndShown() throws {
        var session = session(SettingsPersonalisationFixtures.onlyAdded)
        session.tab = .dictation
        let row = try #require(
            session.presentation.pane.groups.flatMap(\.rows).first { $0.id == "forgetLearned" })
        #expect(row.isEnabled == false)

        let removal = try #require(button(.dictation, "forgetLearned", in: session))
        #expect(session.request(removal) == nil)
        #expect(session.rejection == row.unavailability)
    }

    /// Preferences are always there to put back, so a reset always does something.
    @Test("resetting stays available even with nothing saved")
    func resettingIsNeverADeadEnd() throws {
        var session = session(.nothing)
        session.tab = .privacy
        let row = try #require(
            session.presentation.pane.groups.flatMap(\.rows)
                .first { $0.id == "resetPersonalisation" })
        #expect(row.isEnabled)

        let removal = try #require(button(.privacy, "resetPersonalisation", in: session))
        #expect(session.request(removal) == nil)
        #expect(session.pendingRemoval != nil)
    }
}

// MARK: - Afterwards

@Suite("Once something has been forgotten")
struct SettingsRemovalCompletionTests {
    @Test("takes the new counts from the stores rather than assuming them")
    func countsComeBackFromTheStores() {
        var session = SettingsSession(
            settings: .default, personalisation: SettingsPersonalisationFixtures.plenty)
        let left = SettingsPersonalisation(learnedWords: 0, addedWords: 12, transcripts: 142)

        #expect(session.completed(.learnedWords, leaving: left) == nil)
        #expect(session.personalisation == left)
    }

    @Test("puts the settings back only when the level says to, and hands them back to save")
    func resettingRestoresTheDefaults() {
        var changed = Settings.default
        changed.floatingButtonAnchor = .rightEdge
        changed.hotkey = HotkeyBinding(keyCode: 40, modifiers: [.command, .shift])

        var session = SettingsSession(settings: changed)
        #expect(session.completed(.learnedWords, leaving: .nothing) == nil)
        #expect(session.settings == changed)

        #expect(session.completed(.everything, leaving: .nothing) == .default)
        #expect(session.settings == .default)
        // The shortcut field follows, so the window is not left offering a dead key.
        #expect(session.recorder.binding == Settings.default.hotkey)
    }

    @Test("clears the question and the last refusal")
    func nothingIsLeftHalfAsked() {
        var session = SettingsSession(
            settings: .default, personalisation: SettingsPersonalisationFixtures.plenty)
        session.apply(.retention(days: 0))
        session.tab = .privacy
        let row = session.presentation.pane.groups.flatMap(\.rows)
            .first { $0.id == "resetPersonalisation" }
        guard case .removal(let removal)? = row?.control else {
            Issue.record("the reset row is not a button")
            return
        }
        session.request(removal)
        session.confirm(removal)

        session.completed(.everything, leaving: .nothing)
        #expect(session.pendingRemoval == nil)
        #expect(session.rejection == nil)
    }

    /// Whether the words a user asked to delete are still there is never left to assumption.
    @Test("says so when the disk refused, and says which way it left things")
    func aFailureIsSaidOutLoud() {
        var session = SettingsSession(settings: .default)
        session.failed(.learnedWords)
        #expect(session.rejection?.contains("nothing was forgotten") == true)
        #expect(session.pendingRemoval == nil)

        session.failed(.everything)
        #expect(session.rejection?.contains("may still be here") == true)
    }
}

// MARK: - The counts on screen

@Suite("What a destructive button promises")
struct SettingsRemovalCopyTests {
    private func row(
        _ tab: SettingsTab, _ id: String, _ counts: SettingsPersonalisation
    )
        -> SettingsRow?
    {
        SettingsPresenter.pane(for: tab, settings: .default, personalisation: counts)
            .groups.flatMap(\.rows).first { $0.id == id }
    }

    /// The design's wording, with real numbers in it, in the row rather than in a dialogue.
    @Test("says what forgetting takes and what it keeps, counted")
    func forgettingIsCountedOnTheRow() {
        let row = row(.dictation, "forgetLearned", SettingsPersonalisationFixtures.plenty)
        #expect(row?.explanation == "Forget 34 learned words, keeping 12 you added yourself.")
        #expect(row?.isEnabled == true)
    }

    @Test("agrees with the number, down to one of each")
    func countsAreWrittenInAgreement() {
        #expect(
            row(.dictation, "forgetLearned", SettingsPersonalisationFixtures.singular)?.explanation
                == "Forget 1 learned word, keeping 1 you added yourself.")
        #expect(
            row(.dictation, "forgetLearned", SettingsPersonalisationFixtures.onlyLearned)?
                .explanation == "Forget 34 learned words. You have not added any of your own.")
    }

    @Test("describes the trade rather than counting nothing when there is nothing")
    func nothingLearnedStillExplainsTheButton() {
        let row = row(.dictation, "forgetLearned", SettingsPersonalisationFixtures.onlyAdded)
        #expect(row?.explanation?.contains("Words you added yourself stay") == true)
        #expect(row?.unavailability?.isEmpty == false)
        // Both are spoken, so the reason is never only a shade of grey.
        #expect(row?.accessibilityLabel.contains("stay") == true)
    }

    @Test("counts every part of what a reset takes, and says it cannot be undone")
    func resettingIsCountedInTheDialogue() {
        guard
            case .removal(let removal)? = row(
                .privacy, "resetPersonalisation", SettingsPersonalisationFixtures.plenty
            )?.control,
            let confirmation = removal.confirmation
        else {
            Issue.record("the reset row asks nothing")
            return
        }
        #expect(
            confirmation.message
                == "This removes 46 words from your dictionary (34 it learned, 12 you added "
                + "yourself) and 142 saved transcripts, and puts every preference back to its "
                + "default. It cannot be undone.")
        #expect(confirmation.title == "Reset personalisation?")
    }

    @Test("counts only the parts there are")
    func theDialogueLeavesOutWhatIsNotThere() {
        for counts in SettingsPersonalisationFixtures.every {
            guard
                case .removal(let removal)? = row(.privacy, "resetPersonalisation", counts)?
                    .control,
                let message = removal.confirmation?.message
            else {
                Issue.record("the reset row asks nothing")
                continue
            }
            #expect(!message.contains(" 0 "), "counts nothing: \(message)")
            #expect(message.hasSuffix("It cannot be undone."))
            if counts.isEmpty {
                #expect(message.contains("nothing of yours saved"))
            }
            for count in [counts.transcripts, counts.words] where count > 0 {
                #expect(message.contains("\(count)"), "does not count \(count)")
            }
        }
    }

    /// The button that removes something is never the one Return presses.
    @Test("never makes removing something the default answer")
    func theDefaultAnswerNeverRemovesAnything() {
        for counts in SettingsPersonalisationFixtures.every {
            for tab in SettingsTab.allCases {
                let pane = SettingsPresenter.pane(
                    for: tab, settings: .default, personalisation: counts)
                for case .removal(let removal) in pane.groups.flatMap(\.rows).map(\.control) {
                    guard let confirmation = removal.confirmation else { continue }
                    #expect(confirmation.defaultTitle == confirmation.cancelTitle)
                    #expect(confirmation.defaultTitle != confirmation.confirmTitle)
                    #expect(!confirmation.cancelTitle.isEmpty)
                }
            }
        }
    }

    /// The ellipsis is the only signal, before pressing, that a button asks before it acts.
    @Test("ends a button in an ellipsis exactly when it asks first")
    func theEllipsisMeansWhatItSays() {
        for counts in SettingsPersonalisationFixtures.every {
            for tab in SettingsTab.allCases {
                let pane = SettingsPresenter.pane(
                    for: tab, settings: .default, personalisation: counts)
                for case .removal(let removal) in pane.groups.flatMap(\.rows).map(\.control) {
                    #expect(
                        removal.title.hasSuffix("…") == (removal.confirmation != nil),
                        "\(removal.title) does not say whether it asks")
                    #expect(
                        (removal.confirmation != nil) == removal.reset.isConfirmed,
                        "\(removal.reset) asks in one place and not the other")
                }
            }
        }
    }

    /// Both levels have to be reachable, or the design has three levels and a story.
    @Test("puts each level where the design says it lives")
    func bothLevelsAreOnScreen() {
        var found: [SettingsTab: [SettingsReset]] = [:]
        for tab in SettingsTab.allCases {
            let pane = SettingsPresenter.pane(
                for: tab, settings: .default,
                personalisation: SettingsPersonalisationFixtures.plenty)
            for case .removal(let removal) in pane.groups.flatMap(\.rows).map(\.control) {
                found[tab, default: []].append(removal.reset)
            }
        }
        #expect(found == [.dictation: [.learnedWords], .privacy: [.everything]])
    }
}

// MARK: - Signing out

@Suite("Signing out")
struct SettingsSignOutCopyTests {
    /// Signing out takes nothing away, said on the Privacy tab where a user goes to find out.
    @Test("is said on the Privacy tab to leave everything where it is")
    func theTabSaysSigningOutKeepsEverything() {
        let pane = SettingsPresenter.pane(for: .privacy, settings: .default)
        let callout = pane.callout?.message
        #expect(callout?.contains("Signing out takes nothing away") == true)
        for kept in ["history", "dictionary", "settings"] {
            #expect(callout?.contains(kept) == true, "does not say \(kept) stays")
        }
        #expect(callout?.contains("resetting is the only thing that removes them") == true)
    }

    /// The promise says the text is not tied to the account, not that there is no account.
    @Test("the promise does not deny that there is an account")
    func thePromiseDoesNotDenyTheAccount() {
        #expect(!SettingsPresenter.privacyPromise.contains("no account"))
        #expect(SettingsPresenter.privacyPromise.contains("not tied to your account"))
    }
}

/// The clipboard holds a second copy of every dictation, so a full reset has to reach it.
@Suite("Resetting reaches the clipboard too")
struct SettingsResetClipboardTests {
    /// A reset promising a fresh install leaves no file holding a copy of every transcript.
    @Test("a full reset names the clipboard among what it removes")
    func everythingIncludesTheClipboard() {
        #expect(SettingsReset.everything.targets.contains(.clipboard))
    }

    /// Forgetting what was learned is about the dictionary and nothing else.
    @Test("forgetting learned words leaves the clipboard alone")
    func learnedWordsDoesNotTouchTheClipboard() {
        #expect(!SettingsReset.learnedWords.targets.contains(.clipboard))
    }
}
