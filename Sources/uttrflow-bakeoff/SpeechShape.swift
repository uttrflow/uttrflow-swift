import ArgumentParser
import Foundation
import UttrflowAI
import UttrflowCore
import UttrflowEval

/// Rates per 100 words that say how much a set of transcripts looks like spontaneous speech. See `Docs/eval-methodology.md`.
struct SpeechShapeStatistics: Equatable {
    /// The marks counted by kind; every other punctuation character is `other`.
    static let markKinds: [Character] = [".", ",", "?", "!"]

    var lines = 0
    var words = 0
    var sentences = 0
    /// Words the standard passes removed, by what each pass is allowed to remove.
    var disfluent: [String: Int] = ["sound": 0, "repetition": 0, "retraction": 0]
    var marks: [String: Int] = [".": 0, ",": 0, "?": 0, "!": 0, "other": 0]
    var linesWithRestart = 0

    /// Measures transcripts with the rules floor's own passes, so both sides of a comparison use one instrument.
    static func measure(_ transcripts: [String]) async -> SpeechShapeStatistics {
        let grants = CleaningPipeline.standard.grants
        let transformer = RuleBasedTransformer()
        var stats = SpeechShapeStatistics()
        for line in transcripts {
            let tokens = line.split(whereSeparator: \.isWhitespace)
            guard !tokens.isEmpty else { continue }
            stats.lines += 1
            stats.words += tokens.count
            stats.sentences += sentenceCount(tokens)
            for character in line where character.isPunctuation {
                stats.marks[markKinds.contains(character) ? String(character) : "other", default: 0] += 1
            }
            let result = try? await transformer.transform(
                TransformationRequest(transcription: Transcription(text: line)))
            var restarted = false
            for change in result?.cleaning?.changes ?? [] where change.removedCount > 0 {
                guard let grant = grants[change.step], let name = disfluencyName(grant) else { continue }
                stats.disfluent[name, default: 0] += change.removedCount
                if grant != .sound { restarted = true }
            }
            if restarted { stats.linesWithRestart += 1 }
        }
        return stats
    }

    /// A sentence ends at a word ending in a terminal mark; a line's unfinished tail is one more.
    static func sentenceCount(_ tokens: [Substring]) -> Int {
        let ended = tokens.indices.filter { tokens[$0].last.map { ".?!".contains($0) } ?? false }
        return ended.count + (ended.last == tokens.indices.last ? 0 : 1)
    }

    private static func disfluencyName(_ grant: RemovalGrant) -> String? {
        switch grant {
        case .sound: "sound"
        case .repetition: "repetition"
        case .retraction: "retraction"
        case .conversion: nil
        }
    }

    /// A count as a rate per 100 words.
    func per100(_ count: Int) -> Double {
        words == 0 ? 0 : Double(count) * 100 / Double(words)
    }

    /// One `name value` row per figure, in a fixed order so two runs compare line for line.
    var rows: [(String, Double)] {
        var rows: [(String, Double)] = [("lines", Double(lines)), ("words", Double(words))]
        for name in ["sound", "repetition", "retraction"] {
            rows.append(("disfluent \(name) /100w", per100(disfluent[name] ?? 0)))
        }
        for kind in Self.markKinds.map(String.init) + ["other"] {
            rows.append(("mark \(kind) /100w", per100(marks[kind] ?? 0)))
        }
        rows.append(("words per sentence", sentences == 0 ? 0 : Double(words) / Double(sentences)))
        let restartShare = lines == 0 ? 0 : Double(linesWithRestart) * 100 / Double(lines)
        rows.append(("lines with a restart %", restartShare))
        return rows
    }
}

/// Prints the speech-shape figures for the corpus's English cases or for a local reference file.
struct SpeechShape: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "speech-shape",
        abstract: "Print disfluency, mark and sentence-length rates per 100 words."
    )

    @Option(name: .long, help: "A local text file, one utterance per line, to measure instead of the corpus.")
    var reference: String?

    func run() async throws {
        let lines: [String]
        if let reference {
            lines = try String(contentsOfFile: reference, encoding: .utf8)
                .split(whereSeparator: \.isNewline).map(String.init)
        } else {
            lines = EvaluationCorpus.cases(for: .english).map(\.spoken)
        }
        let stats = await SpeechShapeStatistics.measure(lines)
        for (name, value) in stats.rows {
            print("\(name.padded(to: 28))\(String(format: "%.2f", value))")
        }
    }
}
