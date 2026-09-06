public import UttrflowDictionary
public import UttrflowHistory
public import UttrflowClipboard

// MARK: - What can be undone

/// The three levels of forgetting that live on the Settings screen.
///
/// There are five levels altogether, and the other two are elsewhere on purpose:
/// reverting one correction belongs beside the correction, and removing one word
/// belongs beside the word. What is left here is what is about *everything* of a kind
/// or of a place, which is what a user goes looking for in Settings when the app has
/// started getting something reliably wrong.
///
/// ``learnedWords`` is the one that will actually be used. A few wrong corrections can
/// teach the dictionary to keep making the same mistake, and the honest cure is to throw
/// the inferences away — but throwing away the words the user deliberately taught it at
/// the same time would make the cure cost more than the illness, and they would live
/// with the illness instead.
public enum SettingsReset: Sendable, Equatable, Hashable {
    /// Everything Uttrflow worked out for itself. Hand-added words survive.
    case learnedWords
    /// Everything, back to a fresh install.
    case everything
    /// Every completion learned in one application, offered beside that application in the list for the reason reverting one correction is offered beside the correction.
    case suggestions(inApplication: String)
}

/// One thing a reset removes.
///
/// Split out from ``SettingsReset`` so that what a level *means* is decided here, in a
/// module a test can read, rather than in the app layer that happens to hold the stores.
/// The app layer is then a `switch` with no judgement in it.
public enum SettingsResetTarget: Sendable, Equatable {
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
    /// Every completion one application taught, leaving every other application's.
    case suggestions(inApplication: String)
    /// Every completion there is, which a fresh install has none of.
    case everySuggestion
}

extension SettingsReset {
    /// Everything this level removes, in order, and never two opinions about the dictionary.
    public var targets: [SettingsResetTarget] {
        switch self {
        case .learnedWords: [.learnedWords]
        case .everything: [.everyWord, .history, .clipboard, .everySuggestion, .preferences]
        case .suggestions(let application): [.suggestions(inApplication: application)]
        }
    }

    /// Whether the last dictation's words go too, which every reset that clears the transcripts does.
    public var forgetsTheLastDictation: Bool { targets.contains(.history) }

    /// Whether the user is asked first, which only what nothing brings back requires.
    public var isConfirmed: Bool {
        switch self {
        case .learnedWords, .suggestions: false
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

    /// The app the last dictation went into; the frontmost one, while Settings is open, is Uttrflow.
    public let lastDictationApp: SettingsApp?

    /// How many completions each application has taught, keyed by bundle identifier.
    public let suggestions: [String: Int]

    public init(
        learnedWords: Int, addedWords: Int, transcripts: Int,
        lastDictationApp: SettingsApp? = nil, suggestions: [String: Int] = [:]
    ) {
        self.learnedWords = learnedWords
        self.addedWords = addedWords
        self.transcripts = transcripts
        self.lastDictationApp = lastDictationApp
        self.suggestions = suggestions.reduce(into: [:]) { $0[$1.key.lowercased()] = $1.value }
    }

    /// How much one application has taught, which is what the button beside it will take.
    public func suggestions(from bundleIdentifier: String) -> Int {
        suggestions[bundleIdentifier.lowercased()] ?? 0
    }

    /// Every application that has taught the completions anything, so the list can name them.
    public var applicationsWithSuggestions: Set<String> {
        Set(suggestions.filter { $0.value > 0 }.keys)
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
    ///   - lastDictationApp: The app the last dictation went into, when one is known.
    ///   - suggestions: How many completions each application has taught.
    public init(
        entries: [DictionaryEntry], transcripts: Int, lastDictationApp: SettingsApp? = nil,
        suggestions: [String: Int] = [:]
    ) {
        self.init(
            learnedWords: entries.count(where: { $0.origin != .added }),
            addedWords: entries.count(where: { $0.origin == .added }),
            transcripts: transcripts,
            lastDictationApp: lastDictationApp, suggestions: suggestions)
    }

    /// A fresh install, and what a window shows before it has asked.
    public static let nothing = SettingsPersonalisation(
        learnedWords: 0, addedWords: 0, transcripts: 0)

    /// Every word, however it got there.
    public var words: Int { learnedWords + addedWords }

    /// Whether there is anything of the user's to remove at all.
    public var isEmpty: Bool { words == 0 && transcripts == 0 && applicationsWithSuggestions.isEmpty }
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

/// Where the completions this Mac has learned live, so a reset can reach them without this module holding any SQL.
public protocol SuggestionCorpus: Sendable {
    /// How many completions each application has taught, keyed by bundle identifier.
    func learnedSuggestions() async -> [String: Int]

    /// Forgets everything learned in one application.
    func forgetSuggestions(from bundleIdentifier: String) async throws

    /// Forgets every completion there is, which a fresh install has none of.
    func forgetEverySuggestion() async throws
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
    private let suggestions: (any SuggestionCorpus)?

    /// The corpus is optional because a build with tab-to-complete switched off at the wiring has none to reach.
    public init(
        dictionary: PersonalDictionaryStore,
        history: DictationHistoryStore,
        clipboard: ClipboardStore,
        suggestions: (any SuggestionCorpus)? = nil
    ) {
        self.dictionary = dictionary
        self.history = history
        self.clipboard = clipboard
        self.suggestions = suggestions
    }

    public func personalisation(keeping retention: Retention) async -> SettingsPersonalisation {
        // `records(keeping:)` rather than the raw file: it applies the promise, and
        // applies it to the disk as well, so the number shown is the number that is
        // there to be removed and not a count of things already promised deleted.
        let kept = await history.records(keeping: retention)
        return await SettingsPersonalisation(
            entries: dictionary.allEntries(),
            transcripts: kept.count,
            lastDictationApp: Self.lastApp(in: kept),
            suggestions: suggestions?.learnedSuggestions() ?? [:])
    }

    /// The most recent dictation that named the app it went into, which is the app an override is about.
    static func lastApp(in records: [DictationRecord]) -> SettingsApp? {
        let named = records.filter { $0.applicationIdentifier?.isEmpty == false }
        guard let latest = named.max(by: { $0.when < $1.when }),
            let bundle = latest.applicationIdentifier
        else { return nil }
        return SettingsApp(bundleIdentifier: bundle, name: latest.applicationName)
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
        case .suggestions(let application):
            try await suggestions?.forgetSuggestions(from: application)
        case .everySuggestion: try await suggestions?.forgetEverySuggestion()
        case .preferences: break
        }
    }
}
