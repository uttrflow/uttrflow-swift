// Forgetting: the levels the Settings screen offers, what each removes, and who removes it.
public import UttrflowDictionary
public import UttrflowHistory
public import UttrflowClipboard

// MARK: - What can be undone

/// The levels of forgetting Settings offers: everything of a kind, or everything of a place.
public enum SettingsReset: Sendable, Equatable, Hashable {
    /// Everything Uttrflow worked out for itself. Hand-added words survive.
    case learnedWords
    /// Everything, back to a fresh install.
    case everything
    /// Every completion learned in one application, offered beside that application in the list.
    case suggestions(inApplication: String)
}

/// One thing a reset removes, so what a level means is decided here and not in the app layer.
public enum SettingsResetTarget: Sendable, Equatable {
    /// The words Uttrflow inferred, leaving the ones the user typed in.
    case learnedWords
    /// The dictionary in full, hand-added words included.
    case everyWord
    /// Every saved transcript.
    case history
    /// Every preference on this screen, back to its default.
    case preferences
    /// Everything the clipboard kept, which is a separate file holding a copy of every dictation.
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

/// How much of this user is in the app, counted, so a destructive button can say what it takes.
public struct SettingsPersonalisation: Sendable, Equatable {
    /// Words Uttrflow inferred, whether from a correction or merely from watching.
    public let learnedWords: Int

    /// Words the user typed in themselves.
    public let addedWords: Int

    /// Transcripts still inside the retention window, which is all there are to see.
    public let transcripts: Int

    /// The app the last dictation went into; the frontmost one, while Settings is open, is Uttrflow.
    public let lastDictationApp: SettingsApp?

    /// How many completions each application has taught, keyed by bundle identifier.
    public let suggestions: [String: Int]

    /// Takes the counts as given, lower-casing bundle identifiers so a lookup cannot miss.
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

    /// Counts a dictionary as it stands, calling anything not ``WordOrigin/added`` the app's own.
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

/// A reset could not be finished; ``SettingsEditor`` holds the sentence that says so.
public struct SettingsResetFailure: Error, Sendable, Equatable {
    /// The failure carries nothing, so there is nothing to give it.
    public init() {}
}

/// Where learned completions live, so a reset reaches them without this module holding any SQL.
public protocol SuggestionCorpus: Sendable {
    /// How many completions each application has taught, keyed by bundle identifier.
    func learnedSuggestions() async -> [String: Int]

    /// Forgets everything learned in one application.
    func forgetSuggestions(from bundleIdentifier: String) async throws

    /// Forgets every completion there is, which a fresh install has none of.
    func forgetEverySuggestion() async throws
}

/// Where this user's personalisation lives, as a boundary a test can drive without any files.
public protocol SettingsPersonalisationStore: Sendable {
    /// What there is to remove now, counted under the retention promise in force.
    func personalisation(keeping retention: Retention) async -> SettingsPersonalisation

    /// Removes everything a level names, throwing ``SettingsResetFailure`` when the disk refuses.
    func carryOut(_ reset: SettingsReset) async throws(SettingsResetFailure)
}

/// The real store: this Mac's files, holding no opinion the stores themselves do not.
public struct FilePersonalisationStore: SettingsPersonalisationStore {
    private let dictionary: PersonalDictionaryStore
    private let history: DictationHistoryStore
    private let clipboard: ClipboardStore
    private let suggestions: (any SuggestionCorpus)?

    /// The corpus is optional: a build with tab-to-complete unwired has none to reach.
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

    /// Counts the dictionary, the transcripts still inside the promise, and the completions.
    public func personalisation(keeping retention: Retention) async -> SettingsPersonalisation {
        // `records(keeping:)` applies the promise to the disk too, so the count is what is there.
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

    /// Hands each of the level's targets to the store that owns it.
    public func carryOut(_ reset: SettingsReset) async throws(SettingsResetFailure) {
        do {
            for target in reset.targets { try await remove(target) }
        } catch {
            // Every store fails for the same reason, and the user's next move is the same.
            throw SettingsResetFailure()
        }
    }

    /// One target, handed to whichever store owns it; ``SettingsSession`` owns the preferences.
    private func remove(_ target: SettingsResetTarget) async throws {
        switch target {
        case .learnedWords: try await dictionary.removeLearned()
        case .everyWord: try await dictionary.removeEverything()
        case .history: try await history.deleteEverything()
        // `forgetEverything` takes pinned clips too, which is what a fresh install means.
        case .clipboard: try await clipboard.forgetEverything()
        case .suggestions(let application):
            try await suggestions?.forgetSuggestions(from: application)
        case .everySuggestion: try await suggestions?.forgetEverySuggestion()
        case .preferences: break
        }
    }
}
