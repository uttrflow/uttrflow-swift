import NaturalLanguage
import Testing
import UttrflowCore

@testable import UttrflowEval

/// How far the tagger's classes on recogniser-shaped text agree with its classes on the written reference.
@Suite("Lexical class probe on corpus references")
struct LexicalClassProbeTests {
    /// Agreement counts over the English references, read once.
    static let probe = Probe(EvaluationCorpus.cases(for: .english).map(\.expected))

    struct Probe {
        var words = 0
        var agreeing = 0
        var sentenceEnds = 0
        var sentenceEndsAgreeing = 0
        var aligned = 0
        var cases = 0

        init(_ references: [String]) {
            for reference in references {
                cases += 1
                let written = LexicalClass.tags(in: reference)
                let shaped = LexicalClass.tags(in: Self.recogniserShape(reference))
                guard written.count == shaped.count else { continue }
                aligned += 1
                let ends = Self.sentenceEndWords(reference)
                for (index, pair) in zip(written, shaped).enumerated() {
                    words += 1
                    let same = pair.0.tag == pair.1.tag
                    if same { agreeing += 1 }
                    if ends.contains(index) {
                        sentenceEnds += 1
                        if same { sentenceEndsAgreeing += 1 }
                    }
                }
            }
        }

        /// Lowercase with sentence marks removed, as the recogniser's bare output reads.
        static func recogniserShape(_ text: String) -> String {
            String(text.lowercased().map { ".,?!;:\"()".contains($0) ? " " : $0 })
        }

        /// Tags that are marks rather than words.
        static let marks: Set<NLTag> = [
            .punctuation, .openQuote, .closeQuote, .otherPunctuation, .openParenthesis, .closeParenthesis,
            .dash,
        ]

        /// The word indices that close a written sentence.
        static func sentenceEndWords(_ text: String) -> Set<Int> {
            var ends: Set<Int> = []
            var index = -1
            let tagger = NLTagger(tagSchemes: [.lexicalClass])
            tagger.string = text
            tagger.enumerateTags(
                in: text.startIndex..<text.endIndex, unit: .word, scheme: .lexicalClass,
                options: [.omitWhitespace]
            ) { tag, _ in
                if tag == .sentenceTerminator {
                    if index >= 0 { ends.insert(index) }
                } else if !Self.marks.contains(tag ?? .punctuation) {
                    index += 1
                }
                return true
            }
            return ends
        }
    }

    @Test("records the agreement table")
    func table() {
        let probe = Self.probe
        print(
            "lexical-class-probe cases=\(probe.cases) aligned=\(probe.aligned) words=\(probe.words) "
                + "agreeing=\(probe.agreeing) sentenceEnds=\(probe.sentenceEnds) "
                + "sentenceEndsAgreeing=\(probe.sentenceEndsAgreeing)"
        )
        #expect(probe.agreeing * 100 >= probe.words * 95)
    }
}
