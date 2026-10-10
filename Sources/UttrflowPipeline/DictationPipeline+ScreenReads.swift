// Screen reads: what the pipeline reads of the screen, when, and which read a piece of work is judged against.
import UttrflowAI
import UttrflowCore

extension DictationPipeline {
    /// Resolves the values every piece shares, after the single screen read has settled.
    func resolveDictationContext(
        _ app: AppContext, cleaner: any TranscriptCleaning, overrides: DestinationOverrides
    ) async {
        recordingDestination = app
        let situation =
            recordingFieldKind.map {
                Situation(app: app, insertion: app.insertionPoint, destination: $0)
            } ?? SituationResolver.resolve(from: app, overrides: overrides)
        let words = await speechWords(app)
        let fixedCorrector = await corrector.fixed(for: app)
        dictationWords = words
        dictationContext = DictationContext(
            app: app, situation: situation, listening: ListeningLanguages(profile: runningProfile),
            vocabulary: words, profile: runningProfile, corrector: fixedCorrector)
        await cleaner.warm(for: situation)
    }

    /// The words every piece of this dictation is biased towards, ranked once and then remembered.
    func vocabulary(_ mine: Int, seeing context: AppContext) async -> [String] {
        if let dictationContext { return dictationContext.vocabulary }
        if let dictationWords { return dictationWords }
        let words = await speechWords(context)
        // A cancelled dictation's words are not kept for the one now under way.
        guard isStillRunning(mine) else { return words }
        dictationWords = words
        return words
    }

    /// The words this dictation ranked once, or none when it never read a screen to rank them against.
    var rankedWords: [String] { dictationContext?.vocabulary ?? dictationWords ?? [] }

    /// The screen as it was while the key was held, read once for every early piece.
    func earlyContextRead(_ mine: Int) async -> AppContext {
        if let seen = early.context { return seen }
        let read: AppContext
        if let pending = early.pendingInsertion {
            read = await contextAfterPendingInsertion(pending, for: mine)
        } else {
            read = await readContext()
        }
        // Counted before the decision below, which runs without a suspension, so a waiter sees it made.
        early.readsSettled += 1
        // A read the user cancelled belongs to no dictation: the one now under way read its own screen.
        guard isStillRunning(mine) else { return read }
        early.context = read
        insertedInto = read.applicationName
        insertedIntoIdentifier = read.bundleIdentifier
        destinationIsSecure = read.isSecure
        return read
    }

    /// Waits for a previous paste to reach the caret before the new dictation captures its context.
    private func contextAfterPendingInsertion(_ text: String, for mine: Int) async -> AppContext {
        let wanted = PendingInsertionConfirmation.collapsed(text)
        var waited = Duration.zero
        while waited < PendingInsertionConfirmation.budget, isStillRunning(mine), !Task.isCancelled {
            let latest = await readContext()
            let preceding = latest.precedingText.map(PendingInsertionConfirmation.collapsed) ?? ""
            if preceding.hasSuffix(wanted) {
                early.pendingInsertion = nil
                return latest
            }
            do { try await clock.sleep(for: PendingInsertionConfirmation.interval) } catch { break }
            waited = min(PendingInsertionConfirmation.budget, waited + PendingInsertionConfirmation.interval)
        }
        guard isStillRunning(mine), !Task.isCancelled else { return AppContext() }
        return await readContext()
    }

    /// Asks what is on screen within what the dictation's screen-read limit has left, so one stuck app is waited on once.
    private func readContext() async -> AppContext {
        let left = StageTimeout.screenRead - screenReads.cost.duration
        guard left > .zero else { return AppContext(unavailable: .timedOut) }
        // Counted before the read begins, so input that lands while it runs outdates it.
        let inputsBefore = await context.inputsSeen()
        let (read, elapsed) = await Self.timed(on: clock) { [context, clock] in
            ((try? await withStageTimeout(left, clock: clock) {
                await context.currentContext()
            }) ?? nil) ?? AppContext(unavailable: .timedOut)
        }
        screenReads.record(read, took: elapsed, inputsBefore: inputsBefore)
        if let rung = read.readRung, let bundleIdentifier = read.bundleIdentifier {
            await metrics.recordContextRead(rung, in: bundleIdentifier)
        }
        return read
    }

    /// Runs `operation` and says how long it took on `clock`.
    private static func timed<Value>(
        on clock: some Clock<Duration>, isolation: isolated (any Actor)? = #isolation,
        _ operation: () async -> Value
    ) async -> (Value, Duration) {
        let start = clock.now
        let value = await operation()
        return (value, start.duration(to: clock.now))
    }

    /// Uses caret text read just before insertion, refusing it when the destination app changed.
    func insertionContextForWrite(matching destination: AppContext?) async -> AppContext {
        // With no key, click or switch since the last read, and no earlier paste still landing, it is the caret now.
        let unchanged =
            early.pendingInsertion == nil ? screenReads.unchanged(inputsNow: await context.inputsSeen()) : nil
        let current = if let unchanged { unchanged } else { await readContext() }
        guard let destination else { return current }
        if let expected = destination.bundleIdentifier, let actual = current.bundleIdentifier {
            return expected == actual ? current : .unknown
        }
        if let expected = destination.applicationName, let actual = current.applicationName {
            return expected == actual ? current : .unknown
        }
        return current
    }

    /// The screen to tidy against, which for a retry is Uttrflow's own window and says nothing.
    func contextFor(_ delivery: Delivery) async -> AppContext {
        switch delivery {
        case .insert, .command:
            let read = await readContext()
            // Kept from this read: by insertion time the user has often switched away.
            insertedInto = read.applicationName
            insertedIntoIdentifier = read.bundleIdentifier
            destinationIsSecure = read.isSecure
            let recordedDestination = early.context ?? dictationContext?.app ?? read
            recordingDestination = recordedDestination
            let fieldKind =
                dictationContext?.situation.destination
                ?? SituationResolver.resolve(from: recordedDestination, overrides: runningOverrides)
                .destination
            if let openRecording {
                await recordings.setDestination(
                    recordedDestination, fieldKind: fieldKind, for: openRecording)
            }
            return read
        case .copy:
            return recordingDestination ?? AppContext()
        }
    }
}

/// Bounds how long a new dictation waits for a previous insertion to reach the caret.
private enum PendingInsertionConfirmation {
    static let budget = Duration.milliseconds(1600)
    static let interval = Duration.milliseconds(40)

    static func collapsed(_ text: String) -> String {
        TextTidy.collapseWhitespace(text)
    }
}
