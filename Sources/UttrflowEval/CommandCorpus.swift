// Command-key utterances scored for recall and false execution, per command and per document. See `Docs/commands.md`.
public import UttrflowCore

/// Whether a command-key utterance asks for its command, or says the phrase as part of something else.
public enum CommandCaseKind: String, Sendable, Equatable, CaseIterable, Codable {
    /// The command phrase alone, in a document where the command applies: it must run.
    case command
    /// The phrase inside a longer utterance: it must not run.
    case embedded
    /// The phrase alone, in a document where the command does not apply: it must not run.
    case elsewhere
}

/// One utterance said under the command key, with the command it names and whether that command should run.
public struct CommandCase: Sendable, Equatable {
    /// The `spoken-commands.json` row the phrase belongs to.
    public let commandID: String
    public let kind: CommandCaseKind
    public let utterance: String
    /// The document the selection is in, which decides where a command applies.
    public let documentName: String

    /// Whether running a command here is right.
    public var shouldRun: Bool { kind == .command }

    /// The app as the command sees it: one selected word at the start of a line.
    public var target: AppContext {
        AppContext(documentName: documentName, selectedText: "Plan", precedingText: "")
    }
}

extension EvaluationCorpus {
    /// Documents where a Markdown command applies.
    static let commandDocuments = ["notes.md", "README.markdown"]
    /// Documents where it does not, so the same phrase alone must change nothing.
    static let otherDocuments = ["main.swift", "Untitled", "report.txt", "index.html", "notes.rtf"]

    /// Ways a recogniser writes a phrase said alone: case and a closing mark vary, the words do not.
    private static let surfaces: [@Sendable (String) -> String] = [
        { $0 }, { $0.capitalized }, { $0.capitalized + "." }, { $0.uppercased() }, { $0 + "!" },
    ]

    /// Sentences that say a command phrase as content; every one must leave the selection alone.
    private static let embeddings: [@Sendable (String) -> String] = [
        { "make the \($0) bigger" }, { "I said \($0) earlier" }, { "\($0) and then send it" },
        { "not \($0)" }, { "what does \($0) do" },
    ]

    /// Every command-key case, 10 that must run and 10 that must not for each Markdown command.
    public static let commandCases: [CommandCase] = SpokenCommands.markdown.flatMap { row in
        let phrase = row.words.joined(separator: " ")
        let runs = commandDocuments.flatMap { document in
            surfaces.map {
                CommandCase(commandID: row.id, kind: .command, utterance: $0(phrase), documentName: document)
            }
        }
        let embedded = embeddings.map {
            CommandCase(commandID: row.id, kind: .embedded, utterance: $0(phrase), documentName: "notes.md")
        }
        let elsewhere = otherDocuments.map {
            CommandCase(commandID: row.id, kind: .elsewhere, utterance: phrase, documentName: $0)
        }
        return runs + embedded + elsewhere
    }
}

/// How a command reader did over the command corpus: recall per command, and every run that should not have happened.
public struct CommandReport: Sendable, Equatable {
    /// One command's figures.
    public struct Row: Sendable, Equatable {
        public let commandID: String
        /// Cases that must run, and how many did.
        public let wanted: Int
        public let ran: Int
        /// Cases that must not run, and how many did anyway.
        public let content: Int
        public let falseRuns: Int

        public var recall: Double { wanted == 0 ? 1 : Double(ran) / Double(wanted) }
    }

    public let rows: [Row]
    /// The cases that ran when they should not have, for the report to name.
    public let falseExecutions: [CommandCase]
    /// The cases that should have run and did not.
    public let missed: [CommandCase]

    /// Scores `reads`, which returns the edit a command would make or nil when none runs.
    public init(
        cases: [CommandCase] = EvaluationCorpus.commandCases,
        reads: (String, AppContext) -> String?
    ) {
        let ran = cases.map { reads($0.utterance, $0.target) != nil }
        let scored = zip(cases, ran)
        falseExecutions = scored.filter { !$0.0.shouldRun && $0.1 }.map(\.0)
        missed = scored.filter { $0.0.shouldRun && !$0.1 }.map(\.0)
        var order: [String] = []
        for testCase in cases where !order.contains(testCase.commandID) { order.append(testCase.commandID) }
        rows = order.map { id in
            let mine = scored.filter { $0.0.commandID == id }
            return Row(
                commandID: id,
                wanted: mine.count { $0.0.shouldRun }, ran: mine.count { $0.0.shouldRun && $0.1 },
                content: mine.count { !$0.0.shouldRun }, falseRuns: mine.count { !$0.0.shouldRun && $0.1 })
        }
    }

    /// False runs by document, so one where commands should never apply is read on its own.
    public var falseRunsByDocument: [String: Int] {
        Dictionary(grouping: falseExecutions, by: \.documentName).mapValues(\.count)
    }

    /// The release gate: every Markdown command rewrites the selection, so the false-execution budget is zero.
    public var passesGate: Bool {
        falseExecutions.isEmpty && rows.allSatisfy { $0.recall >= Self.recallFloor }
    }

    /// The least recall a command may have; every surface in the corpus is one the recogniser writes.
    public static let recallFloor = 1.0
}
