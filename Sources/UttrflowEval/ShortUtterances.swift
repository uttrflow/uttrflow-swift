// The short-utterance class: one-to-three-word replies, scored by what a recogniser does with too little audio.
private import Foundation
public import UttrflowCore

/// One reply of one to three words, and the language it is spoken in.
public struct ShortUtterance: Sendable, Equatable, Identifiable {
    /// What kind of reply this is, so a report can say which kind fails.
    public enum Kind: String, Sendable, CaseIterable {
        case affirmative, negative, number, courtesy, name, command
    }

    public let id: String
    public let text: String
    public let language: LanguageCode
    public let kind: Kind

    public init(_ text: String, _ language: LanguageCode, _ kind: Kind) {
        self.text = text
        self.language = language
        self.kind = kind
        let slug = WordTokens.words(text.lowercased(), .comparison).joined(separator: "-")
        id = "short-\(language.value)-\(slug)"
    }

    /// Words as the scorer counts them.
    public var words: [String] { TextNormaliser.standard.words(text) }
}

/// The utterances, in English and romanised Hindi; measured in `Docs/speech-engines.md`.
public enum ShortUtterances {
    public static let all: [ShortUtterance] = english + hindi

    static let english: [ShortUtterance] = utterances(
        .english,
        [
            ("yes", .affirmative), ("okay", .affirmative), ("sure", .affirmative),
            ("sounds good", .affirmative),
            ("of course", .affirmative), ("that works", .affirmative), ("got it", .affirmative),
            ("no", .negative), ("not yet", .negative), ("no thanks", .negative), ("never mind", .negative),
            ("one", .number), ("two", .number), ("three", .number), ("four", .number), ("five", .number),
            ("six", .number), ("seven", .number), ("eight", .number), ("nine", .number), ("ten", .number),
            ("thanks", .courtesy), ("okay thanks", .courtesy), ("thank you", .courtesy), ("hello", .courtesy),
            ("good morning", .courtesy), ("see you soon", .courtesy), ("take care", .courtesy),
            ("Priya", .name), ("Marcus", .name), ("Siobhan", .name), ("Nandini", .name),
            ("undo that", .command), ("new line", .command), ("delete that", .command),
            ("send it", .command),
        ])

    static let hindi: [ShortUtterance] = utterances(
        .hindi,
        [
            ("haan", .affirmative), ("haan ji", .affirmative), ("theek hai", .affirmative),
            ("haan theek hai", .affirmative), ("achha", .affirmative), ("bilkul", .affirmative),
            ("ho gaya", .affirmative), ("chalo theek hai", .affirmative),
            ("nahi", .negative), ("nahi yaar", .negative), ("abhi nahi", .negative),
            ("bilkul nahi", .negative),
            ("ek", .number), ("do", .number), ("teen", .number), ("chaar", .number), ("paanch", .number),
            ("dhanyavaad", .courtesy), ("shukriya", .courtesy), ("namaste", .courtesy),
            ("phir milte hain", .courtesy),
            ("Anand", .name), ("Meera", .name), ("Vikram", .name),
            ("ruko", .command), ("bhej do", .command), ("mita do", .command),
        ])

    private static func utterances(
        _ language: LanguageCode, _ replies: [(String, ShortUtterance.Kind)]
    ) -> [ShortUtterance] {
        replies.map { ShortUtterance($0.0, language, $0.1) }
    }
}

/// How long a clip ran, in the bands a report groups by; the first three are the ones the class targets.
public enum ShortUtteranceBucket: String, Sendable, CaseIterable, Comparable {
    case under300ms = "< 0.3 s"
    case to600ms = "0.3-0.6 s"
    case to1s = "0.6-1.0 s"
    case to2s = "1.0-2.0 s"
    case over2s = "> 2.0 s"

    public init(seconds: Double) {
        switch seconds {
        case ..<0.3: self = .under300ms
        case ..<0.6: self = .to600ms
        case ..<1.0: self = .to1s
        case ..<2.0: self = .to2s
        default: self = .over2s
        }
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        allCases.firstIndex(of: lhs) ?? 0 < allCases.firstIndex(of: rhs) ?? 0
    }
}

/// What a recogniser did with one short clip.
public struct ShortUtteranceScore: Sendable, Equatable {
    /// The normalised words match what was said, word for word.
    public let exact: Bool
    /// At least one word came back that the speaker did not say.
    public let invented: Bool
    /// Nothing came back.
    public let empty: Bool
    /// The recogniser wrote a letter of another script, or says it heard another language.
    public let wrongScriptOrLanguage: Bool

    /// Scores `written`, the text after the script is enforced; `heard` is the recogniser's own, judged for script.
    public init(said: ShortUtterance, heard: String, written: String, detected: LanguageCode?) {
        let reference = said.words
        let hypothesis = TextNormaliser.standard.words(written)
        exact = hypothesis == reference
        empty = hypothesis.isEmpty
        invented = !Set(hypothesis).isSubset(of: Set(reference))
        wrongScriptOrLanguage = !LatinScript.isLatin(heard) || detected.map { $0 != said.language } ?? false
    }
}

/// The four class rates over a set of clips.
public struct ShortUtteranceRates: Sendable, Equatable {
    public let clips: Int
    public let exact: Int
    public let invented: Int
    public let empty: Int
    public let wrongScriptOrLanguage: Int

    public init(_ scores: [ShortUtteranceScore]) {
        clips = scores.count
        exact = scores.count { $0.exact }
        invented = scores.count { $0.invented }
        empty = scores.count { $0.empty }
        wrongScriptOrLanguage = scores.count { $0.wrongScriptOrLanguage }
    }

    /// `count` as a share of the clips, in percent.
    public func percent(_ count: Int) -> Double { clips == 0 ? 0 : Double(count) / Double(clips) * 100 }
}
