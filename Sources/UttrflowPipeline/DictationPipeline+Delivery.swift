// Delivery: what happens to the words once they are heard, from landing them to learning from them.
import UttrflowAI
import UttrflowCore
import struct Foundation.UUID

extension DictationPipeline {
    /// Joins the pieces, re-cases them for where the caret is now, inserts or copies them, then counts and learns.
    func deliver(
        _ message: RunningMessage, from audio: AudioSamples, read appContext: AppContext?,
        recording tally: StageTally, delivery: Delivery, for mine: Int
    ) async {
        // Silence is not a fault, but returning quietly to idle would look like a broken app.
        guard !message.pieces.isEmpty else {
            await reportCleaning(for: delivery)
            await fail(Self.silence(missedPieces > 0 ? .speechWithoutWords : .nothingHeard, in: audio))
            return
        }
        let seen = appContext ?? AppContext()
        // Every piece is done while recording, and the screen it is read against still applies.
        if state == .transcribing { transition(to: .tidying) }
        let joining =
            dictationContext?.situation
            ?? SituationResolver.resolve(from: seen, overrides: runningOverrides)
        // Inserting a blank would delete the user's selection, so it is refused like silence.
        let joinedPieces = await join(
            message, going: joining, seeing: seen, vocabulary: rankedWords, recording: tally, for: mine)
        guard !wasCancelled(mine) else { return }
        // After the join, so a seam correction or snippet expansion that gave up is in the account.
        await reportCleaning(for: delivery)
        guard let joined = joinedPieces else {
            await fail(DictationFailure(SpeechEngineError.nothingHeard))
            return
        }
        let (whole, joiningFormatter, expanded) = (joined.whole, joined.formatter, joined.expanded)
        let finalEnforcement = LatinScript.enforcement(of: expanded.text)
        var output = finalEnforcement.text
        guard output.hasRecognisableContent else {
            await fail(DictationFailure(SpeechEngineError.nothingHeard))
            return
        }

        if delivery == .command {
            await runCommand(whole.heard, seeing: appContext, generation: mine)
            return
        }

        let insertionContext: AppContext
        if delivery == .insert {
            insertionContext = await insertionContextForWrite(matching: appContext)
            guard !wasCancelled(mine) else { return }
            output = recased(
                output, writingInto: insertionContext, casedFor: seen, by: joiningFormatter,
                heard: whole.heard.text, cleanedBy: whole.cleaned.producedBy)
        } else {
            insertionContext = seen
        }

        // Pads the words with a space where the field's surrounding text would otherwise join them.
        let landing = SituationResolver.resolve(from: insertionContext, overrides: runningOverrides)
        let consequence = DestinationFormatter.standard(for: landing).consequence
        let toWrite = insertionContext.insertionPoint.paddedBoundary(
            for: OutputSafety.checked(output, consequence: consequence).text, in: landing.destination)

        let changes = AppliedChanges(
            corrections: DictationCorrection.locating(
                whole.corrected.corrections, from: whole.corrected.text, in: toWrite),
            snippets: expanded.snippets,
            entriesTaken: whole.cleaned.entriesTaken,
            // The unrewritten sentence, which is the space the corrections' word ranges index.
            spokenWords: whole.heard.text.spokenWords.count,
            // A snippet changes the word count, so the ledger's positions hold only when none fired.
            changeLedger: expanded.snippets.isEmpty ? whole.cleaned.changeLedger : nil,
            scriptConversions: joined.scriptConversions + ScriptConversions(finalEnforcement),
            heard: whole.heard.text)
        guard
            let attempt = await insert(
                toWrite, cleanedBy: whole.cleaned.producedBy, changes: changes,
                doubtful: DoubtfulWordsOutcome.locating(whole.heard.saying(whole.corrected), in: toWrite),
                delivery: delivery, generation: mine, recording: tally,
                unavailableEngines: whole.cleaned.cleaning?.unavailableEngines ?? [],
                destination: InsertionDestination(
                    applicationName: appContext?.applicationName,
                    bundleIdentifier: appContext?.bundleIdentifier,
                    processIdentifier: appContext?.processIdentifier, field: appContext?.field))
        else { return }
        // Read before the next await, since the next dictation may start once these words are on screen.
        let wasSecure = destinationIsSecure
        // A snippet's caret moves only in the field that took the words, verified there; otherwise it stays at the end.
        if delivery == .insert, let back = expanded.caretBack(inWritten: toWrite), back > 0 {
            _ = await inserter.placeCaret(back: back)
        }
        await learn(
            from: attempt, wrote: toWrite, changes: changes, heard: whole.heard.text,
            read: appContext, seeing: seen, intoSecureField: wasSecure)
    }

    /// Re-cases tidied words whose caret or destination moved since they were cased; otherwise returns them as they are.
    private func recased(
        _ output: String, writingInto insertionContext: AppContext, casedFor seen: AppContext,
        by joiningFormatter: DestinationFormatter, heard: String, cleanedBy producedBy: TransformerKind
    ) -> String {
        let situation = SituationResolver.resolve(from: insertionContext, overrides: runningOverrides)
        let formatter = DestinationFormatter.standard(for: situation)
        // Re-casing is owed only for tidied words whose caret or destination moved since they were cased.
        let caretMoved =
            insertionContext.insertionPoint.sentenceState != seen.insertionPoint.sentenceState
            || formatter.firstWord != joiningFormatter.firstWord
            || formatter.destination != joiningFormatter.destination
        guard producedBy != .untidied, caretMoved else { return output }
        return
            FirstWordPass(
                policy: formatter.firstWord, state: insertionContext.insertionPoint.sentenceState,
                onScreen: [
                    insertionContext.documentName, insertionContext.selectedText,
                    insertionContext.precedingText, insertionContext.followingText,
                ].compactMap { $0 }, heard: heard,
                capitaliseCalendarWords: formatter.firstWord == .fromInsertionPoint
                    && formatter.destination != .codeEditor,
                vocabulary: rankedWords,
                keepsCommandCase: formatter.keepsCommandCase
            )
            .apply(Draft(keepingLineBreaks: output)).text
    }

    /// Counts and learns from words once they are known to be on screen, where the user allows it.
    private func learn(
        from attempt: InsertionAttempt, wrote toWrite: String, changes: AppliedChanges, heard: String,
        read appContext: AppContext?, seeing seen: AppContext, intoSecureField wasSecure: Bool
    ) async {
        // An unconfirmed paste is not proof the words reached the user, so nothing is learnt from it yet.
        guard attempt.arrival != .unconfirmed else {
            early.pendingInsertion = toWrite
            return
        }
        // An application the user declined is learned nothing from, by counting or by the dictionary.
        let learnedFrom = landedIn(attempt)?.bundleIdentifier ?? appContext?.bundleIdentifier
        guard await consent.mayLearn(from: learnedFrom) else { return }
        // A secret is not a word to learn or count, by the same gate that keeps it out of History.
        guard let kept = KeptWords.of(toWrite, intoSecureField: wasSecure) else { return }
        // Both run after the words are on screen, and neither can fail the dictation. §19.
        await count(changes, writtenIn: kept)
        // A destination reported by the inserter wins over a screen read made before the switch.
        if let landedID = landedIn(attempt)?.bundleIdentifier,
            let readID = appContext?.bundleIdentifier, landedID != readID
        {
            return
        }
        await learnWords(heard: heard, wrote: toWrite, seeing: seen)
    }

    /// Puts the finished text where the user was typing, answering how it arrived, or nil on failure.
    private func insert(
        _ text: String, cleanedBy: TransformerKind, changes: AppliedChanges,
        doubtful: DoubtfulWordsOutcome = .notAvailable, delivery: Delivery, generation mine: Int,
        recording tally: StageTally, unavailableEngines: [CleaningRecord.UnavailableEngine],
        destination: InsertionDestination
    ) async -> InsertionAttempt? {
        let inserter = delivery == .copy ? clipboard : self.inserter
        // Said before the words are handed over, because the app takes its own time to show them.
        transition(to: .inserting(into: insertedInto))
        do {
            let inserted = try await MetricsFanOut([metrics, tally]).measuringInTime(
                .insertion, clock: clock, generation: mine
            ) {
                try await withStageTimeout(StageTimeout.insertion, clock: clock) {
                    if delivery == .copy {
                        return try await inserter.insert(text)
                    }
                    return try await inserter.insert(text, targeting: destination)
                }
            }
            // A cancel during the write already ended the dictation, so nothing more is shown or learnt.
            guard !wasCancelled(mine) else { return nil }
            // Either way the dictation has to end, so the next one can begin.
            guard let attempt = inserted else {
                throw delivery == .copy
                    ? TextInsertionError.clipboardUnavailable
                    : TextInsertionError.insertionTimedOut
            }
            // A field found secure at the write counts from here on, before anything is learnt from it.
            if attempt.intoSecureField { destinationIsSecure = true }
            let slowCause = await timeWait(recorded: tally)
            await settleRecording(wordsLost: MissedSpeech.isMissing(missedPieces))
            transition(
                to: .inserted(
                    DictationOutcome(
                        text: text, method: attempt.method, cleanedBy: cleanedBy,
                        insertedInto: landedIn(attempt)?.applicationName ?? insertedInto,
                        insertedIntoIdentifier: landedIn(attempt)?.bundleIdentifier
                            ?? insertedIntoIdentifier,
                        spokenFor: spokenFor, changes: changes,
                        fromRecording: delivery == .copy, arrival: attempt.arrival,
                        intoSecureField: destinationIsSecure, missedPieces: missedPieces,
                        unavailableEngines: unavailableEngines, doubtful: doubtful,
                        slowCause: slowCause)))
            return attempt
        } catch {
            guard !wasCancelled(mine) else { return nil }
            // The words survive the failure: the interface can still offer them.
            await fail(DictationFailure(error, transcript: text))
            return nil
        }
    }

    /// Runs a command-key utterance on the selection as it stands now; the words are never typed.
    private func runCommand(
        _ transcription: Transcription, seeing appContext: AppContext?, generation mine: Int
    ) async {
        let target = await insertionContextForWrite(matching: appContext)
        guard !wasCancelled(mine) else { return }
        // Dictionary spellings apply to command words as to dictation, so "with Y" writes a term as the user filed it.
        let proposals = (try? await runningCorrector.corrections(for: transcription, seeing: target)) ?? []
        let corrected = DictationCorrection.applying(proposals, to: transcription.text).text
        // The words a replace writes are dictation, so they are tidied as a phrase; the command words are not.
        let heard = await ReplaceCommand.tidyingReplacement(in: corrected) { words in
            LatinScript.enforced(await tidiedPhrase(Transcription(text: words), seeing: target) ?? words)
        }
        guard !wasCancelled(mine) else { return }
        do {
            let outcome = try await commands.run(heard, on: target)
            guard !wasCancelled(mine) else { return }
            guard case .ran(let said) = outcome else { return await fail(.commandNotUnderstood(heard)) }
            await settleRecording(wordsLost: false)
            transition(to: .executed(said))
        } catch {
            guard !wasCancelled(mine) else { return }
            await fail(DictationFailure(error, transcript: heard))
        }
    }

    /// Where the words actually went, which is the insertion's to say; the recording's read is the fallback.
    private func landedIn(_ attempt: InsertionAttempt) -> InsertionDestination? {
        guard let destination = attempt.destination, destination.isKnown else { return nil }
        return destination
    }

    /// Tells the stores what this dictation used, once the words are safely on screen.
    private func count(_ changes: AppliedChanges, writtenIn text: String) async {
        // Once per entry and in one batch: the store counts dictations an entry appeared in, not words, by any path.
        var counted: Set<UUID> = []
        let entries = (changes.corrections.map(\.entryID) + changes.entriesTaken)
            .filter { counted.insert($0).inserted }
        if !entries.isEmpty || !text.isEmpty {
            try? await learner.recordUse(ofEntries: entries, writtenIn: text)
        }

        guard !changes.snippets.isEmpty else { return }
        // One batch, duplicates left in, because the store counts firings not dictations.
        try? await learner.recordUse(ofSnippets: changes.snippets.map(\.snippetID))
    }

    /// Offers the dictionary what this dictation showed, once its words have landed.
    private func learnWords(heard: String, wrote: String, seeing context: AppContext) async {
        guard !context.isEmpty else { return }
        try? await vocabulary.learn(heard: heard, wrote: wrote, seeing: context)
    }
}
