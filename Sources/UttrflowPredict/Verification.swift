/// What the gates decided about one candidate, which is the last word on whether it may be shown.
public enum Verdict: Sendable, Equatable {
    /// The machine itself says it exists, so nothing below may interfere with it.
    case attested
    /// Nothing objected, so it stands in the form the corpus offered it.
    case plausible
    /// It is wrong, and this is the form to offer instead.
    case corrected(String)
    /// It is wrong and nothing near it is right, so it is not offered at all.
    case rejected

    /// Whether the machine vouched for it, which is all a verification over budget may still show.
    public var isAttested: Bool { self == .attested }

    /// Whether anything at all may be drawn from it.
    public var allowsOffering: Bool { self != .rejected }
}

/// Scores how likely a candidate is where it stands, which is the one thing frequency cannot say.
public protocol CandidateScoring: Sendable {
    /// Whether the model can answer at once, since a keystroke may never wait on one still loading.
    var isReady: Bool { get async }

    /// The whole candidate line's mean log-likelihood per token past what is typed, in one pass, abandoned when cancelled.
    func logLikelihood(of candidate: String, following context: String) async -> Double?
}

/// Marks a candidate wrong wherever it is remembered, so it stops accruing weight.
public protocol SupersessionRecording: Sendable {
    /// Records that one text is replaced by another, which is what stops it being proposed again.
    func recordSupersession(of text: String, by replacement: String, in surface: Surface) async

    /// Records that one text is wrong with nothing on this machine to put in its place.
    func recordRejection(of text: String, in surface: Surface) async
}

/// What the model managed to say about a candidate inside the budget.
public enum Plausibility: Sendable, Equatable {
    /// It scored the candidate, and this is the score.
    case scored(Double)
    /// It is up but had nothing to say, so the statistical tiers answer alone.
    case silent
    /// The budget ran out, so only what the machine already attested may be shown.
    case overBudget
}

/// What the machine says the next word may be, which decides whether the model writes freely, chooses, or is not asked. See `Docs/predict-agent.md`, A3.
public enum ArgumentOptions: Equatable, Sendable {
    /// Anything: the word is one the command reads as text, or the machine has not answered yet.
    case open
    /// One of these, each a whole word beginning as the typed word does, shortest first.
    case among([String])
    /// Nothing: the word is of a kind the machine lists, and nothing listed begins as it was typed.
    case none
}

/// Correctness in ordered gates, because frequency says what the user does rather than what is right.
public enum Verification {
    /// How long a verdict waits for the model before a candidate stands on the machine's word alone.
    public static let budgetInMilliseconds = 7_000

    /// How unlikely, per token, a candidate may be before the model's objection counts, set from `uttrflow-bakeoff score`.
    public static let plausibilityFloor = -6.0

    /// The dearest slip a correction may explain away, which is one plain insertion or deletion.
    public static let correctionCeiling = TypoModel.indelCost

    /// The program whose subcommands and aliases the machine is asked about by name.
    static let gitCommand = "git"

    /// The verdict the gates reach together, from what the machine knows and whether the model objects.
    public static func verdict(word: String, known: Set<String>, modelObjects: Bool) -> Verdict {
        guard !attests(word, known) else { return .attested }
        if let neighbour = nearestNeighbour(of: word, among: known) { return .corrected(neighbour) }
        return modelObjects ? .rejected : .plausible
    }

    /// Whether the machine vouches for a word, ignoring case, so a capitalised first letter still attests.
    public static func attests(_ word: String, _ known: Set<String>) -> Bool {
        let lowered = word.lowercased()
        return known.contains { $0.lowercased() == lowered }
    }

    /// Whether the model finds a candidate too unlikely to stand, false whenever it has no opinion.
    public static func objects(to plausibility: Plausibility) -> Bool {
        guard case .scored(let score) = plausibility else { return false }
        return score < plausibilityFloor
    }

    /// The nearest name the machine knows, when one slip cheap enough explains the difference.
    public static func nearestNeighbour(of word: String, among known: Set<String>) -> String? {
        let typed = Array(word.utf8)
        guard FuzzyMatch.budget(forQueryOfLength: typed.count) > 0 else { return nil }
        let width = FuzzyMatch.maskWidth(forQueryOfLength: typed.count, within: 1)
        let queryMask = FuzzyMatch.mask(typed)

        var best: String?
        var bestScore = -Double.infinity
        let lowered = word.lowercased()
        for candidate in known.sorted() {
            // A difference only of case is not a typo, so it is never corrected or superseded.
            guard candidate.lowercased() != lowered else { continue }
            let bytes = Array(candidate.utf8)
            let mask = FuzzyMatch.mask(bytes.prefix(width))
            guard FuzzyMatch.couldMatch(query: queryMask, candidate: mask, within: 1) else { continue }
            let score = TypoModel.logLikelihood(typed: word, meant: candidate)
            guard score >= -correctionCeiling, score > bestScore else { continue }
            best = candidate
            bestScore = score
        }
        return best
    }

    /// Whether the kinds name everything there is, as programs and their verbs do and paths and branches never do.
    static func isClosedVocabulary(_ kinds: [EnvironmentKind]) -> Bool {
        !kinds.contains { kind in
            switch kind {
            case .branch, .entries, .directories: true
            case .executable, .alias, .subcommand, .gitAlias: false
            }
        }
    }

    /// One name to look up among some kinds, and what stands before it in the word when the word is a path.
    public struct Lookup: Equatable, Sendable {
        /// The name looked up: the word, or the last name of a path.
        public let word: String
        /// The kinds whose values may vouch for it.
        public let kinds: [EnvironmentKind]
        /// The path before the name, ending in its slash, which a candidate puts back in front of a value.
        public let prefix: String

        init(_ word: String, _ kinds: [EnvironmentKind], prefix: String = "") {
            self.word = word
            self.kinds = kinds
            self.prefix = prefix
        }
    }

    /// What the machine could vouch for in a word the model wrote; any one lookup vouching lets the word stand.
    public struct Attestation: Equatable, Sendable {
        public let lookups: [Lookup]
    }

    /// The characters that make a word a quotation, an expansion, an assignment, an address or a mode, none of which a listing can deny.
    private static let freeCharacters: Set<Character> = [
        "\"", "'", "$", "*", "?", "{", "}", "=", ":", "`", "+",
    ]

    /// What could vouch for a generated word, absent where any word is allowed: a flag, a number, a quotation, or a word the command reads as text.
    static func attestation(for token: CompletionToken) -> Attestation? {
        guard !isFree(token.token) else { return nil }
        return lookups(for: token)
    }

    /// What the next word may be chosen from: the lookups for a word begun or not yet begun, absent where the word may be anything.
    static func choices(for token: CompletionToken) -> Attestation? {
        let word = token.token
        // A word not begun is chosen from what the shape lists; a lone dot begins a hidden file, but for a directory may be `..`.
        if word.isEmpty { return lookups(for: token) }
        if word == "." { return LineShape.of(token).kind == .directory ? nil : lookups(for: token) }
        guard !isFree(word) else { return nil }
        // A path ending in its slash is open at a name not yet begun, so what is under the path is offered.
        guard word.hasSuffix("/") else { return lookups(for: token) }
        let under = word == "/" ? "/" : String(word.dropLast())
        let kind = LineShape.of(token).kind
        let below = Lookup(
            "", [kind == .directory ? .directories(under: under) : .entries(under: under)], prefix: word)
        // Where a branch is wanted, the slash may be a branch's own, so the branches beginning this way are offered too.
        return Attestation(lookups: kind == .branch ? [Lookup(word, [.branch]), below] : [below])
    }

    /// The most values the model is offered to choose among, since each costs prompt and a directory may hold hundreds.
    public static let mostChoices = 40

    /// The typed line finished by each of the machine's values, which is what every alternative to a chosen word is.
    public static func completed(_ typed: String, with choices: [String]) -> [String] {
        let word = CompletionToken(typed)?.token ?? ""
        let head = String(typed.dropLast(word.count))
        return choices.map { head + $0 }
    }

    /// The lookups the line's shape gives a word, absent for one the command reads as text.
    private static func lookups(for token: CompletionToken) -> Attestation? {
        let word = token.token
        let shape = LineShape.of(token)
        // A path is looked up where it points, narrowed to directories by `cd` and its kin; a word read as text is never a path, so `deploy/api` stands.
        if word.contains("/"), shape.kind != .free {
            guard let path = path(word, directoriesOnly: shape.kind == .directory) else { return nil }
            return shape.kind == .branch
                ? Attestation(lookups: [Lookup(word, [.branch]), path]) : Attestation(lookups: [path])
        }
        switch shape.kind {
        case .program: return Attestation(lookups: [Lookup(word, [.executable, .alias])])
        case .subcommand(let program):
            return Attestation(lookups: [
                Lookup(word, [.subcommand(of: program)] + (program == gitCommand ? [.gitAlias] : []))
            ])
        case .directory: return Attestation(lookups: [Lookup(word, [.directory])])
        case .file: return Attestation(lookups: [Lookup(word, [.file])])
        // A branch is one ref among many: `HEAD~1`, a tag, a commit hash and `origin/main` are git's to accept, not the list's to deny.
        case .branch: return isRef(word) ? nil : Attestation(lookups: [Lookup(word, [.branch])])
        // A dotfile names one file here and nothing else; any other word may be one the command reads as text.
        case .free: return word.hasPrefix(".") ? Attestation(lookups: [Lookup(word, [.file])]) : nil
        }
    }

    /// What the machine may offer to finish a word: what could vouch for it, and for a free word the names here, which a shell offers too.
    static func offerings(for token: CompletionToken) -> [Lookup] {
        if let attestation = attestation(for: token) { return attestation.lookups }
        return isFree(token.token) ? [] : [Lookup(token.token, [.file])]
    }

    /// Whether a generated word may stand: the machine has not answered, or it names the word.
    public static func stands(_ word: String, known: Set<String>?) -> Bool {
        guard let known else { return true }
        return attests(word, known)
    }

    /// A path's last name looked up under the directory before it, absent for a word without a slash or one naming here or a parent.
    private static func path(_ word: String, directoriesOnly: Bool) -> Lookup? {
        guard word.contains("/") else { return nil }
        var components = word.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        // A trailing slash says the name is a directory and completes it.
        var trailing = false
        while components.count > 1, components.last == "" {
            components.removeLast()
            trailing = true
        }
        guard let name = components.popLast(), !name.isEmpty, name != ".", name != ".." else { return nil }
        let under = components.isEmpty ? "." : (components == [""] ? "/" : components.joined(separator: "/"))
        let prefix = components.isEmpty ? "" : components.joined(separator: "/") + "/"
        let kind: EnvironmentKind =
            directoriesOnly || trailing ? .directories(under: under) : .entries(under: under)
        return Lookup(name, [kind], prefix: prefix)
    }

    /// The words of a whole line past what was typed, each with what precedes it; a word the typing began and the model finished is the model's.
    static func words(of line: String, addedAfter typed: String) -> [CompletionToken] {
        var words: [CompletionToken] = []
        var start = line.startIndex
        while start < line.endIndex {
            guard line[start] != " " else {
                start = line.index(after: start)
                continue
            }
            let end = line[start...].firstIndex(of: " ") ?? line.endIndex
            if line.distance(from: line.startIndex, to: end) > typed.count {
                words.append(
                    CompletionToken(leading: String(line[..<start]), token: String(line[start..<end])))
            }
            start = end
        }
        return words
    }

    /// Whether a word could be anything at all: a flag, a number, here, the parent or home, or one the shell would rewrite.
    private static func isFree(_ word: String) -> Bool {
        word.hasPrefix("-") || word == "." || word == ".." || (word.hasPrefix("~") && !word.contains("/"))
            || word.allSatisfy(\.isNumber)
            || word.contains(where: freeCharacters.contains)
    }

    /// Whether a word names a git ref no branch list holds: a `HEAD` form, a relative ref, or a commit hash.
    private static func isRef(_ word: String) -> Bool {
        word.hasPrefix("HEAD") || word.contains("~") || word.contains("^")
            || (word.count >= 7 && word.allSatisfy(\.isHexDigit))
    }

    /// What could vouch for a word, which the command and the word's place in it decide; nothing for a word the command reads as text.
    static func attestingKinds(for token: CompletionToken) -> [EnvironmentKind] {
        attestation(for: token)?.lookups.flatMap(\.kinds) ?? []
    }
}
