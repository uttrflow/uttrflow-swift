import Testing
import UttrflowTestSupport

@testable import UttrflowAI
@testable import UttrflowCore
@testable import UttrflowEval

/// Holds the guard's same-words proof to the corpus: it never reads a changed word as the same, and it changes no verdict a mark, case or layout check owns.
@Suite("Same-words proof over the corpus")
struct SameWordsCorpusTests {
    static let corpus = EvaluationCorpus.all + EvaluationCorpus.longForm + EvaluationCorpus.genres
    static let seeds = Seeded.seeds(0..<20)

    /// A case's draft as the engine hands it to the model, with the formatter and passes that judge the answer.
    struct Prepared {
        let id: String
        let expected: String
        let draft: Draft
        let formatter: DestinationFormatter
        let pipeline: CleaningPipeline

        init(_ sample: EvaluationCase) {
            id = sample.id
            expected = sample.expected
            formatter = DestinationFormatter.standard(for: sample.situation)
            pipeline = CleaningPipeline.beforeModel(for: formatter, situation: sample.situation)
            draft = pipeline.run(Draft(keepingLineBreaks: sample.spoken))
        }

        func input(_ rewritten: String) -> GuardInput {
            GuardInput(
                draft: draft, rewritten: rewritten, layout: formatter.layout, grammar: formatter.grammar,
                grants: pipeline.grants)
        }
    }

    static let prepared = corpus.map(Prepared.init)

    /// The draft's own words, each written as the expected text writes it where the two share the word, with the expected text's line breaks.
    static func punctuated(_ draft: String, like expected: String) -> String {
        let kept = WordTokens.tokens(draft, .display)
        let shown = WordTokens.tokens(expected, .display).filter { !WordShape($0.text).key.isEmpty }
        let alignment = WordErrorRate.measure(
            reference: kept.map { WordShape($0.text).key }, hypothesis: shown.map { WordShape($0.text).key })
        func breakBefore(_ token: WordToken, in text: String) -> String? {
            let gap = String(
                text[..<token.range.lowerBound].reversed().prefix(while: \.isWhitespace).reversed())
            return gap.contains(where: \.isNewline) ? gap : nil
        }
        var written: [String] = []
        var keptIndex = 0
        var shownIndex = 0
        for operation in alignment.alignment {
            let gap = breakBefore(kept[min(keptIndex, kept.count - 1)], in: draft)
            switch operation {
            case .match:
                let separator = gap ?? breakBefore(shown[shownIndex], in: expected) ?? " "
                written.append((written.isEmpty ? "" : separator) + shown[shownIndex].text)
                keptIndex += 1
                shownIndex += 1
            case .substitution, .deletion:
                written.append((written.isEmpty ? "" : gap ?? " ") + kept[keptIndex].text)
                keptIndex += 1
                if operation.kind == .substitution { shownIndex += 1 }
            case .insertion:
                shownIndex += 1
            }
        }
        return written.joined()
    }

    /// The first refusal among the checks with no word proof applied, which is the guard as it judged before the proof.
    static func unproven(_ input: GuardInput) -> (check: String, verdict: GuardVerdict)? {
        for check in MeaningPreservationGuard.checks {
            let verdict = check.judge(input)
            if !verdict.isAccepted { return (check.name, verdict) }
        }
        return nil
    }

    @Test("a punctuation-and-case rewrite of every draft is refused only by a check its words cannot answer")
    func corpusVerdicts() {
        let guarder = MeaningPreservationGuard()
        var before: [String] = []
        var after: [String] = []
        var longFormAfter = 0
        var judged = 0
        for sample in Self.prepared {
            let rewritten = Self.punctuated(sample.draft.text, like: sample.expected)
            guard rewritten != sample.draft.text else { continue }
            judged += 1
            let input = sample.input(rewritten)
            #expect(input.sameWords, "\(sample.id): \(rewritten)")
            if let refused = Self.unproven(input) { before.append("\(sample.id) [\(refused.check)]") }
            guard let refused = guarder.checkResults(on: input).first(where: { !$0.verdict.isAccepted })
            else {
                continue
            }
            after.append("\(sample.id) [\(refused.name)]")
            if sample.id.hasPrefix("long-form-") { longFormAfter += 1 }
            #expect(refused.verdict == guarder.verdict(on: input))
        }
        print(
            "same-words rewrites refused: \(before.count) of \(judged) before the proof, \(after.count) after"
        )
        for line in after { print("  \(line)") }
        #expect(longFormAfter == 0)
        #expect(after.allSatisfy(before.contains))
    }

    /// Every word the corpus speaks, a lone mark left to the symbol checks rather than counted a word.
    static let wordPool = Array(
        Set(corpus.flatMap { WordTokens.words($0.spoken, .display) }.filter { !WordShape($0).key.isEmpty })
    ).sorted()

    /// One edit to the words of a draft, chosen by the generator; `nil` where the draft gives it nothing to change.
    static func editedWord(_ words: [String], pool: [String], using generator: inout Seeded) -> [String]? {
        let speakable = words.indices.filter { !WordShape(words[$0]).key.isEmpty }
        guard let place = speakable.randomElement(using: &generator) else { return nil }
        var edited = words
        let word = words[place]
        let shape = WordShape(word)
        switch Int.random(in: 0..<8, using: &generator) {
        case 0:
            guard let other = pool.filter({ WordShape($0).key != shape.key }).randomElement(using: &generator)
            else { return nil }
            edited[place] = shape.replacingCore(with: other)
        case 1:
            edited.remove(at: place)
        case 2:
            edited.insert(generator.pick(pool), at: place)
        case 3:
            guard let next = speakable.first(where: { $0 > place }),
                WordShape(words[next]).key != shape.key
            else { return nil }
            edited.swapAt(place, next)
        case 4:
            guard let inner = shape.core.firstIndex(where: { !$0.isLetter && !$0.isNumber }) else {
                return nil
            }
            var core = shape.core
            core.remove(at: inner)
            edited[place] = shape.replacingCore(with: core)
        case 5:
            guard shape.core.count > 1 else { return nil }
            let cut = shape.core.index(
                shape.core.startIndex, offsetBy: Int.random(in: 1..<shape.core.count, using: &generator))
            edited[place] = shape.prefix + shape.core[..<cut] + " " + shape.core[cut...] + shape.suffix
        case 6:
            guard let next = speakable.first(where: { $0 > place }) else { return nil }
            edited[place] = word + words[next]
            edited.remove(at: next)
        default:
            guard let letter = shape.core.firstIndex(where: \.isLetter) else { return nil }
            let other = generator.pick(
                Array("abcdefghijklmnopqrstuvwxyz").filter {
                    $0 != Character(shape.core[letter].lowercased())
                })
            var core = shape.core
            core.replaceSubrange(letter...letter, with: String(other))
            edited[place] = shape.replacingCore(with: core)
        }
        return edited
    }

    /// Marks at the words' edges, capitals and breaks a model may add, which leave every word unchanged.
    static func punctuationNoise(_ words: [String], using generator: inout Seeded) -> String {
        words.map { word in
            var written = generator.chance(0.3) ? WordShape.capitalised(word) : word
            if generator.chance(0.2) {
                written += generator.pick([",", ".", ";", ":", "?", "!", "\u{2014}"])
            }
            if generator.chance(0.05) { written = "(" + written + ")" }
            if generator.chance(0.05) { written = "\"" + written + "\"" }
            return written
        }
        .reduce("") { text, word in
            text.isEmpty ? word : text + (generator.chance(0.05) ? "\n\n" : " ") + word
        }
    }

    @Test("no edit to a word, with any marks, case and breaks around it, is read as the same words")
    func wordEditsNeverProven() {
        let pool = Self.wordPool
        var edits = 0
        for seed in Self.seeds {
            var generator = Seeded(seed: seed)
            for sample in Self.prepared {
                let words = WordTokens.words(sample.draft.text, .display)
                guard let edited = Self.editedWord(words, pool: pool, using: &generator) else { continue }
                let rewritten = Self.punctuationNoise(edited, using: &generator)
                edits += 1
                #expect(
                    !GuardInput(text: sample.draft.text, rewritten: rewritten, excusingPreamble: false)
                        .sameWords,
                    "\(generator) \(sample.id): \(rewritten)")
            }
        }
        print("word edits read as different words: \(edits)")
        #expect(edits > Self.seeds.count * Self.prepared.count / 2)
    }

    @Test("marks, case and breaks alone are always read as the same words")
    func noiseAlwaysProven() {
        for seed in Self.seeds {
            var generator = Seeded(seed: seed)
            for sample in Self.prepared {
                let rewritten = Self.punctuationNoise(
                    WordTokens.words(sample.draft.text, .display), using: &generator)
                #expect(
                    GuardInput(text: sample.draft.text, rewritten: rewritten, excusingPreamble: false)
                        .sameWords,
                    "\(generator) \(sample.id): \(rewritten)")
            }
        }
    }

    @Test("a word edit is judged exactly as the guard judged it before the proof")
    func wordEditsJudgedAsBefore() {
        let pool = Self.wordPool
        var generator = Seeded(seed: Self.seeds.first ?? 0)
        let guarder = MeaningPreservationGuard()
        for sample in Self.prepared where sample.id.hasPrefix("long-form-") || sample.id.hasPrefix("genre-") {
            let words = WordTokens.words(sample.draft.text, .display)
            guard let edited = Self.editedWord(words, pool: pool, using: &generator) else { continue }
            let input = sample.input(Self.punctuationNoise(edited, using: &generator))
            #expect(
                guarder.verdict(on: input) == (Self.unproven(input)?.verdict ?? .accepted), "\(sample.id)")
        }
    }
}
