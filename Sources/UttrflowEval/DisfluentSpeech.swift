// Labelled takes from people whose speech is disfluent, scored by the meant words lost and the disfluency left in.
public import Foundation
import UttrflowCore

/// How a take departs from fluent speech; the axis every row of the report is read on.
enum SpeechPattern: String, Sendable, Equatable, CaseIterable, Codable {
    /// A sound said over before the word: "b-b-but".
    case soundRepetition = "sound-repetition"
    /// A syllable or part of a word said over: "ba- ba- banana".
    case partWordRepetition = "part-word-repetition"
    /// A whole short word said over without being meant twice: "I I I want".
    case wholeWordRepetition = "whole-word-repetition"
    /// A sound held on: "sssso".
    case prolongation
    /// A silent or strained stop before or inside a word, which can split the word in two.
    case block
    /// Slow, effortful speech with long gaps between words.
    case slowEffortful = "slow-effortful"
    /// The same speaker talking fluently, the floor every other row is read against.
    case fluent

    /// Whether a take of this pattern always has something said and not meant, which its transcript must mark.
    var isMarked: Bool {
        switch self {
        case .soundRepetition, .partWordRepetition, .wholeWordRepetition, .prolongation: true
        case .block, .slowEffortful, .fluent: false
        }
    }
}

/// Why a take or a corpus file is refused; each case names the take so the labeller can find it.
enum DisfluentSpeechError: Error, Equatable {
    case unbalancedMark(String)
    case emptyMark(String)
    case nothingMeant(String)
    case markMissing(String, SpeechPattern)
    case markOnFluent(String)
    case duplicateID(String)
    case speakerNotALabel(String)
    case consentMissing(String)
    case audioOutsideFolder(String)
    case audioMissing(String)
    case protocolVersion(Int)
}

/// One take: who said it, how it is disfluent, and what was meant, with what was said and not meant marked.
struct DisfluentUtterance: Sendable, Equatable, Codable, Identifiable {
    let id: String
    /// Who spoke, as the label on their consent record; never a name.
    let speaker: String
    let pattern: SpeechPattern
    /// What was said, with every sound or word the speaker did not mean in braces: "{b-b-}but I {I I} want it".
    let marked: String
    /// The take's file name inside the speaker's folder; `nil` for an invented case, which has no audio.
    let audio: String?
    /// The version of the consent form the speaker signed; a take with audio and no consent is refused.
    let consent: String?

    init(
        id: String, speaker: String, pattern: SpeechPattern, marked: String, audio: String? = nil,
        consent: String? = nil
    ) {
        self.id = id
        self.speaker = speaker
        self.pattern = pattern
        self.marked = marked
        self.audio = audio
        self.consent = consent
    }

    /// The transcript the speaker meant: the marked text with every braced part taken out.
    var meant: String { Self.joined(pieces.filter { !$0.isDisfluent }) }

    /// Everything that was said, the text a recogniser that heard every sound would write.
    var said: String { Self.joined(pieces) }

    /// The words inside the braces, which a clean transcript leaves out.
    var disfluentWords: Int { pieces.filter(\.isDisfluent).reduce(0) { $0 + Scorer.tokens($1.text).count } }

    /// Refuses a take whose marks or labels the scorer cannot trust.
    func validate() throws {
        let parsed = try parse()
        if Scorer.tokens(Self.joined(parsed.filter { !$0.isDisfluent })).isEmpty {
            throw DisfluentSpeechError.nothingMeant(id)
        }
        let marks = parsed.count(where: \.isDisfluent)
        if pattern == .fluent, marks > 0 { throw DisfluentSpeechError.markOnFluent(id) }
        if pattern.isMarked, marks == 0 { throw DisfluentSpeechError.markMissing(id, pattern) }
        if !CorpusSlug.isValid(speaker) { throw DisfluentSpeechError.speakerNotALabel(id) }
        if let audio {
            if consent?.isEmpty ?? true { throw DisfluentSpeechError.consentMissing(id) }
            if audio.isEmpty || audio.contains("/") || audio.hasPrefix(".") {
                throw DisfluentSpeechError.audioOutsideFolder(id)
            }
        }
    }

    private struct Piece {
        let text: String
        let isDisfluent: Bool
    }

    /// The marked text cut at its braces; a take that failed ``validate()`` reads as said.
    private var pieces: [Piece] { (try? parse()) ?? [Piece(text: marked, isDisfluent: false)] }

    private func parse() throws -> [Piece] {
        var pieces: [Piece] = []
        var current = ""
        var inside = false
        for character in marked {
            switch character {
            case "{":
                if inside { throw DisfluentSpeechError.unbalancedMark(id) }
                pieces.append(Piece(text: current, isDisfluent: false))
                current = ""
                inside = true
            case "}":
                if !inside { throw DisfluentSpeechError.unbalancedMark(id) }
                if current.allSatisfy(\.isWhitespace) { throw DisfluentSpeechError.emptyMark(id) }
                pieces.append(Piece(text: current, isDisfluent: true))
                current = ""
                inside = false
            default: current.append(character)
            }
        }
        if inside { throw DisfluentSpeechError.unbalancedMark(id) }
        pieces.append(Piece(text: current, isDisfluent: false))
        return pieces
    }

    /// Pieces joined as written, so a brace glued to a word ("{b-b-}but") keeps the word whole.
    private static func joined(_ pieces: [Piece]) -> String {
        WordTokens.words(pieces.map(\.text).joined(), .display).joined(separator: " ")
    }
}

/// The corpus file kept beside the audio on the recording Mac, never in the repository.
struct DisfluentSpeechCorpus: Sendable, Equatable, Codable {
    /// The version of `Docs/disfluent-speech.md`'s protocol the takes were recorded under.
    static let currentProtocol = 1
    /// The takes and the speakers a pass decision needs before it is read off the report.
    static let takesToDecide = 100
    static let speakersToDecide = 5

    let protocolVersion: Int
    let utterances: [DisfluentUtterance]

    init(utterances: [DisfluentUtterance], protocolVersion: Int = Self.currentProtocol) {
        self.protocolVersion = protocolVersion
        self.utterances = utterances
    }

    /// Reads and validates the file at `url`.
    static func load(from url: URL) throws -> Self {
        let corpus = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        try corpus.validate()
        return corpus
    }

    func validate() throws {
        guard protocolVersion == Self.currentProtocol else {
            throw DisfluentSpeechError.protocolVersion(protocolVersion)
        }
        var seen: Set<String> = []
        for utterance in utterances {
            guard seen.insert(utterance.id).inserted else {
                throw DisfluentSpeechError.duplicateID(utterance.id)
            }
            try utterance.validate()
        }
    }

    var speakers: Set<String> { Set(utterances.map(\.speaker)) }

    /// Whether there are enough takes from enough speakers for the report to decide a pass change.
    var isEnoughToDecide: Bool {
        utterances.count >= Self.takesToDecide && speakers.count >= Self.speakersToDecide
    }
}

/// One take's clean-up output, and the recogniser's transcript where there was audio, against what was meant.
struct DisfluentSpeechScore: Sendable, Equatable {
    let utterance: DisfluentUtterance
    let meantWords: Int
    /// Meant words the output has no word for.
    let lost: Int
    /// Output words with no meant word behind them: disfluency left in, or a word the recogniser made up.
    let leftIn: Int
    /// Meant words written as another word, a rewrite such as a numeral included.
    let misheard: Int
    /// The recogniser's transcript against the meant words, before clean-up; `nil` for an invented case.
    let recognition: WordErrorRate?

    init(utterance: DisfluentUtterance, recognised: String? = nil, output: String) {
        let meant = Scorer.tokens(utterance.meant)
        let cleaned = WordErrorRate.measure(reference: meant, hypothesis: Scorer.tokens(output))
        self.utterance = utterance
        meantWords = meant.count
        lost = cleaned.deletions
        leftIn = cleaned.insertions
        misheard = cleaned.substitutions
        recognition = recognised.map {
            WordErrorRate.measure(reference: meant, hypothesis: Scorer.tokens($0))
        }
    }
}

/// Meant words lost and disfluency left in per pattern, and the recogniser's error rate per pattern by speaker.
struct DisfluentSpeechReport: Sendable, Equatable {
    struct Row: Sendable, Equatable {
        let pattern: SpeechPattern
        let takes: Int
        let speakers: Int
        let meantWords: Int
        let disfluentWords: Int
        let lost: Int
        let leftIn: Int
        let misheard: Int

        /// Meant words lost over meant words, the number that protects a speaker.
        var lostRate: Double { meantWords == 0 ? 0 : Double(lost) / Double(meantWords) }
        /// Words left in over the words marked as not meant; `nil` where nothing was marked.
        var leftInRate: Double? { disfluentWords == 0 ? nil : Double(leftIn) / Double(disfluentWords) }
    }

    let rows: [Row]
    /// The recogniser's rate per pattern with intervals that resample speakers; `nil` when no take had audio.
    let recognition: SpeakerGroupReport?

    init(scores: [DisfluentSpeechScore]) {
        rows = SpeechPattern.allCases.compactMap { pattern in
            let scores = scores.filter { $0.utterance.pattern == pattern }
            guard !scores.isEmpty else { return nil }
            return Row(
                pattern: pattern, takes: scores.count, speakers: Set(scores.map(\.utterance.speaker)).count,
                meantWords: scores.reduce(0) { $0 + $1.meantWords },
                disfluentWords: scores.reduce(0) { $0 + $1.utterance.disfluentWords },
                lost: scores.reduce(0) { $0 + $1.lost }, leftIn: scores.reduce(0) { $0 + $1.leftIn },
                misheard: scores.reduce(0) { $0 + $1.misheard })
        }
        // The pattern is the labeller's, read off the marked transcript, so it is a verified label.
        let clips = scores.compactMap { score in
            score.recognition.map {
                SpeakerClip(
                    speaker: score.utterance.speaker, group: score.utterance.pattern.rawValue,
                    label: .verified,
                    errors: $0.errors, words: $0.referenceWordCount)
            }
        }
        recognition = clips.isEmpty ? nil : SpeakerGroupReport(clips: clips)
    }

    /// The printed report: one line per pattern, then the recogniser's rows when there was audio.
    var lines: [String] {
        func percent(_ value: Double?) -> String { value.map { String(format: "%.1f%%", $0 * 100) } ?? "-" }
        let header =
            "pattern\ttakes\tspeakers\tmeant\tlost\tlost rate\tmarked\tleft in\tleft-in rate\tmisheard"
        let table = rows.map { row in
            [
                row.pattern.rawValue, "\(row.takes)", "\(row.speakers)", "\(row.meantWords)", "\(row.lost)",
                percent(row.lostRate), "\(row.disfluentWords)", "\(row.leftIn)", percent(row.leftInRate),
                "\(row.misheard)",
            ].joined(separator: "\t")
        }
        return [header] + table
            + (recognition.map { ["", "recogniser against meant words"] + $0.lines } ?? [])
    }
}

/// Scores a recorded corpus folder: `corpus.json` beside one subfolder of audio per speaker label.
public enum DisfluentSpeechRun {
    /// What the recogniser wrote for one take, and what the clean-up made of it.
    public struct Heard: Sendable, Equatable {
        public let recognised: String
        public let output: String

        public init(recognised: String, output: String) {
            self.recognised = recognised
            self.output = output
        }
    }

    /// Checks every take's audio is in place, decodes each in turn, and returns the corpus line then the report.
    public static func lines(folder: URL, decode: (URL) async throws -> Heard) async throws -> [String] {
        let corpus = try DisfluentSpeechCorpus.load(from: folder.appendingPathComponent("corpus.json"))
        let recorded = corpus.utterances.compactMap { take in
            take.audio.map { (take, folder.appendingPathComponent(take.speaker).appendingPathComponent($0)) }
        }
        for (take, url) in recorded where !FileManager.default.fileExists(atPath: url.path) {
            throw DisfluentSpeechError.audioMissing(take.id)
        }
        var scores: [DisfluentSpeechScore] = []
        for (take, url) in recorded {
            let heard = try await decode(url)
            scores.append(
                DisfluentSpeechScore(utterance: take, recognised: heard.recognised, output: heard.output))
        }
        let heardCorpus = DisfluentSpeechCorpus(
            utterances: recorded.map(\.0), protocolVersion: corpus.protocolVersion)
        let skipped = corpus.utterances.count - recorded.count
        let decision =
            heardCorpus.isEnoughToDecide
            ? "enough to decide"
            : "not enough to decide (needs \(DisfluentSpeechCorpus.takesToDecide) takes from "
                + "\(DisfluentSpeechCorpus.speakersToDecide) speakers)"
        let summary =
            "\(recorded.count) recorded takes from \(heardCorpus.speakers.count) speakers; "
            + "\(skipped) take\(skipped == 1 ? "" : "s") without audio skipped; \(decision)"
        return [summary] + DisfluentSpeechReport(scores: scores).lines
    }
}
