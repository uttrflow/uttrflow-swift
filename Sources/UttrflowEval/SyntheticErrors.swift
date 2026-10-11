// Perturbed recogniser output for reranker training, and the realism check that gates mixing it into a fit.
internal import Foundation
internal import UttrflowCore

/// The shape of one recogniser error.
package enum ErrorSpanKind: String, Sendable, Equatable, CaseIterable, Codable {
    /// One reference word written as another.
    case substitution
    /// One reference word written as two ("utter flow").
    case split
    /// Two reference words written as one.
    case merge
    /// A reference word the recogniser left out.
    case drop
}

/// What the error span is about, which decides how much a wrong guess costs the reader.
package enum ErrorSpanClass: String, Sendable, Equatable, CaseIterable, Codable {
    case name
    case number
    case commonWord = "common word"

    /// The class of a reference span: a name when any word is in `names`, a number when any word is a numeral.
    package init(reference: [String], names: Set<String>) {
        let words = reference.map { $0.lowercased() }
        if words.contains(where: { names.contains($0) }) {
            self = .name
        } else if words.contains(where: Self.isNumeral) {
            self = .number
        } else {
            self = .commonWord
        }
    }

    private static let numberWords: Set<String> = [
        "zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven",
        "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen", "twenty",
        "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety", "hundred", "thousand", "million",
        "billion",
    ]

    private static func isNumeral(_ word: String) -> Bool {
        numberWords.contains(word) || word.contains(where: \.isNumber)
    }
}

/// One error the recogniser made, or one a generator made up, described by numbers and closed classes only.
package struct ErrorSpan: Sendable, Equatable {
    package let kind: ErrorSpanKind
    package let spanClass: ErrorSpanClass
    /// Words of the reference the error covers.
    package let referenceWords: Int
    /// Character edits between the reference text and what was written.
    package let editDistance: Int
    /// The decoder's certainty in what it wrote, between 0 and 1.
    package let confidence: Double
    /// The decoder-evidence feature vector a fit row for this span carries.
    package let features: [Double]

    package init(
        kind: ErrorSpanKind, spanClass: ErrorSpanClass, referenceWords: Int, editDistance: Int,
        confidence: Double, features: [Double]
    ) {
        self.kind = kind
        self.spanClass = spanClass
        self.referenceWords = referenceWords
        self.editDistance = editDistance
        self.confidence = confidence
        self.features = features
    }
}

/// Makes errors by perturbing reference words the way the confusion table says the recogniser does.
package struct SyntheticErrorGenerator: Sendable {
    private let pairs: [ConfusionTable.Pair]
    private let real: [ErrorSpan]
    private let names: Set<String>
    private let seed: UInt64

    /// Substitution pairs weighted by their counts, kinds weighted by their share of `real`, evidence drawn from `real`.
    package init(table: ConfusionTable, real: [ErrorSpan], names: Set<String> = [], seed: UInt64) {
        self.pairs = table.pairs
        self.real = real
        self.names = Set(names.map { $0.lowercased() })
        self.seed = seed
    }

    /// `count` errors, the same for the same inputs and seed; empty when the table or the real spans are empty.
    package func generate(count: Int) -> [ErrorSpan] {
        guard !pairs.isEmpty, !real.isEmpty, count > 0 else { return [] }
        var generator = WordDoubtEvaluation.SplitMix(state: seed)
        return (0..<count).map { _ in span(&generator) }
    }

    private func span(_ generator: inout WordDoubtEvaluation.SplitMix) -> ErrorSpan {
        let kind = kindDraw(&generator)
        let first = pairDraw(&generator)
        let reference: [String]
        let written: [String]
        switch kind {
        case .substitution:
            (reference, written) = ([first.reference], [first.recognised])
        case .split:
            let word = Array(first.reference)
            let cut = word.count < 2 ? 1 : 1 + Int(generator.next() % UInt64(word.count - 1))
            (reference, written) = (
                [first.reference], [String(word.prefix(cut)), String(word.dropFirst(cut))]
            )
        case .merge:
            let second = pairDraw(&generator)
            (reference, written) = (
                [first.reference, second.reference], [first.reference + second.reference]
            )
        case .drop:
            (reference, written) = ([first.reference], [])
        }
        let donor = donorDraw(
            kind: kind, spanClass: ErrorSpanClass(reference: reference, names: names), &generator)
        return ErrorSpan(
            kind: kind, spanClass: ErrorSpanClass(reference: reference, names: names),
            referenceWords: reference.count,
            editDistance: Self.characterEdits(
                reference.joined(separator: " "), written.joined(separator: " ")),
            confidence: donor.confidence, features: donor.features)
    }

    /// A kind in proportion to how often `real` shows it.
    private func kindDraw(_ generator: inout WordDoubtEvaluation.SplitMix) -> ErrorSpanKind {
        real[Int(generator.next() % UInt64(real.count))].kind
    }

    /// A pair in proportion to its count.
    private func pairDraw(_ generator: inout WordDoubtEvaluation.SplitMix) -> ConfusionTable.Pair {
        let total = pairs.reduce(0) { $0 + max($1.count, 1) }
        var remaining = Int(generator.next() % UInt64(total))
        for pair in pairs {
            remaining -= max(pair.count, 1)
            if remaining < 0 { return pair }
        }
        return pairs[pairs.count - 1]
    }

    /// A real span of the same kind and class, else of the same kind, else any, so evidence keeps its joint shape.
    private func donorDraw(
        kind: ErrorSpanKind, spanClass: ErrorSpanClass, _ generator: inout WordDoubtEvaluation.SplitMix
    ) -> ErrorSpan {
        let exact = real.filter { $0.kind == kind && $0.spanClass == spanClass }
        let sameKind = real.filter { $0.kind == kind }
        let pool = !exact.isEmpty ? exact : (!sameKind.isEmpty ? sameKind : real)
        return pool[Int(generator.next() % UInt64(pool.count))]
    }

    /// Levenshtein over characters with unit costs, read from the one word-level alignment.
    static func characterEdits(_ reference: String, _ written: String) -> Int {
        WordErrorRate.measure(
            reference: reference.map(String.init), hypothesis: written.map(String.init)
        ).errors
    }
}

/// The largest distance each compared distribution may sit from the real one, and the cap on synthetic rows.
package struct RealismBounds: Sendable, Equatable, Codable {
    /// Two-sample Kolmogorov-Smirnov distance on words covered.
    package let length: Double
    /// Two-sample Kolmogorov-Smirnov distance on character edits.
    package let editDistance: Double
    /// Two-sample Kolmogorov-Smirnov distance on decoder confidence.
    package let confidence: Double
    /// Total variation distance between the name, number and common-word shares.
    package let classMix: Double
    /// The most that synthetic rows may be of the development rows a fit reads.
    package let maximumShare: Double

    package init(
        length: Double = 0.2, editDistance: Double = 0.2, confidence: Double = 0.2, classMix: Double = 0.2,
        maximumShare: Double = 0.5
    ) {
        self.length = length
        self.editDistance = editDistance
        self.confidence = confidence
        self.classMix = classMix
        self.maximumShare = maximumShare
    }
}

/// How far synthetic error spans sit from real ones on each compared distribution.
package struct RealismReport: Sendable, Equatable {
    /// One compared distribution: its distance and the bound it is held to.
    package struct Measure: Sendable, Equatable {
        package let name: String
        package let distance: Double
        package let bound: Double
        package var passes: Bool { distance <= bound }
    }

    package let measures: [Measure]
    package let realCount: Int
    package let syntheticCount: Int

    /// Whether every compared distance is within its bound.
    package var passes: Bool { !measures.isEmpty && measures.allSatisfy(\.passes) }

    /// Compares `synthetic` with `real`; no measures when either is empty, since nothing can be said then.
    package init(real: [ErrorSpan], synthetic: [ErrorSpan], bounds: RealismBounds) {
        realCount = real.count
        syntheticCount = synthetic.count
        guard !real.isEmpty, !synthetic.isEmpty else {
            measures = []
            return
        }
        func ks(_ value: (ErrorSpan) -> Double) -> Double {
            Self.kolmogorovSmirnov(real.map(value), synthetic.map(value))
        }
        measures = [
            Measure(name: "length", distance: ks { Double($0.referenceWords) }, bound: bounds.length),
            Measure(
                name: "edit distance", distance: ks { Double($0.editDistance) }, bound: bounds.editDistance),
            Measure(name: "confidence", distance: ks(\.confidence), bound: bounds.confidence),
            Measure(
                name: "class mix",
                distance: Self.totalVariation(real.map(\.spanClass), synthetic.map(\.spanClass)),
                bound: bounds.classMix),
        ]
    }

    /// The report as the lines a fit prints.
    package var lines: [String] {
        guard !measures.isEmpty else {
            return ["realism: nothing to compare (\(realCount) real, \(syntheticCount) synthetic): fails"]
        }
        return ["realism over \(realCount) real and \(syntheticCount) synthetic error spans:"]
            + measures.map {
                let distance = String(format: "%.3f", $0.distance)
                let bound = String(format: "%.3f", $0.bound)
                return "  \($0.name): distance \(distance), bound \(bound): \($0.passes ? "ok" : "fails")"
            }
    }

    /// The largest gap between the two empirical distribution functions.
    static func kolmogorovSmirnov(_ first: [Double], _ second: [Double]) -> Double {
        let points = Set(first + second).sorted()
        func cumulative(_ sample: [Double], _ point: Double) -> Double {
            Double(sample.count { $0 <= point }) / Double(sample.count)
        }
        return points.map { abs(cumulative(first, $0) - cumulative(second, $0)) }.max() ?? 0
    }

    /// Half the summed difference between the two samples' shares of each class.
    static func totalVariation<Class: Hashable>(_ first: [Class], _ second: [Class]) -> Double {
        let classes = Set(first).union(second)
        return classes.reduce(0.0) { total, kind in
            total
                + abs(
                    Double(first.count { $0 == kind }) / Double(first.count)
                        - Double(second.count { $0 == kind }) / Double(second.count))
        } / 2
    }
}

/// Mixes synthetic rows into a fit only when they pass the realism check, and keeps the test side real.
package enum SyntheticMix {
    /// Why synthetic rows may not join a fit.
    package enum Refusal: Error, Equatable, CustomStringConvertible {
        case unrealistic(RealismReport)
        case overCap(share: Double, maximum: Double)
        case onTestSide(count: Int)

        package var description: String {
            switch self {
            case .unrealistic(let report): (report.lines + ["synthetic rows refused"]).joined(separator: "\n")
            case .overCap(let share, let maximum):
                String(format: "synthetic share %.3f is over the cap %.3f", share, maximum)
            case .onTestSide(let count):
                "\(count) synthetic rows sit in the held-out split, which holds real errors only"
            }
        }
    }

    /// A fit over real and synthetic rows, with the report and limits that admit it.
    package struct Result: Sendable, Equatable {
        package let scorer: LinearScorer
        package let report: RealismReport
        package let bounds: RealismBounds
        package let syntheticRows: Int
        package let developmentRows: Int
        package let syntheticShare: Double

        /// The lines a fit prints: the realism report, then the cap, bounds and share recorded with it.
        package var lines: [String] {
            report.lines + [
                String(
                    format: "synthetic rows: %d of %d development rows (share %.3f, cap %.3f)", syntheticRows,
                    developmentRows, syntheticShare, bounds.maximumShare),
                String(
                    format: "bounds: length %.3f, edit distance %.3f, confidence %.3f, class mix %.3f",
                    bounds.length, bounds.editDistance, bounds.confidence, bounds.classMix),
            ]
        }
    }

    /// The wrong-labelled development rows `spans` stand for, ordinals continuing after `table`'s.
    package static func rows(
        _ spans: [ErrorSpan], after table: FitTable, language: TranscriptionCase.Language
    )
        -> [FitTableRow]
    {
        let start = (table.rows.map(\.ordinal).max() ?? -1) + 1
        return spans.enumerated().map {
            FitTableRow(
                ordinal: start + $0.offset, split: .development, language: language, label: .wrong,
                features: $0.element.features)
        }
    }

    /// Fits `table` plus `synthetic`; throws unless the report passes, the share is under the cap and no row is held out.
    package static func fit(
        table: FitTable, synthetic: [FitTableRow], realSpans: [ErrorSpan], syntheticSpans: [ErrorSpan],
        bounds: RealismBounds = RealismBounds()
    ) throws -> Result {
        let heldOut = synthetic.count { $0.split != .development }
        guard heldOut == 0 else { throw Refusal.onTestSide(count: heldOut) }
        let report = RealismReport(real: realSpans, synthetic: syntheticSpans, bounds: bounds)
        guard report.passes else { throw Refusal.unrealistic(report) }
        let real = table.developmentRows
        let share = Double(synthetic.count) / Double(max(real.count + synthetic.count, 1))
        guard share <= bounds.maximumShare else {
            throw Refusal.overCap(share: share, maximum: bounds.maximumShare)
        }
        let mixed = real + synthetic.map { FitRow(features: $0.features, label: false) }
        return Result(
            scorer: LinearScorer.fit(mixed), report: report, bounds: bounds, syntheticRows: synthetic.count,
            developmentRows: mixed.count, syntheticShare: share)
    }
}
