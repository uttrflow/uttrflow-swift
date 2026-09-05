public import Foundation
public import UttrflowCore

/// Whether something the page reports is fine, wants attention, or is simply not known.
///
/// The third case is the point of the type. A diagnostics page that cannot tell "no"
/// from "nobody has asked yet" will eventually tell the user something untrue.
public enum DiagnosticsState: Sendable, Equatable {
    case good
    case attention
    case unknown
}

/// One fact about the machine, and what to do if it is the wrong fact.
public struct DiagnosticsRow: Sendable, Equatable, Identifiable {
    public let title: String
    public let detail: String
    public let state: DiagnosticsState
    public let action: MainAction?

    public var id: String { title }

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
    public let stage: PipelineStage
    public let title: String
    /// The middle measurement, not a mean: one pathological dictation should not move
    /// the number a user reads as "what usually happens".
    public let typical: String
    /// The worst one seen. Reported as the slowest rather than as a percentile, because
    /// a percentile over a handful of samples is arithmetic pretending to be evidence.
    public let slowest: String
    /// This stage's share of the total below, for the bar. Zero to one.
    public let share: Double
    public let samples: Int

    public var id: PipelineStage { stage }

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
    /// Prefixed with "at least" while any stage remains unmeasured, because a total
    /// assembled from some of the journey is a floor and must not be read as the whole.
    public let headline: String
    /// Says exactly what the headline is, because it is a sum of typicals rather than
    /// the typical of any one dictation — the pipeline times stages, not journeys.
    public let caption: String
    public let stages: [DiagnosticsStageRow]
    /// The stages nothing has ever timed, named rather than drawn.
    ///
    /// A row of its own instead of a zero among the others: "never run" and "took no
    /// measurable time" are different facts about a stage, and the page that conflates
    /// them tells the user the journey is shorter than it is.
    public let unmeasured: [DiagnosticsRow]

    /// `unmeasured` has no default, deliberately: "nothing is missing" is a claim about
    /// the journey, and a caller has to make it rather than fall into it.
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

/// Whether a downloaded speech model is on the machine.
///
/// Described rather than named: this module knows nothing about model catalogues, and
/// §16 says the user is not told which recogniser they are running in any case.
public struct DiagnosticsModelPresence: Sendable, Equatable {
    public let isInstalled: Bool
    /// What it occupies, when it is there.
    public let bytesOnDisk: Int64?
    public let isMultilingual: Bool

    public init(isInstalled: Bool, bytesOnDisk: Int64?, isMultilingual: Bool) {
        self.isInstalled = isInstalled
        self.bytesOnDisk = bytesOnDisk
        self.isMultilingual = isMultilingual
    }
}

/// Everything the diagnostics page is drawn from.
public struct DiagnosticsSnapshot: Sendable, Equatable {
    public let engines: EngineConfiguration
    /// What each clean-up engine answered when last asked whether it could run here.
    /// A kind that is absent has never been asked, and is reported as such.
    public let transformerAvailability: [TransformerKind: Bool]
    /// Absent until the store has been consulted.
    public let speechModel: DiagnosticsModelPresence?
    public let permissions: [PermissionKind: PermissionStatus]
    /// Every stage timing recorded since the app started.
    public let measurements: [StageMeasurement]

    public init(
        engines: EngineConfiguration = .default,
        transformerAvailability: [TransformerKind: Bool] = [:],
        speechModel: DiagnosticsModelPresence? = nil,
        permissions: [PermissionKind: PermissionStatus] = [:],
        measurements: [StageMeasurement] = []
    ) {
        self.engines = engines
        self.transformerAvailability = transformerAvailability
        self.speechModel = speechModel
        self.permissions = permissions
        self.measurements = measurements
    }
}

/// What the diagnostics page shows.
/// The one line at the top of Diagnostics: whether anything needs doing, and the button
/// that does it.
///
/// This page is a page of facts, and a page of facts makes the reader do the work of
/// deciding which fact matters. Somebody opens Diagnostics because something is wrong or
/// because they want to be told nothing is — both deserve an answer above the table
/// rather than three sections down it.
public struct DiagnosticsSummary: Sendable, Equatable {
    public let text: String
    /// Whether this is a warning or an all-clear. The all-clear is drawn quietly: a green
    /// banner every time somebody looks is a banner they stop reading, and then the amber
    /// one does not register either.
    public let needsAttention: Bool
    /// The action from the row it is about, when that row offered one — the same button,
    /// moved to where the sentence is, so a fix is never two scrolls from its own
    /// explanation.
    public let action: MainAction?

    public init(text: String, needsAttention: Bool, action: MainAction?) {
        self.text = text
        self.needsAttention = needsAttention
        self.action = action
    }
}

public struct DiagnosticsPresentation: Sendable, Equatable {
    /// The verdict, above everything else on the page.
    public let summary: DiagnosticsSummary
    /// Absent until something has been timed, in which case ``latencyEmptyState`` says so.
    public let latency: DiagnosticsLatency?
    public let latencyEmptyState: MainEmptyState?
    /// How often each measured stage worked. Empty until there is something to divide.
    public let reliability: [MainStatistic]
    public let engines: [DiagnosticsRow]
    public let permissions: [DiagnosticsRow]
    public let storage: [DiagnosticsRow]
    public let footnote: String
    public let copyAction: MainAction

    public init(
        summary: DiagnosticsSummary,
        latency: DiagnosticsLatency?,
        latencyEmptyState: MainEmptyState?,
        reliability: [MainStatistic],
        engines: [DiagnosticsRow],
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
        self.permissions = permissions
        self.storage = storage
        self.footnote = footnote
        self.copyAction = copyAction
    }
}

/// Turns what has actually been measured into the diagnostics page.
///
/// The rule the whole type is built around: nothing appears here that was not measured.
/// A stage nobody timed has no row, a percentage with no samples behind it is not shown,
/// and the artboard's memory figures are absent entirely because nothing measures them.
/// A number a user cannot trust makes every other number on the page worthless.
public enum DiagnosticsPresenter {
    /// The sentence under the page's name.
    public static let caption = "What is installed, what is allowed, and how fast it runs."

    /// Timings are kept in memory only, so this is honest about the window they cover.
    public static let footnote =
        "Measured on this Mac since Uttrflow started, and never sent anywhere."

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
            permissions: permissions,
            storage: storage,
            footnote: footnote,
            copyAction: MainAction(
                title: "Copy Diagnostics", intent: .copy(report(for: snapshot, locale: locale))))
    }

    // MARK: - The verdict

    /// What to say above the table.
    ///
    /// Permissions first, then engines, then storage — the order somebody is stopped in.
    /// A permission that is not granted means no dictation at all; an engine that is not
    /// ready means a worse one is being used; storage is the least urgent of the three.
    /// Only the first thing wrong is named, because a page that lists three problems at
    /// the top has not summarised anything.
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

    /// Nothing has been timed. Said plainly, with what to do about it, rather than by
    /// drawing an empty chart.
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
                // Everything measured as instant divides zero by zero; a flat bar is the
                // truthful picture of a journey with no time in it.
                share: total > 0 ? summary.typical.inSeconds / total : 0,
                samples: summary.samples)
        }
    }

    /// - Parameters:
    ///   - summaries: The stages something has timed, in journey order.
    ///   - missing: The stages nothing has, which the total therefore does not include.
    /// - Returns: The headline, what it is made of, and what it is missing.
    static func latency(
        for summaries: [StageLatency], missing: [PipelineStage]
    ) -> DiagnosticsLatency {
        let total = summaries.reduce(Duration.zero) { $0 + $1.typical }
        // One transcription per dictation, so its sample count is how many journeys the
        // numbers rest on. Absent entirely if transcription was never reached.
        let dictations = summaries.first { $0.stage == .transcription }?.samples ?? 0
        let measured = MainFormatting.seconds(total)
        let overDictations = MainFormatting.count(dictations, "dictation", "dictations")

        // "at least" needs a number it can qualify, and ``MainFormatting/seconds(_:)``
        // says "under 0.01s" for an instant total — an upper bound, which is the one
        // claim a total with a stage missing from it may not make.
        let floor = total.inSeconds < 0.01 ? "0.00s" : measured

        return DiagnosticsLatency(
            // A sum of the stages that were timed is a floor, not the journey, and the
            // one word that says so has to be on the number itself: a caption below a
            // confident "2.62s" is not what anybody reads.
            headline: missing.isEmpty ? measured : "at least \(floor)",
            caption: caption(over: overDictations, missing: missing.count),
            stages: stageRows(for: summaries),
            unmeasured: missing.map(neverRunRow))
    }

    /// Says exactly what the headline is, and — when it is one — that it is partial.
    ///
    /// The count rather than the names: the stages are listed underneath by name, and a
    /// caption that repeated them would be the same fact twice at the width the page has.
    ///
    /// - Parameters:
    ///   - dictations: How many dictations the numbers rest on, already written out.
    ///   - missing: How many stages nothing has ever timed.
    /// - Returns: The sentence under the headline.
    static func caption(over dictations: String, missing: Int) -> String {
        let base = "each stage's typical time, added together, over \(dictations)"
        guard missing > 0 else { return base }
        return """
            \(base), without \(MainFormatting.count(missing, "stage", "stages")) \
            nothing has ever timed
            """
    }

    /// A stage nothing has timed, said in the page's own vocabulary for "not known".
    ///
    /// Grey and wordless rather than `0.00s`, for the reason ``DiagnosticsState`` exists:
    /// a page that cannot tell "no time" from "no measurement" will eventually tell the
    /// user something untrue.
    static func neverRunRow(for stage: PipelineStage) -> DiagnosticsRow {
        DiagnosticsRow(title: title(for: stage), detail: "Never run", state: .unknown)
    }

    /// The words the rest of the product already uses for these moments, so a user who
    /// has read the floating button recognises the row.
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

    /// Plain English, never a product name.
    ///
    /// §16 says the user must never learn which engine ran, and a diagnostics page is
    /// still the user's. What is useful here is *what kind of thing* is running — on
    /// this Mac or not, downloaded or built in — and that survives the rule intact.
    static func name(for kind: SpeechEngineKind) -> String {
        switch kind {
        case .whisperKit: "Downloaded speech model"
        case .appleSpeech: "Built-in speech recognition"
        }
    }

    static func name(for kind: TransformerKind) -> String {
        switch kind {
        case .foundationModels: "Built-in language model"
        case .localModel: "Downloaded language model"
        case .rules: "Built-in rules"
        case .cloud: "Hosted language model"
        }
    }

    // MARK: - Permissions

    /// Every permission, granted or not: a page that lists only the broken ones cannot
    /// be used to confirm that nothing is broken.
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

    static func name(for kind: PermissionKind) -> String {
        switch kind {
        case .microphone: "Microphone"
        case .accessibility: "Accessibility"
        }
    }

    // MARK: - What is on the disk

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

    /// The same facts as plain text, for pasting into a bug report.
    ///
    /// Built from the page rather than assembled separately, so what is copied cannot
    /// say something different from what was on screen.
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
            // Named here as well as on the page, because a bug report that lists four
            // stages of a six-stage journey is a bug report about the wrong four.
            lines += StageLatency.unmeasuredStages(in: snapshot.measurements).map {
                "  \(title(for: $0)): never run"
            }
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
