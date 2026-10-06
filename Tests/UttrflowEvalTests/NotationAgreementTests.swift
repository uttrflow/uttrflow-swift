import Foundation
import Testing
import UttrflowAI
import UttrflowCore

@testable import UttrflowEval

/// The spoken command table, the corpus and the prompt blocks describe one notation.
@Suite("The notation table agrees with the corpus and the prompt")
struct NotationAgreementTests {
    /// The lower-cased words of a sentence, with the punctuation around each stripped.
    private static func words(_ text: String) -> [String] {
        text.lowercased().split(whereSeparator: \.isWhitespace).map { (word: Substring) -> String in
            String(word).trimmingCharacters(in: .punctuationCharacters)
        }
    }

    private static func says(_ phrase: [String], in text: String) -> Bool {
        let spoken = words(text)
        guard phrase.count <= spoken.count else { return false }
        return (0...(spoken.count - phrase.count)).contains {
            Array(spoken[$0..<$0 + phrase.count]) == phrase
        }
    }

    /// Rows no corpus case says yet, a baseline that only shrinks: a row that gains a case must leave it.
    static let uncovered: Set<String> = [
        "case.kebab", "case.upper", "code.arrow", "code.close-brace",
        "code.open-brace", "code.semicolon", "code.underscore", "layout.blank-line",
        "layout.next-point",
        "mark.exclamation-mark", "mark.exclamation-point", "mark.hyphen", "mark.semi-colon", "mark.semicolon",
    ]

    /// Block and row pairs where a worked example writes other than the table, a baseline that only shrinks.
    static let disagreements: Set<String> = []

    @Test("every table row is said by a corpus case in a destination it is enabled in")
    func everyRowHasACorpusCase() {
        // The corpus runs the default steps, which leave emoji names as words; `SpokenEmojiTests` covers those rows.
        for row in SpokenCommands.all where !Self.uncovered.contains(row.id) && row.action != .emoji {
            let covered = EvaluationCorpus.all.contains {
                row.isEnabled(in: $0.destination) && Self.says(row.words, in: $0.spoken)
            }
            #expect(covered, "\(row.id) has no corpus case")
        }
    }

    @Test("the uncovered baseline names only rows that exist and still lack a case")
    func uncoveredOnlyShrinks() {
        let ids = Set(SpokenCommands.all.map(\.id))
        for id in Self.uncovered {
            #expect(ids.contains(id), "\(id) is not a table row")
            let row = SpokenCommands.all.first { $0.id == id }
            let covered = row.map { row in
                EvaluationCorpus.all.contains {
                    row.isEnabled(in: $0.destination) && Self.says(row.words, in: $0.spoken)
                }
            }
            #expect(covered != true, "\(id) now has a corpus case; remove it from the baseline")
        }
    }

    /// A mark whose words a flag row also says is that flag wherever the flag row is enabled.
    private static func isSuperseded(_ row: SpokenCommand, in destination: Destination) -> Bool {
        row.action == .mark
            && SpokenCommands.flags.contains { $0.words == row.words && $0.isEnabled(in: destination) }
    }

    @Test("a worked example that says a command writes what the table writes for it")
    func promptExamplesFollowTheTable() {
        for (destination, formatter) in DestinationFormatter.registry {
            guard let block = PromptBlocks.standard[formatter.promptBlock] else { continue }
            for example in block.examples {
                for row in SpokenCommands.all
                where row.action != .casing && row.isEnabled(in: destination)
                    && !Self.isSuperseded(row, in: destination)
                    && Self.says(row.words, in: example.spoken)
                    && !Self.disagreements.contains("\(block.id) \(row.id)")
                {
                    #expect(
                        example.cleaned.contains(row.text),
                        "\(block.id) example \"\(example.spoken)\" says \(row.id) but does not write \(row.text)"
                    )
                }
            }
        }
    }
}
