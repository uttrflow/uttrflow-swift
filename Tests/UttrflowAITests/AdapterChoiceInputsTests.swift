// Tests that the destination's formatter is chosen from the caret situation alone. See `Docs/adapters.md`, section 2.

import Foundation
import Testing
import UttrflowCore
import UttrflowDictionary

@testable import UttrflowAI

/// A persona biases words, never the choice of formatter: a month of SQL must not make prose into SQL.
@Suite("Adapter choice reads only the caret situation and the utterance")
struct AdapterChoiceInputsTests {
    private static let now = Date(timeIntervalSince1970: 1_700_000_000)
    private static let today = EvidenceRow.day(of: now)

    /// One person's learned state: their dictionary, their profile, and the ledger fifty earlier dictations wrote.
    struct Persona: Sendable, CustomStringConvertible {
        let name: String
        let entries: [DictionaryEntry]
        let profile: UserProfile
        let evidence: [EvidenceRow]
        var description: String { name }
    }

    /// The ledger fifty earlier dictations into `destination` leave, as the app records them on landing.
    private static func history(
        of texts: [String], into destination: Destination, using entries: [DictionaryEntry]
    ) -> [EvidenceRow] {
        (0..<50).flatMap { index in
            let text = texts[index % texts.count]
            let day = today - 50 + index
            let used = entries.filter { text.contains($0.word) }
                .map { EvidenceRow(kind: .use, subject: $0.id.uuidString, day: day, provenance: .dictation) }
            return used + StyleSignals.rows(for: text, into: destination, day: day)
        }
    }

    private static func entries(_ words: [String]) -> [DictionaryEntry] {
        words.map {
            DictionaryEntry(
                word: $0, origin: .added, firstSeen: now.addingTimeInterval(-60 * 86_400), timesUsed: 50)
        }
    }

    static let empty = Persona(name: "empty", entries: [], profile: .default, evidence: [])

    static let sqlHeavy: Persona = {
        let words = entries(["PostgreSQL", "SELECT", "JOIN", "GROUP BY", "pgAdmin", "user_id"])
        let texts = [
            "SELECT user_id FROM orders JOIN users ON users.id = orders.user_id",
            "GROUP BY user_id in PostgreSQL",
            "open pgAdmin and SELECT the newest rows",
        ]
        return Persona(
            name: "SQL-heavy", entries: words,
            profile: UserProfile(preferredLanguages: [.english], pauses: .long),
            evidence: history(of: texts, into: .sqlEditor, using: words)
                + history(of: texts, into: .codeEditor, using: words))
    }()

    static let proseOnly: Persona = {
        let words = entries(["Orvanta", "Quillfeather", "Marisol"])
        let texts = [
            "Thanks Marisol, the Orvanta draft is attached.",
            "Can Quillfeather review it on Thursday?",
            "I will send the Orvanta notes tonight.",
        ]
        return Persona(
            name: "prose-only", entries: words, profile: .default,
            evidence: history(of: texts, into: .document, using: words))
    }()

    static let personas = [empty, sqlHeavy, proseOnly]

    /// An empty editor buffer in a code editor, and a sentence that is prose.
    static let context = AppContext(
        applicationName: "Visual Studio Code", bundleIdentifier: "com.microsoft.VSCode",
        precedingText: "", followingText: "")
    static let utterance = "um remind me to send the invoice to the landlord tomorrow"

    private static func request(for persona: Persona) -> TransformationRequest {
        let vocabulary = WorkingSet.words(
            from: persona.entries, now: now, favouring: context, evidence: persona.evidence)
        return TransformationRequest(
            transcription: Transcription(text: utterance), context: context,
            profile: persona.profile, vocabulary: vocabulary)
    }

    @Test("The fixtures differ in what they would bias: the SQL persona puts its words in the vocabulary")
    func fixturesAreNotVacuous() {
        let empty = Self.request(for: Self.empty).vocabulary
        let sql = Self.request(for: Self.sqlHeavy).vocabulary
        let prose = Self.request(for: Self.proseOnly).vocabulary
        #expect(empty.isEmpty)
        #expect(sql.contains("PostgreSQL"))
        #expect(prose.contains("Orvanta"))
        #expect(Self.sqlHeavy.evidence.count >= 50 && Self.proseOnly.evidence.count >= 50)
    }

    @Test(
        "One utterance at one caret gets the same formatter, output and prompt under every persona",
        arguments: personas)
    func personaNeverSelects(persona: Persona) async throws {
        let baseline = Self.request(for: Self.empty)
        let request = Self.request(for: persona)
        #expect(request.situation == baseline.situation)
        #expect(
            DestinationFormatter.standard(for: request.situation)
                == DestinationFormatter.standard(for: baseline.situation))

        let transformer = RuleBasedTransformer()
        let output = try await transformer.transform(request).text
        let expected = try await transformer.transform(baseline).text
        #expect(output == expected)

        let prompts = PromptBuilder.standard
        #expect(prompts.userPrompt(for: request) == prompts.userPrompt(for: baseline))
        #expect(
            prompts.conversation(for: request.situation.destination)
                == prompts.conversation(for: baseline.situation.destination))
    }

    /// A field added here reaches every formatter decision, so it is a deliberate change to `Docs/adapters.md`.
    @Test("The situation carries only what the screen said and how the person writes numbers")
    func situationHoldsNoLearnedState() {
        let fields = Mirror(reflecting: Situation.unknown).children.compactMap(\.label)
        #expect(fields == ["app", "insertion", "destination", "intent", "numberStyle"])
    }

    /// The files that turn a situation into a formatter, which must not name a learned or stored type.
    static let choosingFiles = [
        "Models/Situation.swift", "Models/WritingIntent.swift", "Models/DestinationClassifier.swift",
        "Models/DestinationFormatter.swift", "Models/DestinationRules.swift", "Models/CaretStructure.swift",
        "Models/CaretStructure+Region.swift", "Models/FieldKind.swift", "Models/FieldRole.swift",
    ]

    /// Learned state lives in the same module as the choice, so an import check alone cannot keep it out.
    static let learnedTypes = [
        "EvidenceRow", "StyleSignals", "UserProfile", "DictionaryEntry", "WorkingSet", "PersonaProjection",
        "DictationRecord", "TransformationRequest",
    ]

    @Test(
        "No file that chooses the formatter names a persona, history or settings type",
        arguments: choosingFiles)
    func choosingFileNamesNoLearnedType(file: String) throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // UttrflowAITests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // package root
            .appending(path: "Sources/UttrflowCore/\(file)")
        let text = try String(contentsOf: url, encoding: .utf8)
        let named = Self.learnedTypes.filter {
            text.range(of: "\\b\($0)\\b", options: .regularExpression) != nil
        }
        #expect(named.isEmpty, "\(file) names \(named); see Docs/adapters.md, section 2")
    }
}
