// Measures how many words the screen can put into a dictation that the speaker never said.
import Foundation
import Testing
import UttrflowCore

@testable import UttrflowAI
@testable import UttrflowEval

/// One dictation paired with a screen string that holds a near-homophone of one spoken word. See Docs/ai-context-line.md.
private struct SteeringCase {
    /// The spoken words, a question so the rules never settle them and the model is asked.
    let spoken: String
    /// The spoken word the recogniser is unsure of, when it is.
    let doubtful: String
    /// An invented word that sounds like `doubtful`; it appears only on screen.
    let planted: String
}

/// Where on screen the planted word sits.
private enum ScreenSource: String, CaseIterable {
    case windowTitle = "window title"
    case selection = "selection"
    case precedingText = "text before the caret"
    case quotedReply = "quoted reply after the caret"

    func context(planting word: String) -> AppContext {
        let notes = (name: "Notes", id: "com.apple.Notes")
        switch self {
        case .windowTitle:
            return AppContext(
                applicationName: notes.name, bundleIdentifier: notes.id, documentName: "Draft for \(word)")
        case .selection:
            return AppContext(
                applicationName: notes.name, bundleIdentifier: notes.id, selectedText: "ask \(word) to review"
            )
        case .precedingText:
            return AppContext(
                applicationName: notes.name, bundleIdentifier: notes.id,
                precedingText: "Thanks for the update, \(word). ")
        case .quotedReply:
            return AppContext(
                applicationName: notes.name, bundleIdentifier: notes.id,
                followingText: "\n> \(word) wrote: see you at example.com")
        }
    }
}

/// What one dictation let through from one screen source.
private struct SteeringOutcome {
    let source: ScreenSource
    let recogniserWasUnsure: Bool
    /// Screen words absent from the audio that the engine offered as readings.
    let offered: Set<String>
    /// Screen words absent from the audio that survived the guard in an answer that took every offer.
    let shipped: Set<String>
}

private actor AskCount {
    private(set) var asked = 0
    func ask() { asked += 1 }
}

/// A model that always takes the first offered reading that comes off the screen, the worst a model can do with the offers.
private struct AcceptingModel: CleanupModel {
    let answer: String
    let count = AskCount()

    func availability(for language: LanguageCode?) async -> TransformerAvailability { .available }

    func rewrite(
        _ text: String, instructions: String, kind: TransformerKind
    ) async throws(TransformationError) -> String {
        await count.ask()
        return answer
    }
}

private enum SteeringProbe {
    static let cases = [
        SteeringCase(
            spoken: "can you send the recipe to everyone before lunch", doubtful: "recipe", planted: "Resipee"
        ),
        SteeringCase(
            spoken: "is the invoice overdue or just late", doubtful: "overdue", planted: "Overdoo"),
        SteeringCase(
            spoken: "did you book the venue for the party", doubtful: "venue", planted: "Venew"),
        SteeringCase(
            spoken: "can we sign the contract before friday", doubtful: "contract", planted: "Kontract"),
        SteeringCase(
            spoken: "who watered the garden this morning", doubtful: "garden", planted: "Gardin"),
        SteeringCase(
            spoken: "will they repeal the rule this year", doubtful: "repeal", planted: "Repeel"),
        SteeringCase(
            spoken: "can you take the route through town", doubtful: "route", planted: "Rowt"),
    ]

    static func words(_ text: String) -> Set<String> {
        Set(WordTokens.words(text, .comparison).map { $0.lowercased() })
    }

    /// The text the screen shows, as one string.
    static func shown(_ context: AppContext) -> String {
        [context.documentName, context.selectedText, context.precedingText, context.followingText]
            .compactMap(\.self).joined(separator: " ")
    }

    static func run(
        _ steering: SteeringCase, from source: ScreenSource, unsure: Bool
    ) async -> SteeringOutcome {
        let evaluation = EvaluationCase(
            id: "steer-\(steering.planted.lowercased())-\(source.rawValue)", category: .notARequest,
            spoken: steering.spoken, expected: steering.spoken,
            context: source.context(planting: steering.planted),
            doubtful: unsure ? [steering.doubtful] : [])
        let spoken = words(steering.spoken)
        let onScreen = words(shown(evaluation.context))
        let leaks: (Set<String>) -> Set<String> = { $0.subtracting(spoken).intersection(onScreen) }

        let draft = CleaningPipeline.beforeModel(for: .standard(for: .plain), situation: .unknown).run(
            Draft(transcription: evaluation.transcription))
        let spans = await DoubtfulWords.standard.spans(in: draft, for: evaluation.situation)
        let offered = leaks(Set(spans.flatMap(\.candidates).flatMap { words($0.spelling) }))

        var answer = steering.spoken
        for span in spans {
            guard let reading = span.candidates.first(where: { !leaks(words($0.spelling)).isEmpty }) else {
                continue
            }
            answer = answer.replacingOccurrences(of: span.heard, with: reading.spelling)
        }
        let model = AcceptingModel(answer: answer)
        let shipped = try? await GenerativeTextTransformer(kind: .foundationModels, model: model)
            .transform(evaluation.transformationRequest())
        return SteeringOutcome(
            source: source, recogniserWasUnsure: unsure, offered: offered,
            shipped: leaks(words(shipped?.text ?? "")))
    }

    static func outcomes() async -> [SteeringOutcome] {
        var all: [SteeringOutcome] = []
        for steering in cases {
            for source in ScreenSource.allCases {
                for unsure in [true, false] {
                    all.append(await run(steering, from: source, unsure: unsure))
                }
            }
        }
        return all
    }

    /// The upper end of a one-sided 95% interval for a rate that was zero in `trials` runs.
    static func zeroUpperBound(trials: Int) -> Double { 1 - pow(0.05, 1 / Double(trials)) }
}

/// Keeps the screen-to-dictation leak measured per source, so a source that starts to steer shows up as a count.
@Suite("Screen text steering recognition")
struct ScreenSteeringProbeTests {
    @Test("puts the planted word only on screen, sounding like a spoken word and not inside it")
    func plantedWordIsOnlyOnScreen() {
        for steering in SteeringProbe.cases {
            #expect(!SteeringProbe.words(steering.spoken).contains(steering.planted.lowercased()))
            #expect(SteeringProbe.words(steering.spoken).contains(steering.doubtful))
            for source in ScreenSource.allCases {
                let shown = SteeringProbe.words(
                    SteeringProbe.shown(source.context(planting: steering.planted)))
                #expect(shown.contains(steering.planted.lowercased()), "\(source) hides \(steering.planted)")
            }
        }
    }

    @Test("lets no screen word into a dictation whose words the recogniser was sure of")
    func sureWordsAreNeverOffered() async {
        let sure = await SteeringProbe.outcomes().filter { !$0.recogniserWasUnsure }
        #expect(sure.count == SteeringProbe.cases.count * ScreenSource.allCases.count)
        for outcome in sure {
            #expect(outcome.offered.isEmpty, "\(outcome.source) offered \(outcome.offered)")
            #expect(outcome.shipped.isEmpty, "\(outcome.source) shipped \(outcome.shipped)")
        }
    }

    @Test("ships a screen word only where the engine first offered it as a reading")
    func nothingShipsUnoffered() async {
        for outcome in await SteeringProbe.outcomes() {
            #expect(
                outcome.shipped.isSubset(of: outcome.offered),
                "\(outcome.source) shipped \(outcome.shipped) but offered \(outcome.offered)")
        }
    }

    @Test("reports the words let through per source, with the bound where none were")
    func perSourceTable() async {
        let outcomes = await SteeringProbe.outcomes()
        var lines = [
            "| Source | Unsure: offered | Unsure: shipped | Sure: offered | Sure: shipped |",
            "|---|---|---|---|---|",
        ]
        for source in ScreenSource.allCases {
            let mine = outcomes.filter { $0.source == source }
            let cells = [true, false].flatMap { unsure -> [String] in
                let runs = mine.filter { $0.recogniserWasUnsure == unsure }
                return [
                    runs.filter { !$0.offered.isEmpty }.count, runs.filter { !$0.shipped.isEmpty }.count,
                ].map { leaked in
                    leaked == 0
                        ? "0/\(runs.count) (<\(String(format: "%.0f", SteeringProbe.zeroUpperBound(trials: runs.count) * 100))%)"
                        : "\(leaked)/\(runs.count)"
                }
            }
            lines.append("| \(source.rawValue) | \(cells.joined(separator: " | ")) |")
        }
        print("STEERING-TABLE\n" + lines.joined(separator: "\n"))
        #expect(lines.count == ScreenSource.allCases.count + 2)
    }

    @Test("has a control with the screen withheld that adds nothing the speaker did not say")
    func withheldScreenAddsNothing() async {
        for steering in SteeringProbe.cases {
            let evaluation = EvaluationCase(
                id: "control", category: .notARequest, spoken: steering.spoken, expected: steering.spoken,
                context: ScreenSource.windowTitle.context(planting: steering.planted),
                doubtful: [steering.doubtful])
            let draft = CleaningPipeline.beforeModel(for: .standard(for: .plain), situation: .unknown).run(
                Draft(transcription: evaluation.transcription))
            let spans = await DoubtfulWords.standard.spans(
                in: draft, for: evaluation.transformationRequest(withholdingContext: true).situation)
            let planted = Set(spans.flatMap(\.candidates).flatMap { SteeringProbe.words($0.spelling) })
            #expect(
                !planted.contains(steering.planted.lowercased()),
                "\(steering.planted) leaks past a withheld screen")
        }
    }
}
