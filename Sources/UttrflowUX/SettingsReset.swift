public import UttrflowDictionary
public import UttrflowHistory
public import UttrflowClipboard

// MARK: - What can be undone

/// The two levels of forgetting that live on the Settings screen.
///
/// There are four levels altogether, and the other two are elsewhere on purpose:
/// reverting one correction belongs beside the correction, and removing one word
/// belongs beside the word. What is left here is the pair that is about *everything* of
/// a kind, which is the pair a user goes looking for in Settings when the app has
/// started getting something reliably wrong.
///
/// ``learnedWords`` is the one that will actually be used. A few wrong corrections can
/// teach the dictionary to keep making the same mistake, and the honest cure is to throw
/// the inferences away — but throwing away the words the user deliberately taught it at
/// the same time would make the cure cost more than the illness, and they would live
/// with the illness instead.
public enum SettingsReset: String, Sendable, Equatable, CaseIterable {
    /// Everything Uttrflow worked out for itself. Hand-added words survive.
    case learnedWords
    /// Everything, back to a fresh install.
    case everything
}

/// One thing a reset removes.
///
/// Split out from ``SettingsReset`` so that what a level *means* is decided here, in a
/// module a test can read, rather than in the app layer that happens to hold the stores.
/// The app layer is then a `switch` with no judgement in it.
public enum SettingsResetTarget: Sendable, Equatable, CaseIterable {
    /// The words Uttrflow inferred, leaving the ones the user typed in.
    case learnedWords
    /// The dictionary in full, hand-added words included.
    case everyWord
    /// Every saved transcript.
    case history
    /// Every preference on this screen, back to its default.
    case preferences
    /// Everything the clipboard kept — which includes a second copy of every dictation.
    ///
    /// Its own target rather than part of ``history`` because the two are separate files
    /// with separate lifetimes; naming it here is what stops a reset that says "a fresh
    /// install" leaving every transcript the user ever spoke on the disk.
    case clipboard
}

extension SettingsReset {
    /// Everything this level removes, in the order it is removed.
    ///
    /// ``learnedWords`` and ``everyWord`` are deliberately never both present: they are
    /// two different opinions about the dictionary, and running both would mean the
    /// count shown to the user described only the first.
    public var targets: [SettingsResetTarget] {
        switch self {
        case .learnedWords: [.learnedWords]
        case .everything: [.everyWord, .history, .clipboard, .preferences]
        }
    }

    /// Whether the user is asked before anything goes.
    ///
    /// Forgetting what was learned is not: it costs a few days of the app noticing
    /// things again, and it is recovered simply by carrying on using the app. A reset
    /// is, because nothing brings a year of history back.
    public var isConfirmed: Bool {
        switch self {
        case .learnedWords: false
        case .everything: true
        }
    }
}

// MARK: - What there is to remove

/// How much of this user is in the app, counted.
///
/// Held so that a destructive action can say what it will take before it takes it. A
/// count is the difference between a warning the user can act on and a shrug: "Forget 34
/// learned words, keeping 12 you added yourself" is a decision, "Are you sure?" is not.
///
/// The split between learned and added is exactly the split
/// ``PersonalDictionaryStore/removeLearned()`` makes, and is taken from the same field,
/// so the number shown and the number removed cannot drift apart.
public struct SettingsPersonalisation: Sendable, Equatable {
    /// Words Uttrflow inferred — both the ones it learned from a correction and the ones
    /// it merely observed. The user cannot be expected to know which mechanism guessed
    /// wrong, so neither can they be asked to choose between them.
    public let learnedWords: Int

    /// Words the user typed in themselves.
    public let addedWords: Int

    /// Transcripts still inside the retention window, which is all there are to see.
    public let transcripts: Int

    public init(learnedWords: Int, addedWords: Int, transcripts: Int) {
        self.learnedWords = learnedWords
        self.addedWords = addedWords
        self.transcripts = transcripts
    }

    /// Counts a dictionary as it stands.
    ///
    /// Anything that is not ``WordOrigin/added`` is the app's own inference, which is
    /// the same test ``PersonalDictionaryStore/removeLearned()`` applies. Written as a
    /// negation for that reason: a fourth origin invented later is the app's until
    /// somebody says otherwise, and counting it as the user's would understate what a
    /// reset takes.
    ///
    /// - Parameters:
    ///   - entries: Every word in the dictionary.
    ///   - transcripts: How many dictations are still kept.
    public init(entries: [DictionaryEntry], transcripts: Int) {
        self.init(
            learnedWords: entries.count(where: { $0.origin != .added }),
            addedWords: entries.count(where: { $0.origin == .added }),
            transcripts: transcripts)
    }

    /// A fresh install, and what a window shows before it has asked.
    public static let nothing = SettingsPersonalisation(
        learnedWords: 0, addedWords: 0, transcripts: 0)

    /// Every word, however it got there.
    public var words: Int { learnedWords + addedWords }

    /// Whether there is anything of the user's to remove at all.
    public var isEmpty: Bool { words == 0 && transcripts == 0 }
}

// MARK: - Who does the removing

/// A reset was asked for and could not be finished.
///
/// Carries nothing. There is one thing worth saying to a user whose disk refused, it
/// depends on which reset they asked for rather than on what the disk said, and
/// ``SettingsEditor`` is where the words for a refusal already live.
public struct SettingsResetFailure: Error, Sendable, Equatable {
    public init() {}
}

/// Where this user's personalisation actually lives.
///
/// A boundary rather than the stores themselves, so that what a reset *means* stays
/// decided in this module while the files stay owned by theirs. It is also what lets the
/// window be driven, end to end, by a test that never touches Application Support.
public protocol SettingsPersonalisationStore: Sendable {
    /// What there is to remove, right now.
    ///
    /// - Parameter retention: The promise in force, so that transcripts the user was
    ///   told are already gone are not counted as though they were still there.
    /// - Returns: The counts to put in front of the user.
    func personalisation(keeping retention: Retention) async -> SettingsPersonalisation

    /// Removes everything a level names.
    ///
    /// - Parameter reset: The level the user asked for.
    /// - Throws: ``SettingsResetFailure`` when the disk refused, so the user is told
    ///   their words are still here rather than left assuming they are not.
    func carryOut(_ reset: SettingsReset) async throws(SettingsResetFailure)
}

/// The real one: the dictionary file and the history file on this Mac.
///
/// It contains no opinion of its own. ``SettingsReset/targets`` says what to remove and
/// each store says what removing it means — in particular
/// ``PersonalDictionaryStore/removeLearned()`` is the single definition of "what was
/// learned", and this deliberately does not hold a second one.
public struct FilePersonalisationStore: SettingsPersonalisationStore {
    private let dictionary: PersonalDictionaryStore
    private let history: DictationHistoryStore
    private let clipboard: ClipboardStore

    public init(
        dictionary: PersonalDictionaryStore,
        history: DictationHistoryStore,
        clipboard: ClipboardStore
    ) {
        self.dictionary = dictionary
        self.history = history
        self.clipboard = clipboard
    }

    public func personalisation(keeping retention: Retention) async -> SettingsPersonalisation {
        // `records(keeping:)` rather than the raw file: it applies the promise, and
        // applies it to the disk as well, so the number shown is the number that is
        // there to be removed and not a count of things already promised deleted.
        await SettingsPersonalisation(
            entries: dictionary.allEntries(),
            transcripts: history.records(keeping: retention).count)
    }

    public func carryOut(_ reset: SettingsReset) async throws(SettingsResetFailure) {
        do {
            for target in reset.targets { try await remove(target) }
        } catch {
            // Every store fails the same way and for the same reason — it could not
            // write — and the user's next move is the same whichever one it was.
            throw SettingsResetFailure()
        }
    }

    /// One target, handed to whichever store owns it.
    ///
    /// Preferences are the one target no store here holds: they belong to
    /// ``SettingsSession``, which puts them back itself and hands the result to be
    /// saved. Named in the `switch` rather than left to a `default` so that a fifth
    /// target cannot be added and silently ignored.
    private func remove(_ target: SettingsResetTarget) async throws {
        switch target {
        case .learnedWords: try await dictionary.removeLearned()
        case .everyWord: try await dictionary.removeEverything()
        case .history: try await history.deleteEverything()
        // `forgetEverything`, not `deleteEverything(keeping:)`: the latter spares pinned
        // clips on purpose, because "Clear clipboard" is a tidy-up. This button says a
        // fresh install, and a fresh install has nothing pinned either.
        case .clipboard: try await clipboard.forgetEverything()
        case .preferences: break
        }
    }
}
