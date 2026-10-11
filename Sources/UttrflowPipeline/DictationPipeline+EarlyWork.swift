// What the early loop holds while the key is down, and what it hands the release pass. See `Docs/early-transcription.md`.
import Foundation
import UttrflowCore

extension DictationPipeline {
    /// One span of a recording: the words a pass finished it with, or audio a later pass still has to do.
    enum Span {
        case done(Piece, span: UUID?)
        case pending(Range<Int>)
        /// Still being tidied when the key came up; joined by the release pass instead of waited on at the hand-off.
        case tidying(Tidying)

        /// A tidy under way and the words it tidies, which the next piece reads before the tidy ends.
        struct Tidying {
            let task: Task<Piece, Never>
            let heard: Transcription
            let span: UUID
        }

        /// The words recognised for this span, or `nil` for audio not yet recognised.
        var heard: Transcription? {
            switch self {
            case .done(let piece, _): piece.heard
            case .pending: nil
            case .tidying(let tidying): tidying.heard
            }
        }
    }

    /// The early loop's state, beside the main sequence rather than in it. See `Docs/early-transcription.md`.
    struct EarlyWork {
        /// Spans the early loop reached while the key was held, and where the audio it consumed ends.
        var spans: [Span] = []
        /// The pieces those spans finished, with the seams between them decided as each arrived.
        var running = RunningMessage()
        var cut = 0
        var lastWindowStart: Int?
        var task: Task<Void, Never>?
        /// A tidy the early loop started but has not yet folded into `spans`, picked up by the release pass at key-up.
        var tidyTask: Span.Tidying?
        /// Whether a piece is being recognised or tidied right now, which is what makes the drain a wait worth timing.
        var pieceInFlight = false
        /// Early recogniser calls still running after their cancelled task has returned.
        var decodesInFlight = 0
        /// Whether the loop is inside a recognition, which key-up lets finish rather than cancel.
        var recognising = false
        var context: AppContext?
        /// A microphone opened while a modifier press settles, before it belongs to a dictation.
        var pendingCapture: Task<Void, Never>?
        var pendingCaptureElapsed: (@Sendable () -> Duration)?
        /// Text from an unconfirmed paste, checked at the caret before another dictation starts.
        var pendingInsertion: String?
        var readsSettled = 0

        /// Clears what a previous dictation left, before the loop for this one starts.
        mutating func begin() {
            spans = []
            running = RunningMessage()
            cut = 0
            lastWindowStart = nil
            tidyTask = nil
            context = nil
        }

        /// Stops the loop and drops everything it reached.
        mutating func cancel() {
            task?.cancel()
            task = nil
            begin()
            pieceInFlight = false
        }

        /// Returns what the drained loop reached and clears it, a tidy still running joining as its last span.
        mutating func handOff() -> (
            spans: [Span], running: RunningMessage, cut: Int, lastWindowStart: Int?, context: AppContext?
        ) {
            var handed = spans
            if let tidyTask { handed.append(.tidying(tidyTask)) }
            let result = (handed, running, cut, lastWindowStart, context)
            task = nil
            begin()
            pieceInFlight = false
            return result
        }
    }

    /// What the early loop hands over: the spans it cut and the message they make, the audio left, the screen it read.
    struct Takeover {
        let spans: [Span]
        let running: RunningMessage
        let remainder: [Range<Int>]
        let context: AppContext?
        /// What the early loop has not decoded at key-up, or `nil` when its pieces are dropped.
        let backlog: WorkAheadBacklog?
    }

    // MARK: Working ahead

    /// Resolves the screen, vocabulary, language policy and initial warm session once for this dictation.
    func beginWorkingAhead(_ mine: Int) {
        recordingFieldKind = nil
        forgetTheLastAttempt()
        show(heard: nil)
        early.begin()
        early.task = Task { [cleaner = runningCleaner, overrides = runningOverrides] in
            let seeing = await self.earlyContextRead(mine)
            guard self.isStillRunning(mine) else { return }
            await self.resolveDictationContext(seeing, cleaner: cleaner, overrides: overrides)
            await self.workAhead(mine)
        }
    }

    /// Transcribes each piece the moment a pause ends it and tidies it beside the next one, until the key is released.
    func workAhead(_ mine: Int) async {
        while state == .recording, generation == mine, !wasCancelled(mine), !Task.isCancelled {
            try? await pollClock.sleep(for: earlyPoll)
            guard state == .recording, generation == mine, !wasCancelled(mine), !Task.isCancelled
            else { return }

            // One sample before the cut is kept, so a later piece is never taken for the whole recording.
            let lead = early.cut > 0 ? 1 : 0
            let audio = await capture.capturedSoFar(from: early.cut - lead)
            guard
                let cut = runningWindowing.nextCut(
                    in: audio.samples, sampleRate: audio.sampleRate, from: lead,
                    boundaries: audio.discontinuities)
            else { continue }
            let start = early.cut
            let end = early.cut - lead + cut

            // Keep the previous tidy in its span while the next piece is recognised.
            if let earlyTidy = early.tidyTask {
                early.spans.append(.tidying(earlyTidy))

                early.tidyTask = nil
            }

            let seeing = await earlyContextRead(mine)
            if dictationContext == nil {
                await resolveDictationContext(seeing, cleaner: runningCleaner, overrides: runningOverrides)
            }
            // Recognition only; a key released mid-tidy is not held to this, since the tidy runs on past it.
            early.pieceInFlight = true
            early.decodesInFlight += 1
            early.recognising = true
            defer { early.recognising = false }
            let heard: Transcription?
            do {
                heard = try await transcribe(
                    audio, lead..<cut, biasedTowards: await vocabulary(mine, seeing: seeing),
                    recording: NoOpMetricsRecorder(), skippingAMiss: false, for: mine)
            } catch {
                early.decodesInFlight -= 1
                guard generation == mine, !wasCancelled(mine) else { return }
                // A failed piece is left for the end, where it is reported; the rest still work ahead.
                early.spans.append(.pending(early.cut..<end))
                early.cut = end
                early.lastWindowStart = start
                early.pieceInFlight = false
                continue
            }
            early.decodesInFlight -= 1
            guard generation == mine, !wasCancelled(mine) else { return }
            // Cut here, before the tidy, so a key-up mid-tidy still knows what audio is left to recognise.
            early.cut = end
            early.lastWindowStart = heard == nil ? nil : start
            if let heard {
                // The piece before is read as heard, which every path has once it is recognised.
                let preceding = early.spans.last?.heard
                let previousTidy = early.spans.reversed().compactMap { span in
                    if case .tidying(let tidying) = span { return tidying.task }
                    return nil
                }.first
                let span = UUID()
                let tidy = Task {
                    if let previousTidy { _ = await previousTidy.value }
                    guard !Task.isCancelled else {
                        return Piece(
                            heard: heard, corrected: .unchanged(heard.text),
                            cleaned: TransformationResult(text: heard.text, producedBy: .untidied))
                    }
                    return await Self.$tidiedSpan.withValue(span) {
                        await self.finish(
                            heard, seeing: seeing, correctionSeeing: seeing, after: preceding,
                            recording: NoOpMetricsRecorder(), for: mine)
                    }
                }
                early.tidyTask = Span.Tidying(task: tidy, heard: heard, span: span)
                // Warm for the next piece after this one finishes, without making key-up wait for warm-up.
                Task {
                    let piece = await tidy.value
                    guard self.state == .recording, self.generation == mine,
                        !self.wasCancelled(mine)
                    else { return }
                    let situation =
                        self.dictationContext?.situation
                        ?? SituationResolver.resolve(from: seeing, overrides: self.runningOverrides)
                    self.early.running.fold(piece, going: situation)
                    self.showFinished(piece)
                    await self.runningCleaner.warm(
                        for: SituationResolver.resolve(
                            from: seeing, overrides: self.runningOverrides))
                }
            }
            early.pieceInFlight = early.tidyTask != nil
        }
    }
}
