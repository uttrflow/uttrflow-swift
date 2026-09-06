// The Diagnostics page: its rows, the latency figures, reliability, and the plain-text report.
public import Foundation
public import UttrflowCore

/// Whether something the page reports is fine, wants attention, or is not yet known.
public enum DiagnosticsState: Sendable, Equatable {
    /// Nothing to do.
    case good
    /// Something needs the user.
    case attention
    /// Nobody has asked yet.
    case unknown
}

/// One fact about the machine, and what to do if it is the wrong fact.
public struct DiagnosticsRow: Sendable, Equatable, Identifiable {
    /// What the row is about.
    public let title: String
    /// The fact itself.
    public let detail: String
    /// How the fact is coloured.
    public let state: DiagnosticsState
    /// The fix, when the row offers one.
    public let action: MainAction?

    /// The title, which is unique on the page.
    public var id: String { title }

    /// Builds a row; without an action it is only a fact.
    public init(
        title: String, detail: String, state: DiagnosticsState, action: MainAction? = nil
    ) {
        self.title = title
        self.detail = detail
        self.state = state
        self.action = action
    }
}

/// How long one stage of the journey takes, from the times actually recorded.
public struct DiagnosticsStageRow: Sendable, Equatable, Identifiable {
    /// Which stage this row times.
    public let stage: PipelineStage
    /// The stage in the product's words.
    public let title: String
    /// The median, not a mean, so one pathological dictation does not move "what usually happens".
    public let typical: String
    /// The worst one seen, reported as the slowest rather than a percentile over a handful of samples.
    public let slowest: String
    /// This stage's share of the total below, for the bar. Zero to one.
    public let share: Double
    /// How many timings the row rests on.
    public let samples: Int

    /// The stage, which appears once.
    public var id: PipelineStage { stage }

    /// Builds a row from its measurements.
    public init(
        stage: PipelineStage, title: String, typical: String, slowest: String, share: Double,
        samples: Int
    ) {
        self.stage = stage
        self.title = title
        self.typical = typical
        self.slowest = slowest
        self.share = share
        self.samples = samples
    }
}

/// The headline number and what it is made of.
public struct DiagnosticsLatency: Sendable, Equatable {
    /// Prefixed with "at least" while any stage is unmeasured, because a partial total is a floor.
    public let headline: String
    /// Says exactly what the headline is: a sum of typicals, not the typical of any one dictation.
    public let caption: String
    /// One row per stage something has timed.
    public let stages: [DiagnosticsStageRow]
    /// The stages nothing has ever timed, named in a row of their own rather than drawn as zero.
    public let unmeasured: [DiagnosticsRow]

    /// `unmeasured` has no default: "nothing is missing" is a claim a caller has to make.
    public init(
        headline: String, caption: String, stages: [DiagnosticsStageRow],
        unmeasured: [DiagnosticsRow]
    ) {
        self.headline = headline
        self.caption = caption
        self.stages = stages
        self.unmeasured = unmeasured
    }
}

/// Whether a downloaded speech model is on the machine; described, never named, per §16.
public struct DiagnosticsModelPresence: Sendable, Equatable {
    /// Whether the model is there.
    public let isInstalled: Bool
    /// What it occupies, when it is there.
    public let bytesOnDisk: Int64?
    /// Whether it recognises every language or only English.
    public let isMultilingual: Bool

    /// Builds the description.
    public init(isInstalled: Bool, bytesOnDisk: Int64?, isMultilingual: Bool) {
        self.isInstalled = isInstalled
        self.bytesOnDisk = bytesOnDisk
        self.isMultilingual = isMultilingual
    }
}

/// Everything the diagnostics page is drawn from.
public struct DiagnosticsSnapshot: Sendable, Equatable {
    /// Which engines are configured, in preference order.
    public let engines: EngineConfiguration
    /// What each clean-up engine answered when last asked whether it can run here; absent means never asked.
    public let transformerAvailability: [TransformerKind: Bool]
    /// Absent until the store has been consulted.
    public let speechModel: DiagnosticsModelPresence?
    /// What macOS has granted, for every permission asked about.
    public let permissions: [PermissionKind: PermissionStatus]
    /// Every stage timing recorded since the app started.
    public let measurements: [StageMeasurement]
    /// What the clean-up steps did to the last dictation, absent until one has been tidied.
    public let cleaning: CleaningRecord?

    /// Builds a snapshot; everything defaults to not yet checked.
    public init(
        engines: EngineConfiguration = .default,
        transformerAvailability: [TransformerKind: Bool] = [:],
        speechModel: DiagnosticsModelPresence? = nil,
        permissions: [PermissionKind: PermissionStatus] = [:],
        measurements: [StageMeasurement] = [],
        cleaning: CleaningRecord? = nil
    ) {
        self.engines = engines
        self.transformerAvailability = transformerAvailability
        self.speechModel = speechModel
        self.permissions = permissions
        self.measurements = measurements
        self.cleaning = cleaning
    }
}

/// The one line at the top of Diagnostics: whether anything needs doing, and the button that does it.
public struct DiagnosticsSummary: Sendable, Equatable {
    /// The sentence itself.
    public let text: String
    /// Whether this is a warning or an all-clear; the all-clear is drawn quietly so the warning registers.
    public let needsAttention: Bool
    /// The action from the row it is about, moved up beside the sentence.
    public let action: MainAction?

    /// Builds the summary.
    public init(text: String, needsAttention: Bool, action: MainAction?) {
        self.text = text
        self.needsAttention = needsAttention
        self.action = action
    }
}

/// What the diagnostics page shows.
public struct DiagnosticsPresentation: Sendable, Equatable {
    /// The verdict, above everything else on the page.
    public let summary: DiagnosticsSummary
    /// Absent until something has been timed, in which case ``latencyEmptyState`` says so.
    public let latency: DiagnosticsLatency?
    /// Shown instead of ``latency`` until something has been timed.
    public let latencyEmptyState: MainEmptyState?
    /// How often each measured stage worked. Empty until there is something to divide.
    public let reliability: [MainStatistic]
    /// One row per speech and clean-up engine.
    public let engines: [DiagnosticsRow]
    /// What each clean-up step did to the last dictation, and which steps are switched off.
    public let cleanUp: [DiagnosticsRow]
    /// One row per permission, granted or not.
    public let permissions: [DiagnosticsRow]
    /// What the speech model occupies on disk.
    public let storage: [DiagnosticsRow]
    /// The line under the page saying where the timings come from.
    public let footnote: String
    /// Copies the same facts as plain text.
    public let copyAction: MainAction

    /// Builds the page from its parts.
    public init(
        summary: DiagnosticsSummary,
        latency: DiagnosticsLatency?,
        latencyEmptyState: MainEmptyState?,
        reliability: [MainStatistic],
        engines: [DiagnosticsRow],
        cleanUp: [DiagnosticsRow],
        permissions: [DiagnosticsRow],
        storage: [DiagnosticsRow],
        footnote: String,
        copyAction: MainAction
    ) {
        self.summary = summary
        self.latency = latency
        self.latencyEmptyState = latencyEmptyState
        self.reliability = reliability
        self.engines = engines
        self.cleanUp = cleanUp
        self.permissions = permissions
        self.storage = storage
        self.footnote = footnote
        self.copyAction = copyAction
    }
}

/// Turns what has been measured into the diagnostics page; nothing appears that was not measured.
public enum DiagnosticsPresenter {
    /// The sentence under the page's name.
    public static let caption = "What is installed, what is allowed, and how fast it runs."

    /// Timings are kept in memory only, so this is honest about the window they cover.
    public static let footnote =
        "Measured on this Mac since Uttrflow started, and never sent anywhere."

    /// Draws the Diagnostics page from a snapshot.
    public static func page(
        for snapshot: DiagnosticsSnapshot, locale: Locale = .autoupdatingCurrent
    ) -> DiagnosticsPresentation {
        let summaries = StageLatency.summarise(snapshot.measurements)
        let missing = StageLatency.unmeasuredStages(in: snapshot.measurements)
        let engines = engineRows(for: snapshot)
        let permissions = permissionRows(for: snapshot)
        let storage = storageRows(for: snapshot, locale: locale)

        return DiagnosticsPresentation(
            summary: summary(engines: engines, permissions: permissions, storage: storage),
            latency: summaries.isEmpty ? nil : latency(for: summaries, missing: missing),
            latencyEmptyState: summaries.isEmpty ? noTimingsYet : nil,
            reliability: reliability(for: snapshot.measurements, locale: locale),
            engines: engines,
            cleanUp: cleanUpRows(for: snapshot.cleaning),
            permissions: permissions,
            storage: storage,
            footnote: footnote,
            copyAction: MainAction(
                title: "Copy Diagnostics", intent: .copy(report(for: snapshot, locale: locale))))
    }

    // MARK: - The verdict

    /// What to say above the table: the first thing wrong, in the order permissions, engines, storage.
    static func summary(
        engines: [DiagnosticsRow], permissions: [DiagnosticsRow], storage: [DiagnosticsRow]
    ) -> DiagnosticsSummary {
        let ordered = permissions + engines + storage
        guard let problem = ordered.first(where: { $0.state == .attention }) else {
            return DiagnosticsSummary(
                text: "Everything Uttrflow needs is in place.", needsAttention: false,
                action: nil)
        }
        return DiagnosticsSummary(
            text: "\(problem.title): \(problem.detail)", needsAttention: true,
            action: problem.action)
    }

    /// Nothing has been timed, said plainly with what to do about it.
    static let noTimingsYet = MainEmptyState(
        symbolName: "gauge.with.dots.needle.bottom.50percent",
        title: "No timings yet",
        message: "Dictate something and the times appear here. They stay on this Mac.")

    // MARK: - Latency

    /// One row per stage something has timed, from Core's own medians so this page and the harness agree.
    static func stageRows(for summaries: [StageLatency]) -> [DiagnosticsStageRow] {
        let total = summaries.reduce(0.0) { $0 + $1.typical.inSeconds }
        return summaries.map { summary in
            DiagnosticsStageRow(
                stage: summary.stage,
                title: title(for: summary.stage),
                typical: MainFormatting.seconds(summary.typical),
                slowest: MainFormatting.seconds(summary.slowest),
                // Everything measured as instant divides zero by zero; a flat bar is the truthful picture.
                share: total > 0 ? summary.typical.inSeconds / total : 0,
                samples: summary.samples)
        }
    }

    /// The headline, what it is made of, and the stages it is missing.
    static func latency(
        for summaries: [StageLatency], missing: [PipelineStage]
    ) -> DiagnosticsLatency {
        let total = summaries.reduce(Duration.zero) { $0 + $1.typical }
        // One transcription per dictation, so its sample count is how many journeys the numbers rest on.
        let dictations = summaries.first { $0.stage == .transcription }?.samples ?? 0
        let measured = MainFormatting.seconds(total)
        let overDictations = MainFormatting.count(dictations, "dictation", "dictations")

        // "at least" needs a number it can qualify, and "under 0.01s" is an upper bound, not a floor.
        let floor = total.inSeconds < 0.01 ? "0.00s" : measured

        return DiagnosticsLatency(
            // A sum of the timed stages is a floor, and the word saying so has to be on the number itself.
            headline: missing.isEmpty ? measured : "at least \(floor)",
            caption: caption(over: overDictations, missing: missing.count),
            stages: stageRows(for: summaries),
            unmeasured: missing.map(neverRunRow))
    }

    /// The sentence under the headline; counts the missing stages rather than naming them again.
    static func caption(over dictations: String, missing: Int) -> String {
        let base = "each stage's typical time, added together, over \(dictations)"
        guard missing > 0 else { return base }
        return """
            \(base), without \(MainFormatting.count(missing, "stage", "stages")) \
            nothing has ever timed
            """
    }

    /// A stage nothing has timed, grey and wordless rather than `0.00s`.
    static func neverRunRow(for stage: PipelineStage) -> DiagnosticsRow {
        DiagnosticsRow(title: title(for: stage), detail: "Never run", state: .unknown)
    }

    /// The words the floating button already uses for these moments, so the row is recognised.
    static func title(for stage: PipelineStage) -> String {
        switch stage {
        case .capture: "Recording"
        case .transcription: "Transcribing"
        case .correction: "Checking the dictionary"
        case .transformation: "Tidying up"
        case .expansion: "Expanding snippets"
        case .insertion: "Inserting"
        }
    }

    // MARK: - Reliability

    /// How often each measured stage worked, one figure per stage with samples.
    static func reliability(for measurements: [StageMeasurement], locale: Locale) -> [MainStatistic] {
        PipelineStage.allCases.compactMap { stage in
            let attempts = measurements.filter { $0.stage == stage }
            guard !attempts.isEmpty else { return nil }
            let worked = attempts.filter(\.succeeded).count
            return MainStatistic(
                value: MainFormatting.percentage(
                    Double(worked) / Double(attempts.count), locale: locale),
                caption: "\(title(for: stage)) worked")
        }
    }

    // MARK: - Engines

    /// The speech engine, then every clean-up engine with whether it is in use, ready, or missing.
    static func engineRows(for snapshot: DiagnosticsSnapshot) -> [DiagnosticsRow] {
        let ordered = snapshot.engines.resolvedTransformerPreference
        let inUse = ordered.first { snapshot.transformerAvailability[$0] == true }

        let speech = DiagnosticsRow(
            title: "Speech", detail: name(for: snapshot.engines.speech), state: .good)

        return [speech]
            + ordered.map { kind in
                switch snapshot.transformerAvailability[kind] {
                case true:
                    DiagnosticsRow(
                        title: name(for: kind),
                        detail: kind == inUse ? "In use" : "Ready if needed", state: .good)
                case false:
                    DiagnosticsRow(
                        title: name(for: kind), detail: "Not available on this Mac",
                        state: .attention)
                case nil:
                    DiagnosticsRow(
                        title: name(for: kind), detail: "Not checked yet", state: .unknown)
                }
            }
    }

    /// Plain English, never a product name, since §16 says the user never learns which engine ran.
    static func name(for kind: SpeechEngineKind) -> String {
        switch kind {
        case .whisperKit: "Downloaded speech model"
        case .appleSpeech: "Built-in speech recognition"
        }
    }

    /// Plain English for a clean-up engine, never a product name.
    static func name(for kind: TransformerKind) -> String {
        switch kind {
        case .foundationModels: "Built-in language model"
        case .localModel: "Downloaded language model"
        case .rules: "Built-in rules"
        case .cloud: "Hosted language model"
        }
    }

    // MARK: - What the clean-up steps did

    /// At most this many words are quoted in a row; the rest are counted, so a row stays a line.
    static let quoted = 4

    /// The steps this page reports on: the ones the user is offered, whichever engine tidied the words.
    static func reported(_ record: CleaningRecord) -> [CleaningRecord.Change] {
        record.changes.filter { CleaningSteps.isOffered($0.step) }
    }

    /// One row per step that changed something, then every step that is off, naming the words rather than counting them.
    static func cleanUpRows(for record: CleaningRecord?) -> [DiagnosticsRow] {
        guard let record else {
            return [
                DiagnosticsRow(
                    title: "Clean-up steps", detail: "Nothing dictated yet", state: .unknown)
            ]
        }

        let changed = reported(record).map {
            DiagnosticsRow(
                title: CleaningSteps.name(of: $0.step), detail: detail(of: $0), state: .good)
        }
        // Named rather than absent: a step that is off is why a word is still there.
        let off = record.switchedOff.map {
            DiagnosticsRow(
                title: CleaningSteps.name(of: $0), detail: "Switched off", state: .unknown)
        }
        guard changed.isEmpty, off.isEmpty else { return changed + off }
        return [
            DiagnosticsRow(
                title: "Clean-up steps", detail: "Nothing needed changing", state: .good)
        ]
    }

    /// What one step did, in the first few words it did it to and a count of the rest.
    static func detail(of change: CleaningRecord.Change) -> String {
        var parts: [String] = []
        if !change.removed.isEmpty {
            parts.append("removed \(change.removed.count): \(listed(change.removed))")
        }
        if !change.replaced.isEmpty {
            let rewrites = change.replaced.map { "\($0.from) → \($0.to)" }
            parts.append("rewrote \(rewrites.count): \(listed(rewrites))")
        }
        if !change.inserted.isEmpty {
            parts.append("added \(change.inserted.count): \(listed(change.inserted))")
        }
        return parts.joined(separator: "; ")
    }

    /// The first few words, then how many more there were, because the row is one line of a page.
    static func listed(_ words: [String]) -> String {
        guard words.count > quoted else { return words.joined(separator: ", ") }
        return words.prefix(quoted).joined(separator: ", ") + " and \(words.count - quoted) more"
    }

    /// The same steps counted rather than quoted, for the report that leaves this Mac by hand.
    static func countedCleanUp(_ record: CleaningRecord) -> [String] {
        reported(record).map { change in
            let counts = [
                change.removed.isEmpty ? nil : "removed \(change.removed.count)",
                change.replaced.isEmpty ? nil : "rewrote \(change.replaced.count)",
                change.inserted.isEmpty ? nil : "added \(change.inserted.count)",
            ].compactMap(\.self)
            return "  \(CleaningSteps.name(of: change.step)): \(counts.joined(separator: ", "))"
        }
            + record.switchedOff.map { "  \(CleaningSteps.name(of: $0)): switched off" }
    }

    // MARK: - Permissions

    /// Every permission, granted or not, so the page can confirm that nothing is broken.
    static func permissionRows(for snapshot: DiagnosticsSnapshot) -> [DiagnosticsRow] {
        PermissionKind.allCases.map { kind in
            switch snapshot.permissions[kind] {
            case .granted:
                DiagnosticsRow(title: name(for: kind), detail: "Granted", state: .good)
            case .denied:
                DiagnosticsRow(
                    title: name(for: kind), detail: "Turned off", state: .attention,
                    action: action(.openSystemSettings(kind.settingsPane)))
            case .notDetermined:
                DiagnosticsRow(
                    title: name(for: kind), detail: "Not asked for yet", state: .attention,
                    action: MainAction(title: "Set Up", intent: .go(.onboarding)))
            case .restricted:
                // Asking again cannot help, so nothing is offered — see PermissionError.
                DiagnosticsRow(
                    title: name(for: kind), detail: "Blocked by a device policy",
                    state: .attention)
            case nil:
                DiagnosticsRow(title: name(for: kind), detail: "Not checked yet", state: .unknown)
            }
        }
    }

    /// A recovery as a button, worded once in ``MainPresenter``.
    static func action(_ recovery: RecoveryAction) -> MainAction {
        MainAction(title: MainPresenter.title(for: recovery), intent: .recover(recovery))
    }

    /// The permission as the rest of the product names it.
    static func name(for kind: PermissionKind) -> String {
        switch kind {
        case .microphone: "Microphone"
        case .accessibility: "Accessibility"
        }
    }

    // MARK: - What is on the disk

    /// The speech model row: not checked, not downloaded, or its size and languages.
    static func storageRows(for snapshot: DiagnosticsSnapshot, locale: Locale) -> [DiagnosticsRow] {
        guard let model = snapshot.speechModel else {
            return [DiagnosticsRow(title: "Speech model", detail: "Not checked yet", state: .unknown)]
        }
        guard model.isInstalled else {
            return [
                DiagnosticsRow(
                    title: "Speech model", detail: "Not downloaded", state: .attention,
                    action: action(.downloadSpeechModel))
            ]
        }

        let languages = model.isMultilingual ? "every language" : "English"
        let size = model.bytesOnDisk.map { "\(MainFormatting.bytes($0, locale: locale)), " } ?? ""
        return [
            DiagnosticsRow(
                title: "Speech model", detail: "\(size)on this Mac, \(languages)", state: .good)
        ]
    }

    // MARK: - Copying it out

    /// The same facts as plain text for a bug report, built from the page so the two cannot differ.
    public static func report(
        for snapshot: DiagnosticsSnapshot, locale: Locale = .autoupdatingCurrent
    ) -> String {
        let stages = stageRows(for: StageLatency.summarise(snapshot.measurements))
        var lines = ["Uttrflow diagnostics", footnote, ""]

        if stages.isEmpty {
            lines.append("Timings: none recorded yet")
        } else {
            lines.append("Timings (typical / slowest / samples)")
            lines += stages.map { "  \($0.title): \($0.typical) / \($0.slowest) / \($0.samples)" }
            // Named here as on the page, so a bug report never lists four stages of a six-stage journey.
            lines += StageLatency.unmeasuredStages(in: snapshot.measurements).map {
                "  \(title(for: $0)): never run"
            }
        }

        // Counted, never quoted: this string is pasted elsewhere, and dictated words are not a diagnostic.
        let counted = snapshot.cleaning.map(countedCleanUp) ?? []
        if !counted.isEmpty {
            lines += ["", "Clean-up steps, last dictation"] + counted
        }

        let sections: [(String, [DiagnosticsRow])] = [
            ("Engines", engineRows(for: snapshot)),
            ("Permissions", permissionRows(for: snapshot)),
            ("On disk", storageRows(for: snapshot, locale: locale)),
        ]
        for (heading, rows) in sections {
            lines += ["", heading]
            lines += rows.map { "  \($0.title): \($0.detail)" }
        }

        return lines.joined(separator: "\n")
    }
}
