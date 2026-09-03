import Foundation
@testable import UttrflowClipboard
import UttrflowCore
import UttrflowDictionary
import UttrflowHistory
import UttrflowSettings
import Testing

@testable import UttrflowUX

// MARK: - Fixtures

/// Every shape the counts can take.
///
/// Held in one place and swept over by every suite that reads a sentence, because a
/// count has a different wording for each of these and the ones nobody thought about —
/// one of each, none at all — are exactly the ones that ship reading "1 words".
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

/// A directory of its own for each test, so nothing here can reach the dictionary or the
/// history of whoever is running it.
private func inATemporaryDirectory(
    _ body: (URL) async throws -> Void
) async throws {
    let directory = URL.temporaryDirectory.appending(
        path: "uttrflow-reset-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer {
        // Permissions are put back first: a test that made the directory read-only to
        // provoke a failure would otherwise leave a directory nothing can remove.
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path())
        try? FileManager.default.removeItem(at: directory)
    }
    try await body(directory)
}

private func entry(_ word: String, _ origin: WordOrigin) -> DictionaryEntry {
    DictionaryEntry(word: word, origin: origin, firstSeen: Date(timeIntervalSince1970: 0))
}

/// Two of everything, so a reset that kept the wrong kind is visible rather than
/// ambiguous.
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

    /// Two opinions about the dictionary in one reset would mean the count the user was
    /// shown described only the first of them.
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

    /// Being asked is itself a cost: a dialogue in front of the recoverable action
    /// teaches people to dismiss dialogues, and the one in front of the irreversible
    /// action is then dismissed too.
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

    /// Transcripts the user was already told are gone must not be offered up for
    /// deletion a second time: the number shown has to be the number that is there.
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

    /// The heart of the third level, asserted rather than assumed: the words the user
    /// typed in survive, everything the app guessed does not, and the history is not
    /// touched at all.
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

    /// A disk that refuses is not the same as a reset that happened, and the user is the
    /// one person who cannot tell the difference by looking.
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

    /// The one the requirement turns on: a question that is dismissed is a question that
    /// removed nothing.
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

    /// A dialogue clears itself as it closes, and whether that lands before or after the
    /// button's own action is not ours to decide. The answer must survive either order,
    /// or a reset the user asked for is silently not carried out.
    @Test("the answer survives the question being cleared first")
    func answeringDoesNotDependOnTheDialogueClosingLast() throws {
        var session = session()
        let removal = try #require(button(.privacy, "resetPersonalisation", in: session))
        session.request(removal)

        session.dismissRemoval()
        #expect(session.confirm(removal) == .everything)
    }

    /// Only a removal that asks can be answered. A button with no question behind it
    /// cannot be talked into acting as though there had been one.
    @Test("refuses to confirm something that was never asked")
    func nothingUnaskedCanBeConfirmed() throws {
        var session = session()
        let forget = try #require(button(.dictation, "forgetLearned", in: session))
        #expect(session.confirm(forget) == nil)
    }

    /// The row is greyed for the same reason the request is refused, from the same
    /// function, so a button drawn operable cannot decline afterwards.
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

    /// The one thing a user cannot be left to assume is whether the words they asked to
    /// delete are still there.
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

    /// The wording the design asks for, with real numbers in it, before the button is
    /// pressed and without a dialogue to carry it.
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

    /// Nothing is destructive by accident: the button that removes something is never
    /// the one Return presses.
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

    /// The ellipsis is the platform's promise that a button asks before it acts, and it
    /// is the only signal the user gets before they press.
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
    /// Signing out takes nothing away, and the Privacy tab is where a user goes to find
    /// that out. The old promise claimed there was no account at all, which stopped
    /// being true the day one shipped.
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

    @Test("the promise no longer denies that there is an account")
    func thePromiseDoesNotDenyTheAccount() {
        #expect(!SettingsPresenter.privacyPromise.contains("no account"))
        #expect(SettingsPresenter.privacyPromise.contains("not tied to your account"))
    }
}

/// The clipboard holds a second copy of every dictation, and the reset did not reach it.
@Suite("Resetting reaches the clipboard too")
struct SettingsResetClipboardTests {
    /// "Puts Uttrflow back to a fresh install: your dictionary, your history and every
    /// preference on this screen" — and it left, untouched, a file containing a full copy
    /// of every transcript the user had ever spoken, reachable from the panel with one
    /// shortcut. On a product whose central promise is about where your words live, a
    /// reset that says everything is gone and leaves them is the worst kind of wrong.
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
