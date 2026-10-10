// How much labelled data each fitted layer needs before its fit means anything, and the check a fit runs first.

/// A dictation-quality layer whose shipped parameters are fitted from data. See `Docs/dictation-quality.md`.
public enum FittedLayer: String, Sendable, CaseIterable {
    /// The linear reranker over a doubtful span's candidates.
    case spanReranker = "span-reranker"
    /// The doubtful-span detector and its monotone calibration map.
    case doubtDetector = "doubt-detector"
    /// The domain n-gram table that scores a candidate against its neighbours.
    case contextNgram = "context-ngram"
    /// A small masked-language-model encoder, fine-tuned on the corpus.
    case maskedScorer = "masked-scorer"
    /// The override gate's calibrated margin and threshold.
    case overrideGate = "override-gate"
    /// One bounded per-person offset on the override gate's margin.
    case personOffset = "person-offset"

    /// The evidence this layer's fit needs before it may ship; below it the layer stays dark.
    public var floor: DataFloor {
        switch self {
        case .spanReranker:
            DataFloor(
                unit: .labelledSpan, rowsPerParameter: 10, wrongPerCell: 30, rowsPerCell: 0,
                weightPerFeature: true,
                fixedParameters: 1)
        case .doubtDetector:
            DataFloor(
                unit: .labelledSpan, rowsPerParameter: 10, wrongPerCell: 100, rowsPerCell: 0,
                weightPerFeature: true,
                fixedParameters: 1 + DataFloor.calibrationSteps)
        case .contextNgram:
            DataFloor(
                unit: .sentence, rowsPerParameter: 0, wrongPerCell: 0, rowsPerCell: 2_000,
                weightPerFeature: false,
                fixedParameters: 0)
        case .maskedScorer:
            DataFloor(
                unit: .labelledSpan, rowsPerParameter: 0, wrongPerCell: 2_000, rowsPerCell: 0,
                weightPerFeature: false,
                fixedParameters: 0)
        case .overrideGate:
            DataFloor(
                unit: .decision, rowsPerParameter: 10, wrongPerCell: 30, rowsPerCell: 300,
                weightPerFeature: false,
                fixedParameters: 2)
        case .personOffset:
            DataFloor(
                unit: .decision, rowsPerParameter: 10, wrongPerCell: 0, rowsPerCell: 0,
                weightPerFeature: false,
                fixedParameters: 1)
        }
    }
}

/// The fewest rows a fit may read: per fitted parameter, and in every split-and-language cell.
public struct DataFloor: Sendable, Equatable {
    /// What one row of the fit's input is.
    public enum Unit: String, Sendable, Equatable {
        /// A doubtful span labelled right or wrong against the reference.
        case labelledSpan = "labelled span"
        /// A reference sentence, counted only; it carries no label.
        case sentence = "text sentence"
        /// An override the gate weighs, labelled by whether the recogniser's word is right.
        case decision
    }

    /// The most steps a fitted calibration map is allowed, each needing its share of rows.
    public static let calibrationSteps = 10

    public let unit: Unit
    /// Fewest development rows per fitted parameter.
    public let rowsPerParameter: Int
    /// Fewest wrong-labelled rows in each split for each language: the rare class.
    public let wrongPerCell: Int
    /// Fewest rows of either label in each split for each language.
    public let rowsPerCell: Int
    /// Whether the fit learns one weight per feature.
    public let weightPerFeature: Bool
    /// Parameters the fit has whatever its feature count: a bias, calibration steps, a threshold.
    public let fixedParameters: Int

    /// The parameters a fit over `featureCount` features has.
    public func parameters(featureCount: Int) -> Int {
        (weightPerFeature ? featureCount : 0) + fixedParameters
    }
}

/// One count a table is short of its layer's floor, worded so it names what to collect.
public struct FloorShortfall: Sendable, Equatable, CustomStringConvertible {
    public enum Count: Sendable, Equatable {
        case developmentRows(parameters: Int)
        case wrongRows(split: CorpusSplit, language: TranscriptionCase.Language)
        case rows(split: CorpusSplit, language: TranscriptionCase.Language)
    }

    public let count: Count
    public let have: Int
    public let need: Int

    public var description: String {
        let what =
            switch count {
            case .developmentRows(let parameters): "development rows for \(parameters) parameters"
            case .wrongRows(let split, let language): "wrong rows in \(split.rawValue) \(language.rawValue)"
            case .rows(let split, let language): "rows in \(split.rawValue) \(language.rawValue)"
            }
        return "\(what): \(have), needs \(need) (\(need - have) short)"
    }
}

extension FitTable {
    /// Right and wrong rows in one split-and-language cell.
    public struct CellCount: Sendable, Equatable {
        public let split: CorpusSplit
        public let language: TranscriptionCase.Language
        public let right: Int
        public let wrong: Int
    }

    /// Every split-and-language cell in declaration order, including empty ones, as `fit` prints them.
    public var cellCounts: [CellCount] {
        CorpusSplit.allCases.flatMap { split in
            TranscriptionCase.Language.allCases.map { language in
                let cell = rows.filter { $0.split == split && $0.language == language }
                let wrong = cell.filter { $0.label == .wrong }.count
                return CellCount(split: split, language: language, right: cell.count - wrong, wrong: wrong)
            }
        }
    }

    /// Every count this table is short of `layer`'s floor, empty when the fit may run.
    public func shortfalls(for layer: FittedLayer) -> [FloorShortfall] {
        let floor = layer.floor
        let parameters = floor.parameters(featureCount: rows.first?.features.count ?? 0)
        let development = rows.filter { $0.split == .development }.count
        var found: [FloorShortfall] = []
        if development < floor.rowsPerParameter * parameters {
            found.append(
                FloorShortfall(
                    count: .developmentRows(parameters: parameters), have: development,
                    need: floor.rowsPerParameter * parameters))
        }
        for cell in cellCounts {
            if cell.wrong < floor.wrongPerCell {
                found.append(
                    FloorShortfall(
                        count: .wrongRows(split: cell.split, language: cell.language), have: cell.wrong,
                        need: floor.wrongPerCell))
            }
            if cell.right + cell.wrong < floor.rowsPerCell {
                found.append(
                    FloorShortfall(
                        count: .rows(split: cell.split, language: cell.language),
                        have: cell.right + cell.wrong,
                        need: floor.rowsPerCell))
            }
        }
        return found
    }
}

/// How many recogniser errors a recorded or synthesised baseline yields per 1,000 reference words, one language at a time.
public struct LabelYield: Sendable, Equatable {
    /// The speaking rate reading time is costed at, matching `TranscriptionCorpus.estimatedReadingTime`.
    public static let wordsPerMinute = 120.0

    public let language: TranscriptionCase.Language
    public let errors: Int
    public let words: Int
    /// The 95% interval of the error rate, resampling whole passages; `nil` under two passages.
    public let interval: ClosedRange<Double>?

    /// Errors per 1,000 reference words.
    public var perThousandWords: Double { words == 0 ? 0 : Double(errors) / Double(words) * 1_000 }

    /// Minutes of reading at this yield to collect `count` wrong spans; `nil` when the baseline shows no errors.
    public func minutesOfReading(toCollect count: Int) -> Double? {
        guard errors > 0 else { return nil }
        return Double(count) * Double(words) / Double(errors) / Self.wordsPerMinute
    }

    /// One yield per language the baseline scored, in declaration order; unscorable entries are left out.
    public static func measure(_ baseline: AccuracyBaseline) -> [LabelYield] {
        TranscriptionCase.Language.allCases.compactMap { language in
            let entries = baseline.entries.filter { $0.language == language && !$0.isUnscorable }
            guard !entries.isEmpty else { return nil }
            return LabelYield(
                language: language, errors: entries.reduce(0) { $0 + $1.errors },
                words: entries.reduce(0) { $0 + $1.referenceWordCount },
                interval: PairedBootstrap.standard.rateInterval(entries))
        }
    }
}
