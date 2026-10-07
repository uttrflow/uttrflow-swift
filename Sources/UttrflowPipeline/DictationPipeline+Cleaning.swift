// The stages after recognition: dictionary, tidier, message passes and snippets.
import UttrflowAI
public import UttrflowCore

extension DictationPipeline {
    /// Runs the dictionary and the tidier over one recognised piece.
    func finish(
        _ heard: Transcription, seeing appContext: AppContext,
        correctionSeeing correctionContext: AppContext, finalPiece: Bool = false,
        after preceding: Transcription? = nil,
        recording metrics: any MetricsRecording, for mine: Int,
        correcting corrector: (any WordCorrecting)? = nil
    ) async -> Piece {
        // The dictionary before the tidier: a correction is argued from the sentence as heard.
        let corrected = await correct(
            heard, seeing: correctionContext, recording: metrics, correcting: corrector, for: mine)
        let cleaned = await tidy(
            heard, saying: corrected, seeing: appContext, finalPiece: finalPiece,
            after: preceding, recording: metrics, for: mine)
        return Piece(heard: heard, corrected: corrected, cleaned: cleaned)
    }

    /// Puts the user's own spellings in, leaving the transcript alone if it cannot. §19.
    func correct(
        _ transcription: Transcription, seeing appContext: AppContext,
        recording metrics: any MetricsRecording, acrossSeams seams: PieceSeams? = nil,
        correcting chosen: (any WordCorrecting)? = nil, for mine: Int? = nil
    ) async -> CorrectedTranscript {
        // Moving a word needs evidence, candidates, a score and the gate, so any one off leaves the words as heard.
        let correcting: [QualityLayer] = [.evidenceCapture, .candidateGeneration, .scoring, .overrideGate]
        guard correcting.allSatisfy(layers.isOn) else { return .unchanged(transcription.text) }
        let corrector = chosen ?? runningCorrector
        do {
            let timed =
                try await metrics.measuringInTime(.correction, clock: clock) {
                    try await withStageTimeout(StageTimeout.correction, clock: clock) { [corrector] in
                        if let seams {
                            try await corrector.weighAcrossSeams(transcription, at: seams, seeing: appContext)
                        } else {
                            try await corrector.weigh(transcription, seeing: appContext)
                        }
                    }
                }
            guard let weighed = timed else {
                skipped(.correction, .timeout, for: mine)
                return .unchanged(transcription.text)
            }
            // The commonest answer, and not worth rebuilding a string to arrive at itself.
            guard !weighed.corrections.isEmpty else {
                return CorrectedTranscript.unchanged(transcription.text).holding(weighed.held)
            }
            return DictationCorrection.applying(weighed.corrections, to: transcription.text)
                .holding(weighed.held)
        } catch {
            skipped(.correction, .error, for: mine)
            return .unchanged(transcription.text)
        }
    }

    /// Gives the dictionary a joined transcript, keeping only proposals that cross a piece boundary.
    func correctAcrossSeams(
        _ pieces: [Piece], in joined: Piece, seeing appContext: AppContext,
        recording metrics: any MetricsRecording, correcting corrector: (any WordCorrecting)? = nil,
        for mine: Int? = nil
    ) async -> Piece {
        guard pieces.count > 1 else { return joined }
        let boundaries = pieces.dropLast().reduce(into: [Int]()) { result, piece in
            result.append((result.last ?? 0) + piece.heard.text.spokenWordCount)
        }
        let seams = PieceSeams(
            boundaries: boundaries, changed: joined.corrected.corrections.map(\.wordRange))
        let proposed = await correct(
            joined.heard, seeing: appContext, recording: metrics, acrossSeams: seams,
            correcting: corrector, for: mine
        ).corrections
        let crossings = proposed.filter { seams.admits($0.wordRange) }
        guard !crossings.isEmpty else { return joined }

        var correctedText = joined.corrected.text
        var cleanedText = joined.cleaned.text
        var added: [DictationCorrection] = []
        var shift = 0
        for correction in crossings.sorted(by: { $0.wordRange.lowerBound < $1.wordRange.lowerBound }) {
            let earlier = joined.corrected.corrections.filter {
                $0.wordRange.lowerBound < correction.wordRange.lowerBound
            }
            let priorShift = earlier.reduce(0) {
                $0 + $1.wrote.spokenWords.count - $1.wordRange.count
            }
            let correctedStart = correction.wordRange.lowerBound + priorShift + shift
            let correctedEnd = correction.wordRange.upperBound + priorShift + shift
            let correctedRange = correctedStart..<correctedEnd
            let replacement = correction.wrote.spokenWords
                .map { String(SpokenToken($0).core) }
                .joined(separator: " ")
            let mapped = Self.correction(correction, at: correctedRange, writing: replacement)
            let applied = DictationCorrection.applying([mapped], to: correctedText)
            guard applied.corrections.count == 1 else { continue }
            correctedText = applied.text
            let actual = applied.corrections[0]
            added.append(Self.correction(actual, at: correction.wordRange))
            shift += actual.wrote.spokenWords.count - correction.wordRange.count

            let heardShape = Self.correction(correction, at: correction.wordRange, writing: correction.heard)
            let located = DictationCorrection.locating(
                [heardShape], from: joined.heard.text, in: cleanedText
            ).first?.writtenWordIndex
            if let located {
                let cleanedRange = located..<(located + correction.wordRange.count)
                cleanedText =
                    DictationCorrection.applying(
                        [Self.correction(correction, at: cleanedRange)], to: cleanedText
                    ).text
            }
        }
        guard !added.isEmpty else { return joined }
        return Piece(
            heard: joined.heard,
            corrected: CorrectedTranscript(
                text: correctedText, corrections: joined.corrected.corrections + added,
                held: joined.corrected.held),
            cleaned: TransformationResult(
                text: cleanedText, producedBy: joined.cleaned.producedBy,
                cleaning: joined.cleaned.cleaning, entriesTaken: joined.cleaned.entriesTaken))
    }

    static func correction(
        _ correction: DictationCorrection, at range: Range<Int>, writing text: String? = nil
    ) -> DictationCorrection {
        DictationCorrection(
            heard: correction.heard, wrote: text ?? correction.wrote, wordRange: range,
            entryID: correction.entryID, reason: correction.reason,
            heardConfidence: correction.heardConfidence, evidence: correction.evidence)
    }

    /// Tidies the transcript, falling back to exactly what was said. The only optional stage.
    func tidy(
        _ transcription: Transcription, saying corrected: CorrectedTranscript,
        seeing appContext: AppContext, finalPiece: Bool = false, after preceding: Transcription? = nil,
        recording metrics: any MetricsRecording, for mine: Int?
    ) async -> TransformationResult {
        let text = corrected.text
        // Every piece of a dictation is tidied against the one screen read, so all see one situation.
        let (situation, profile) = tidyingFrame(seeing: appContext)
        let request = TransformationRequest(
            transcription: transcription.saying(corrected), context: appContext,
            profile: profile, situation: situation, scope: .piece, precedingPiece: preceding?.text)
        if finalPiece { await runningCleaner.reserveFinalPiece(situation) }
        // Not `.rules`: no pass ran over these words, and a record that says otherwise cannot be read.
        let untidied = TransformationResult(text: text, producedBy: .untidied)
        guard layers.isOn(.formatting) else { return untidied }

        do {
            let tidied = try await metrics.measuringInTime(.transformation, clock: clock) {
                try await withStageTimeout(StageTimeout.transformation, clock: clock) {
                    [cleaner = runningCleaner] in
                    try await cleaner.clean(request)
                }
            }
            // A language model that never answers costs the tidying, never the words.
            guard let tidied else {
                skipped(.tidy, .timeout, for: mine)
                return untidied
            }
            // A cancelled dictation's record is not merged into the one now under way.
            if let cleaning = tidied.cleaning, let mine { keep(cleaning, for: mine) }
            return tidied
        } catch {
            skipped(.tidy, .error, for: mine)
            return untidied
        }
    }

    /// Asks the cleaner for the message's own passes once over the joined pieces; untidied words stay as they were.
    func finishMessage(
        _ joined: Piece, going situation: Situation, seeing appContext: AppContext
    ) async -> Piece {
        guard joined.cleaned.producedBy != .untidied else { return joined }
        let request = TransformationRequest(
            transcription: joined.heard.saying(joined.corrected), context: appContext,
            profile: runningProfile,
            situation: situation, vocabulary: dictationWords ?? [])
        let finished = await runningCleaner.finishMessage(joined.cleaned.text, for: request)
        return Piece(
            heard: joined.heard, corrected: joined.corrected,
            cleaned: TransformationResult(
                text: finished, producedBy: joined.cleaned.producedBy,
                cleaning: joined.cleaned.cleaning, entriesTaken: joined.cleaned.entriesTaken))
    }

    /// Recognised pieces cleaned as one dictation's are, from the dictionary to the snippets; nothing is inserted.
    public func clean(_ heard: [Transcription], seeing appContext: AppContext) async -> CleanedDictation {
        let (situation, _) = tidyingFrame(seeing: appContext)
        // One corrector for the whole dictation, so its pieces share one correction budget.
        let corrector = await runningCorrector.fixed()
        var pieces: [Piece] = []
        for (index, piece) in heard.enumerated() {
            // A dictation number never under way, so no piece's record joins a real dictation's account.
            pieces.append(
                await finish(
                    piece, seeing: appContext, correctionSeeing: appContext,
                    finalPiece: index == heard.indices.last, after: heard[..<index].last,
                    recording: NoOpMetricsRecorder(),
                    for: generation + 1, correcting: corrector))
        }
        let joined = await join(
            pieces, going: situation, seeing: appContext, recording: NoOpMetricsRecorder(),
            correcting: corrector, for: generation + 1)
        return CleanedDictation(
            pieces: pieces.map(\.cleaned.text),
            text: joined.map { LatinScript.enforced($0.expanded.text) })
    }

    /// The pieces joined, corrected across their seams, finished as a message and expanded; nil when nothing is writable.
    func join(
        _ pieces: [Piece], going situation: Situation, seeing appContext: AppContext,
        recording metrics: any MetricsRecording, correcting corrector: (any WordCorrecting)? = nil,
        for mine: Int? = nil
    ) async -> JoinedDictation? {
        let formatter = DestinationFormatter.standard(for: situation)
        let pieces = await rejoiningUnits(
            pieces, under: formatter, going: situation, seeing: appContext, recording: metrics, for: mine)
        let joined = PieceJoiner.join(pieces, under: formatter, steps: runningCleaner.cleaningSteps)
        let correctedAtSeams = await correctAcrossSeams(
            pieces, in: joined, seeing: appContext, recording: metrics, correcting: corrector, for: mine)
        let whole = await finishMessage(correctedAtSeams, going: situation, seeing: appContext)
        // Dictation writes Latin letters only, including snippet expansions. See `Docs/latin-output.md`.
        let enforcement = LatinScript.enforcement(of: whole.cleaned.text)
        let written = PreferredSpelling.applied(to: enforcement.text, preferring: await spellings())
        guard written.hasRecognisableContent else { return nil }
        // Joiner-added stops do not separate a spoken snippet; the speaker's stops still do.
        let snippetInput = PieceJoiner.snippetInput(pieces, under: formatter, using: written)
        let expanded = await expand(
            written, matching: snippetInput, laidOut: formatter.layout, for: mine)
        return JoinedDictation(
            whole: whole, formatter: formatter, expanded: expanded,
            scriptConversions: ScriptConversions(enforcement))
    }

    /// Pieces cut inside a spoken number, time or address, tidied again as one piece so the unit is read whole.
    func rejoiningUnits(
        _ pieces: [Piece], under formatter: DestinationFormatter, going situation: Situation,
        seeing appContext: AppContext, recording metrics: any MetricsRecording, for mine: Int?
    ) async -> [Piece] {
        let digits = situation.digits(for: formatter)
        var groups: [[Piece]] = []
        for piece in pieces {
            if let previous = groups.last?.last,
                PieceJoiner.unitRunsAcross(
                    previous.corrected.text, into: piece.corrected.text, under: formatter, digits: digits)
            {
                groups[groups.count - 1].append(piece)
            } else {
                groups.append([piece])
            }
        }
        guard groups.count < pieces.count else { return pieces }
        var rejoined: [Piece] = []
        for group in groups {
            guard group.count > 1 else {
                rejoined += group
                continue
            }
            let whole = PieceJoiner.join(group, under: formatter)
            let cleaned = await tidy(
                whole.heard, saying: whole.corrected, seeing: appContext, recording: metrics, for: mine)
            rejoined.append(Piece(heard: whole.heard, corrected: whole.corrected, cleaned: cleaned))
        }
        return rejoined
    }

    /// What a phrase said on its own reaches the snippet matcher as: the dictionary, then the rules, no model.
    public func arrival(ofSpoken phrase: String) async -> String {
        let heard = Transcription(text: phrase)
        let nowhere = AppContext()
        let corrected = await correct(heard, seeing: nowhere, recording: NoOpMetricsRecorder())
        guard layers.isOn(.formatting) else { return LatinScript.enforced(corrected.text) }
        let situation = SituationResolver.resolve(from: nowhere, overrides: runningOverrides)
        let spoken = heard.saying(corrected)
        let piece = TransformationRequest(
            transcription: spoken, context: nowhere, profile: runningProfile, situation: situation,
            scope: .piece)
        let rules = RuleBasedTransformer(steps: runningCleaner.cleaningSteps)
        guard let tidied = try? await rules.transform(piece) else {
            return LatinScript.enforced(corrected.text)
        }
        let message = TransformationRequest(
            transcription: spoken, context: nowhere, profile: runningProfile, situation: situation)
        return LatinScript.enforced(await runningCleaner.finishMessage(tidied.text, for: message))
    }

    /// Expands the user's snippets under the destination's layout, treating a blank expansion as nothing to do.
    func expand(
        _ text: String, matching seamInput: SeamSnippetInput, laidOut layout: LayoutPolicy,
        for mine: Int? = nil
    ) async -> ExpandedTranscript {
        do {
            let timed = try await metrics.measuringInTime(.expansion, clock: clock) {
                try await withStageTimeout(StageTimeout.expansion, clock: clock) { [snippets] in
                    try await snippets.expand(seamInput.removingSeamStops())
                }
            }
            guard let expanded = timed else {
                skipped(.expansion, .timeout, for: mine)
                return .unchanged(text)
            }
            guard !expanded.text.isBlank else { return .unchanged(text) }
            // A line break is Return in a single-line field, so an expansion's breaks join as the tidier's did.
            let restored = seamInput.restoringUnconsumedStops(in: expanded)
            return layout.contains(.singleLine) ? restored.onOneLine : restored
        } catch {
            skipped(.expansion, .error, for: mine)
            return .unchanged(text)
        }
    }
}

extension DictationPipeline {
    /// Notes in the dictation's account that a stage passed its words on unchanged; outside a dictation, nothing.
    func skipped(
        _ stage: CleaningRecord.SkippedStage.Stage, _ reason: CleaningRecord.SkippedStage.Reason,
        for mine: Int?
    ) {
        if let mine { keep(.skipped(stage, reason), for: mine) }
    }
}

/// What the joined pieces of one dictation became, before anything is inserted.
struct JoinedDictation: Sendable {
    let whole: Piece
    let formatter: DestinationFormatter
    let expanded: ExpandedTranscript
    /// What script enforcement converted before the snippets expanded.
    let scriptConversions: ScriptConversions
}

/// Each piece as the tidier left it, and the text a dictation of those pieces would insert.
public struct CleanedDictation: Sendable, Equatable {
    public let pieces: [String]
    /// Nil when nothing writable is left, which a dictation refuses as silence.
    public let text: String?
}
