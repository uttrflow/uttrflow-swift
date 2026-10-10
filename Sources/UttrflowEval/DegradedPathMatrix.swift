// The corpus run through the pipeline with quality layers switched off, and the floor each run must keep.
public import UttrflowCore
public import UttrflowPipeline
import UttrflowDictionary
import struct Foundation.Date
import class Foundation.ProcessInfo

/// What the pipeline writes with each degraded path of `QualityLayers.degradedPaths`. See `Docs/degraded-path-matrix.md`.
public struct DegradedPathMatrix: Sendable, Equatable {
    /// Builds one case's pipeline with these layers, this tidier, and the case's dictionary as corrector and ranked words.
    public typealias Building =
        @Sendable (
            QualityLayers, any WordCorrecting, @escaping @Sendable (AppContext) async -> [String],
            any TranscriptCleaning
        ) -> DictationPipeline

    /// One run of the corpus: the layers it had off and what its outputs did to the floor.
    public struct Row: Sendable, Equatable {
        /// The layers switched off, in declaration order; empty for the default set.
        public let off: [QualityLayer]
        public let cases: Int
        public let passed: Int
        /// Forbidden words written, summed over the cases.
        public let invented: Int
        /// Reference words dropped with nothing in their place, summed over the cases.
        public let deleted: Int
        /// Words that had to survive and did not, summed over the cases.
        public let lost: Int
        /// Required beginnings or endings missing, summed over the cases.
        public let brokeShape: Int
        /// Cases with a floor failure that neither the default set nor the words as heard has.
        public let belowFloor: [String]

        /// The row's name as the page prints it.
        public var name: String {
            off.isEmpty ? "none (default)" : off.map(\.rawValue).joined(separator: " + ")
        }
    }

    /// One fallback rung's accuracy on the user's own words: those of a case's dictionary its reference writes.
    public struct Rung: Sendable, Equatable {
        public let name: String
        public let terms: Int
        public let kept: Int
    }

    public let rows: [Row]
    public let rungs: [Rung]
    /// Each degraded path paired against the default set, in the order of `rows` after the first.
    package let contributions: [LayerContribution]

    /// Runs `cases` through the default set, then through each degraded path, tidied by `cleaner`.
    public static func measure(
        _ cases: [EvaluationCase] = EvaluationCorpus.all, cleaner: any TranscriptCleaning,
        building: @escaping Building
    ) async -> DegradedPathMatrix {
        let paths: [[QualityLayer]] = [[]] + QualityLayers.degradedPaths
        let written = await withTaskGroup(of: (Int, [Written]).self) { group in
            var next = 0
            var written = [[Written]](repeating: [], count: cases.count)
            func add() {
                guard next < cases.count else { return }
                let index = next
                let testCase = cases[index]
                next += 1
                group.addTask { (index, await outputs(of: testCase, on: paths, cleaner: cleaner, building)) }
            }
            for _ in 0..<width { add() }
            for await (index, outputs) in group {
                written[index] = outputs
                add()
            }
            return written
        }
        let scores = paths.indices.map { path in
            zip(written, cases).map { Scorer.score($0[path].text, against: $1) }
        }
        let heard = cases.map { Scorer.score($0.spoken, against: $0) }
        let rows = paths.indices.map { path in
            row(paths[path], scores: scores[path], reference: scores[0], heard: heard)
        }
        let rungs = [("rules", [QualityLayer]()), ("untidied", [.formatting])].map { name, off in
            rung(name, outputs: written.map { $0[paths.firstIndex(of: off) ?? 0].text }, cases: cases)
        }
        let time = paths.indices.map { path in written.map { $0[path].time }.reduce(.zero, +) }
        let contributions = paths.indices.dropFirst().map { path in
            LayerContribution(
                off: paths[path], scores: scores[path], reference: scores[0], cases: cases,
                latency: (time[0] - time[path]) / max(1, cases.count))
        }
        return DegradedPathMatrix(rows: rows, rungs: rungs, contributions: contributions)
    }

    /// How many cases run at once, one per core.
    private static var width: Int { max(1, ProcessInfo.processInfo.activeProcessorCount) }

    /// What one path wrote for one case, and how long it took.
    struct Written: Sendable {
        let text: String
        let time: Duration
    }

    /// What one case writes on each path, sharing one `RememberedCleaning` warmed by an untimed default run.
    private static func outputs(
        of testCase: EvaluationCase, on paths: [[QualityLayer]], cleaner: any TranscriptCleaning,
        _ building: Building
    ) async -> [Written] {
        let remembering = RememberedCleaning(cleaner)
        let clock = ContinuousClock()
        var written: [Written] = []
        for off in [[]] + paths {
            let layers = QualityLayers(enabled: QualityLayers().enabled.subtracting(off))
            let pipeline = building(layers, corrector(for: testCase), speechWords(for: testCase), remembering)
            let start = clock.now
            let cleaned = await pipeline.clean([testCase.transcription], seeing: testCase.context)
            written.append(Written(text: cleaned.text ?? "", time: clock.now - start))
        }
        return Array(written.dropFirst())
    }

    /// The case's dictionary as the corrector sees it, every entry added by the user.
    static func corrector(for testCase: EvaluationCase) -> any WordCorrecting {
        let index = PhoneticIndex(entries: entries(of: testCase))
        return DictionaryCorrections { _ in index }
    }

    /// The case's dictionary ranked against the screen, as a dictation ranks the words it is biased towards.
    static func speechWords(for testCase: EvaluationCase) -> @Sendable (AppContext) async -> [String] {
        let entries = entries(of: testCase)
        let index = PhoneticIndex(entries: entries)
        return { context in
            WorkingSet.words(
                from: entries, coded: index, now: Date(timeIntervalSince1970: 0), favouring: context)
        }
    }

    private static func entries(of testCase: EvaluationCase) -> [DictionaryEntry] {
        testCase.dictionary.map {
            DictionaryEntry(word: $0, origin: .added, firstSeen: Date(timeIntervalSince1970: 0))
        }
    }

    /// Each floor failure of one score, named by its kind so two kinds of one word stay apart.
    static func floorFailures(_ score: CaseScore) -> Set<String> {
        Set(
            score.invented.map { "invented \($0)" } + score.deleted.map { "deleted \($0)" }
                + score.lost.map { "lost \($0)" } + score.brokeShape.map { "shape \($0)" })
    }

    private static func row(
        _ off: [QualityLayer], scores: [CaseScore], reference: [CaseScore], heard: [CaseScore]
    ) -> Row {
        let below = zip(scores, zip(reference, heard)).compactMap { score, bounds in
            floorFailures(score).subtracting(floorFailures(bounds.0)).subtracting(floorFailures(bounds.1))
                .isEmpty ? nil : score.caseID
        }
        return Row(
            off: off, cases: scores.count, passed: scores.count(where: \.passed),
            invented: scores.map(\.invented.count).reduce(0, +),
            deleted: scores.map(\.deleted.count).reduce(0, +),
            lost: scores.map(\.lost.count).reduce(0, +),
            brokeShape: scores.map(\.brokeShape.count).reduce(0, +), belowFloor: below)
    }

    private static func rung(_ name: String, outputs: [String], cases: [EvaluationCase]) -> Rung {
        var terms = 0
        var kept = 0
        for (output, testCase) in zip(outputs, cases) {
            for term in testCase.dictionary where writes(term, in: testCase.expected) {
                terms += 1
                if writes(term, in: output) { kept += 1 }
            }
        }
        return Rung(name: name, terms: terms, kept: kept)
    }

    /// Whether `text` holds `term` in the term's own case, as whole words; a term of symbols alone is sought literally.
    static func writes(_ term: String, in text: String) -> Bool {
        let wanted = Scorer.surfaceWords(term)
        guard !wanted.isEmpty else { return text.contains(term) }
        let words = Scorer.surfaceWords(text)
        guard words.count >= wanted.count else { return false }
        return (0...(words.count - wanted.count)).contains { start in
            Array(words[start..<(start + wanted.count)]) == wanted
        }
    }

    private static let contributionHeading = "## Each layer's marginal contribution"

    private static let contributionMethod = """
        Each degraded path paired against the default set over the same cases, as the change with the layers \
        off: the failed-case rate, and invented, deleted and lost words per reference word, in percentage \
        points with the 95% paired-bootstrap interval and the minimum detectable change at 80% power. A \
        false override is a case that fails with the layers on and passes with them off. A path is kept \
        when an improvement's interval excludes zero and neither measure's interval lies wholly below it; \
        the override gate exists to prevent harm, so the meaning-changing errors it prevents are its only \
        measure. Every other path is listed for removal and stays dark until a change shows it pays.
        """

    /// The contribution table with its measured latency, as `make release-quality` adds it to its result.
    package var contributionReport: String {
        [
            Self.contributionHeading, "", Self.contributionMethod, "",
            LayerContribution.table(contributions, latency: true),
        ].joined(separator: "\n") + "\n"

    /// The heading of the page's section on each fallback rung, which the release accuracy report carries.
    public static let rungHeading = "## The user's own words on each fallback rung"

    /// The rung section of a page this type generated, from its heading to the next heading; nil when it has none.
    public static func rungSection(in page: String) -> String? {
        let lines = page.components(separatedBy: "\n")
        guard let start = lines.firstIndex(of: rungHeading) else { return nil }
        let end = lines[(start + 1)...].firstIndex { $0.hasPrefix("#") } ?? lines.endIndex
        let section = lines[start..<end].joined(separator: "\n")
        return section.hasSuffix("\n") ? section : section + "\n"
    }

    /// The matrix as the Markdown page `Docs/degraded-path-matrix.md` holds.
    public var markdown: String {
        var lines = [
            "# Degraded-path matrix",
            "",
            "Generated by `DegradedPathMatrix` from `EvaluationCorpus.all` run through `DictationPipeline` with the",
            "rules tidier; do not edit by hand. Regenerate with",
            "`UTTRFLOW_UPDATE_GOLDEN=1 swift test --filter DegradedPathMatrixTests`.",
            "",
            "Each row switches off one default-on layer of `QualityLayer`, or one with a layer it reads",
            "(`QualityLayer.inputs`). The counts are summed over the cases. A case is below the floor when its",
            "output invents a forbidden word, deletes a reference word, loses a required word or breaks a",
            "required beginning or ending that neither the default set nor the words as heard do; any case",
            "below the floor fails the test.",
            "",
            "| Off | Cases | Passed | Invented | Deleted | Lost | Broke shape | Below floor |",
            "|---|---|---|---|---|---|---|---|",
        ]
        for row in rows {
            lines.append(
                "| \(row.name) | \(row.cases) | \(row.passed) | \(row.invented) | \(row.deleted) | \(row.lost) "
                    + "| \(row.brokeShape) | \(row.belowFloor.count) |")
        }
        lines += [
            "", Self.contributionHeading, "", Self.contributionMethod, "",
            LayerContribution.table(contributions, latency: false),
        ]
        lines += [
            "",
            Self.rungHeading,
            "",
            "A term is a word of a case's dictionary that its reference writes; it is kept when the output writes",
            "it in the entry's case. Each case's dictionary is both the corrector and the words the tidier is",
            "given, as in a dictation. The model rung needs the local model's weights, which this run does not",
            "load.",
            "",
            "| Rung | Terms | Kept | Accuracy |",
            "|---|---|---|---|",
        ]
        for rung in rungs {
            let accuracy = rung.terms == 0 ? 0 : Double(rung.kept) / Double(rung.terms)
            lines.append(
                "| \(rung.name) | \(rung.terms) | \(rung.kept) | \(Int((accuracy * 100).rounded()))% |")
        }
        return lines.joined(separator: "\n") + "\n"
    }
}

/// A tidier that answers a repeated request from its first answer, exact for a tidier that is a pure function.
actor RememberedCleaning: TranscriptCleaning {
    private let cleaner: any TranscriptCleaning
    private var cleaned: [(TransformationRequest, Result<TransformationResult, TransformationError>)] = []
    private var finished: [(String, TransformationRequest, String)] = []
    nonisolated let cleaningSteps: CleaningSteps

    init(_ cleaner: any TranscriptCleaning) {
        self.cleaner = cleaner
        self.cleaningSteps = cleaner.cleaningSteps
    }

    func clean(_ request: TransformationRequest) async throws(TransformationError) -> TransformationResult {
        if let known = cleaned.first(where: { $0.0 == request }) { return try known.1.get() }
        let result: Result<TransformationResult, TransformationError>
        do { result = .success(try await cleaner.clean(request)) } catch { result = .failure(error) }
        cleaned.append((request, result))
        return try result.get()
    }

    func finishMessage(_ text: String, for request: TransformationRequest) async -> String {
        if let known = finished.first(where: { $0.0 == text && $0.1 == request }) { return known.2 }
        let message = await cleaner.finishMessage(text, for: request)
        finished.append((text, request, message))
        return message
    }

    func warm(for situation: Situation?) async {
        await cleaner.warm(for: situation)
    }

    func reserveFinalPiece(_ situation: Situation?) async {
        await cleaner.reserveFinalPiece(situation)
    }
}
