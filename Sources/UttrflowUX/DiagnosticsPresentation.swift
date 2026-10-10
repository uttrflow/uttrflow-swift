// The Diagnostics tab: the model cards, this Mac, the latency figures, reliability, and the plain-text report.
public import Foundation
public import UttrflowCore
public import UttrflowHistory

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

    /// The row's VoiceOver label, including the count of its measurements.
    public var accessibilityLabel: String {
        "\(title): \(typical) typically, \(slowest) at worst, over "
            + "\(MainFormatting.count(samples, "measurement", "measurements"))."
    }

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

/// One model Uttrflow runs, as a card: what it is for, what it is, and whether it is ready.
public struct DiagnosticsModelCard: Sendable, Equatable, Identifiable {
    /// What the model is for, which is unique on the page.
    public let title: String
    /// The SF Symbol on the card's tile.
    public let symbolName: String
    /// The accent the tile is washed in.
    public let tint: SettingsTint
    /// The model in plain words, never a product name.
    public let name: String
    /// Short facts under the name: its size, where it runs.
    public let chips: [String]
    /// Whether it is ready, in a word or two.
    public let status: String
    /// How the status is coloured.
    public let state: DiagnosticsState

    /// The title.
    public var id: String { title }

    /// Builds a card.
    public init(
        title: String, symbolName: String, tint: SettingsTint, name: String, chips: [String],
        status: String, state: DiagnosticsState
    ) {
        self.title = title
        self.symbolName = symbolName
        self.tint = tint
        self.name = name
        self.chips = chips
        self.status = status
        self.state = state
    }
}

/// Everything the diagnostics page is drawn from.
public struct DiagnosticsSnapshot: Sendable, Equatable {
    /// Which engines are configured, in preference order.
    public let engines: EngineConfiguration
    /// The recogniser the pipeline transcribes with, which trails the setting until a switch has been taken up.
    public let speechInUse: SpeechEngineKind?
    /// What each clean-up engine answered when last asked whether it can run here; absent means never asked.
    public let transformerAvailability: [TransformerKind: Bool]
    /// Absent until the store has been consulted.
    public let speechModel: DiagnosticsModelPresence?
    /// Whether the speech model can dictate, from the same state Home, the menu bar and the floating button read.
    public let speechReadiness: SpeechModelReadiness?
    /// Why the last speech model load failed; absent when it did not, or nobody asked.
    public let speechLoadFailure: SpeechLoadFailureClass?
    /// What macOS has granted, for every permission asked about.
    public let permissions: [PermissionKind: PermissionStatus]
    /// Whether the dictation shortcut is armed; absent when its state has not been checked.
    public let dictationShortcutArmed: Bool?
    /// Whether macOS has a default input device; absent when its state has not been checked.
    public let hasDefaultInputDevice: Bool?
    /// Every stage timing recorded since the app started.
    public let measurements: [StageMeasurement]
    /// Counts of suggestion lines capture excluded, by closed reason.
    public let captureSkips: [CaptureSkipReason: Int]
    /// The words the active recogniser last kept in its prompt, from the local recorder.
    public let vocabularyPrompt: [String]
    /// The bounded per-piece decode effort recorded since the app started.
    public let decoding: [DecodeEffort]
    /// The decoder's judgement of each recent segment; empty when the engine reports none.
    public let segmentReliability: [SegmentReliability]
    /// The last dictations' waits after key-up, each with the cause named for it.
    public let waits: [TimedWait]
    /// The speech model's last loads, oldest first, kept across launches.
    public let speechModelLoads: [SpeechModelLoadRecord]
    /// What the clean-up steps did to the last dictation, absent until one has been tidied.
    public let cleaning: CleaningRecord?
    /// Which engine tidied the last inserted dictation, including `.untidied` when none did.
    public let lastCleanedBy: TransformerKind?
    /// How the tidy route ended for recent pieces, per engine.
    public let tidyTally: TidyTally
    /// Why the last dictation's screen read carried no field text, or `nil` when it did or none was read.
    public let screenTextUnavailable: ContextUnavailableReason?
    /// Which rung answered each screen read since launch, per application, without field text.
    public let readRungs: ContextReadTally
    /// How far along the model AI suggestions need is.
    public let suggestionModel: SuggestionModelReadiness
    /// Which build is running.
    public let version: AppVersion
    /// This Mac in one line: macOS version, chip and memory; absent when it could not be read.
    public let machine: String?
    /// How each kept dictation's words arrived, one per History record; `nil` predates the field.
    public let arrivals: [RecordedArrival?]
    /// Which quality layers the running pipeline was built with.
    let qualityLayers: QualityLayers
    /// Why the learned-state ledger cannot be used, or `nil` when it can or there is none.
    let learnedState: EvidenceLedgerError?

    /// Builds a snapshot; everything defaults to not yet checked.
    public init(
        engines: EngineConfiguration = .default,
        speechInUse: SpeechEngineKind? = nil,
        transformerAvailability: [TransformerKind: Bool] = [:],
        speechModel: DiagnosticsModelPresence? = nil,
        speechReadiness: SpeechModelReadiness? = nil,
        speechLoadFailure: SpeechLoadFailureClass? = nil,
        permissions: [PermissionKind: PermissionStatus] = [:],
        dictationShortcutArmed: Bool? = nil,
        hasDefaultInputDevice: Bool? = nil,
        measurements: [StageMeasurement] = [],
        captureSkips: [CaptureSkipReason: Int] = [:],
        vocabularyPrompt: [String] = [],
        decoding: [DecodeEffort] = [],
        segmentReliability: [SegmentReliability] = [],
        waits: [TimedWait] = [],
        speechModelLoads: [SpeechModelLoadRecord] = [],
        cleaning: CleaningRecord? = nil,
        tidyTally: TidyTally = TidyTally(),
        screenTextUnavailable: ContextUnavailableReason? = nil,
        readRungs: ContextReadTally = ContextReadTally(),
        lastCleanedBy: TransformerKind? = nil,
        suggestionModel: SuggestionModelReadiness = .notAsked,
        version: AppVersion = .unknown,
        machine: String? = nil,
        arrivals: [RecordedArrival?] = [],
        qualityLayers: QualityLayers = QualityLayers(),
        learnedState: EvidenceLedgerError? = nil
    ) {
        self.engines = engines
        self.speechInUse = speechInUse
        self.transformerAvailability = transformerAvailability
        self.speechModel = speechModel
        self.speechReadiness = speechReadiness
        self.speechLoadFailure = speechLoadFailure
        self.permissions = permissions
        self.dictationShortcutArmed = dictationShortcutArmed
        self.hasDefaultInputDevice = hasDefaultInputDevice
        self.measurements = measurements
        self.captureSkips = captureSkips
        self.vocabularyPrompt = vocabularyPrompt
        self.decoding = decoding
        self.segmentReliability = segmentReliability
        self.waits = waits
        self.speechModelLoads = speechModelLoads
        self.cleaning = cleaning
        self.tidyTally = tidyTally
        self.screenTextUnavailable = screenTextUnavailable
        self.readRungs = readRungs
        self.lastCleanedBy = lastCleanedBy
        self.suggestionModel = suggestionModel
        self.version = version
        self.machine = machine
        self.arrivals = arrivals
        self.qualityLayers = qualityLayers
        self.learnedState = learnedState
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
    /// One card per model Uttrflow runs.
    public let models: [DiagnosticsModelCard]
    /// The build and this Mac, before the permissions.
    public let system: [DiagnosticsRow]
    /// Absent until something has been timed, in which case ``latencyEmptyState`` says so.
    public let latency: DiagnosticsLatency?
    /// Shown instead of ``latency`` until something has been timed.
    public let latencyEmptyState: MainEmptyState?
    /// How often each measured stage worked. Empty until there is something to divide.
    public let reliability: [MainStatistic]
    /// Aggregate counts of pieces that took extra decodes and empty-result retries.
    public let decoding: [DiagnosticsRow]
    /// The wait after key-up per dictation, and how often each cause made it run past the target.
    public let waits: [DiagnosticsRow]
    /// Why suggestion lines were not learned, counted without keeping their words.
    public let captureSkips: [DiagnosticsRow]
    /// How many kept dictations reached a field, by arrival. Empty until History holds one.
    public let arrivals: [DiagnosticsRow]
    /// The speech model's last loads, newest first, each saying whether a recompile explains it.
    public let speechModelLoads: [DiagnosticsRow]
    /// One row per speech and clean-up engine.
    public let engines: [DiagnosticsRow]
    /// What each clean-up step did to the last dictation, and which steps are switched off.
    public let cleanUp: [DiagnosticsRow]
    /// The exact dictionary words included in the latest recogniser prompt.
    public let vocabularyPrompt: DiagnosticsRow
    /// One row per quality layer, saying whether it runs and whether that is its default.
    public let qualityLayers: [DiagnosticsRow]
    /// One row per permission, granted or not.
    public let permissions: [DiagnosticsRow]
    /// Whether the shortcut and input device can start dictation.
    public let availability: [DiagnosticsRow]
    /// What the speech model occupies on disk.
    public let storage: [DiagnosticsRow]
    /// The line under the page saying where the timings come from.
    public let footnote: String
    /// Copies the same facts as plain text.
    public let copyAction: MainAction

    /// Builds the page from its parts.
    public init(
        summary: DiagnosticsSummary,
        models: [DiagnosticsModelCard] = [],
        system: [DiagnosticsRow] = [],
        latency: DiagnosticsLatency?,
        latencyEmptyState: MainEmptyState?,
        reliability: [MainStatistic],
        decoding: [DiagnosticsRow],
        waits: [DiagnosticsRow] = [],
        captureSkips: [DiagnosticsRow] = [],
        speechModelLoads: [DiagnosticsRow] = [],
        arrivals: [DiagnosticsRow] = [],
        engines: [DiagnosticsRow],
        cleanUp: [DiagnosticsRow],
        vocabularyPrompt: DiagnosticsRow,
        qualityLayers: [DiagnosticsRow] = [],
        permissions: [DiagnosticsRow],
        availability: [DiagnosticsRow],
        storage: [DiagnosticsRow],
        footnote: String,
        copyAction: MainAction
    ) {
        self.summary = summary
        self.models = models
        self.system = system
        self.latency = latency
        self.latencyEmptyState = latencyEmptyState
        self.reliability = reliability
        self.decoding = decoding
        self.waits = waits
        self.captureSkips = captureSkips
        self.speechModelLoads = speechModelLoads
        self.arrivals = arrivals
        self.engines = engines
        self.cleanUp = cleanUp
        self.vocabularyPrompt = vocabularyPrompt
        self.qualityLayers = qualityLayers
        self.permissions = permissions
        self.availability = availability
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
        let availability = availabilityRows(for: snapshot)
        let storage =
            storageRows(for: snapshot, locale: locale) + learnedStateRows(for: snapshot.learnedState)

        return DiagnosticsPresentation(
            summary: summary(
                engines: engines, permissions: permissions, availability: availability,
                storage: storage),
            models: models(for: snapshot, locale: locale),
            system: systemRows(for: snapshot),
            latency: summaries.isEmpty ? nil : latency(for: summaries, missing: missing),
            latencyEmptyState: summaries.isEmpty ? noTimingsYet : nil,
            reliability: reliability(for: snapshot.measurements, locale: locale),
            decoding: decodingRows(
                for: snapshot.decoding, segments: snapshot.segmentReliability, locale: locale),
            waits: waitRows(for: snapshot.waits, locale: locale),
            captureSkips: captureSkipRows(for: snapshot.captureSkips),
            speechModelLoads: speechModelLoadRows(for: snapshot.speechModelLoads, locale: locale),
            arrivals: arrivalRows(for: snapshot.arrivals),
            engines: engines,
            cleanUp: cleanUpRows(for: snapshot.cleaning)
                + screenTextRows(for: snapshot.screenTextUnavailable)
                + readRungRows(for: snapshot.readRungs)
                + tidyTallyRows(for: snapshot.tidyTally),
            vocabularyPrompt: DiagnosticsRow(
                title: "Words in recogniser prompt",
                detail: snapshot.vocabularyPrompt.isEmpty
                    ? "No dictionary words in the last prompt"
                    : snapshot.vocabularyPrompt.joined(separator: ", "),
                state: .unknown),
            qualityLayers: qualityLayerRows(for: snapshot.qualityLayers),
            permissions: permissions,
            availability: availability,
            storage: storage,
            footnote: footnote,
            copyAction: MainAction(
                title: "Copy Diagnostics", intent: .copy(report(for: snapshot, locale: locale))))
    }

    /// Names only the fixed detector reasons, never the line that was skipped.
    static func captureSkipRows(for counts: [CaptureSkipReason: Int]) -> [DiagnosticsRow] {
        CaptureSkipReason.allCases.compactMap { reason in
            guard let count = counts[reason], count > 0 else { return nil }
            let title: String
            switch reason {
            case .insertedText: title = "Text not typed"
            case .unmatchedKeys: title = "Text did not match typed keys"
            }
            return DiagnosticsRow(
                title: title, detail: MainFormatting.count(count, "line", "lines"), state: .unknown)
        }
    }

    // MARK: - Models

    /// The recogniser, the clean-up engine in use, and the model AI suggestions need.
    static func models(for snapshot: DiagnosticsSnapshot, locale: Locale) -> [DiagnosticsModelCard] {
        let speech = snapshot.speechInUse ?? snapshot.engines.speech
        return [
            downloadedSpeechCard(snapshot, inUse: speech == .whisperKit, locale: locale),
            cleanUpCard(snapshot),
            suggestionsCard(snapshot.suggestionModel),
        ]
    }

    /// Where every model on the page runs.
    static let onDevice = "On-device"

    /// The downloaded recogniser: whether it is on the disk, how big, and for which languages.
    static func downloadedSpeechCard(
        _ snapshot: DiagnosticsSnapshot, inUse: Bool, locale: Locale
    ) -> DiagnosticsModelCard {
        let card = { (name: String, chips: [String], status: String, state: DiagnosticsState) in
            DiagnosticsModelCard(
                title: "Speech", symbolName: "waveform", tint: .dictation,
                name: name, chips: chips + [onDevice], status: status, state: state)
        }
        let downloaded = name(for: SpeechEngineKind.whisperKit)
        let missing: DiagnosticsState = inUse ? .attention : .unknown
        switch speechModelCondition(snapshot, inUse: inUse) {
        case .unchecked:
            return card(downloaded, [], "Not checked yet", .unknown)
        case .notInstalled:
            return card(notYetDownloaded, [], "Not downloaded", missing)
        case .incomplete:
            return card(notYetDownloaded, [], damaged, missing)
        case .downloading:
            return card(notYetDownloaded, [], "Downloading", .unknown)
        case .loading:
            return card(downloaded, facts(snapshot.speechModel, locale: locale), "Loading", .unknown)
        case .failed(let fix):
            let failed =
                snapshot.speechLoadFailure.map { "Failed to load: \($0.summary)" } ?? "Failed to load"
            let status = fix == .downloadSpeechModel ? damaged : failed
            return card(downloaded, facts(snapshot.speechModel, locale: locale), status, .attention)
        case .ready:
            return card(
                downloaded, facts(snapshot.speechModel, locale: locale), inUse ? "In use" : "Ready", .good)
        }
    }

    /// The model's size and languages as card chips, empty until the store has been read.
    private static func facts(_ model: DiagnosticsModelPresence?, locale: Locale) -> [String] {
        guard let model else { return [] }
        let size = model.bytesOnDisk.map { [MainFormatting.bytes($0, locale: locale)] } ?? []
        return size + [model.isMultilingual ? "Every language" : "English"]
    }

    /// Where the downloaded recogniser stands, as Diagnostics tells it.
    enum SpeechModelCondition: Equatable {
        case unchecked, notInstalled, incomplete, downloading, loading, ready
        /// It failed to load, with the fix every other surface offers for it.
        case failed(RecoveryAction)
    }

    /// Reads the shared readiness first and the files on disk second, so Diagnostics never contradicts Home.
    static func speechModelCondition(_ snapshot: DiagnosticsSnapshot, inUse: Bool) -> SpeechModelCondition {
        switch snapshot.speechReadiness {
        case .incomplete: return .incomplete
        case .notInstalled: return .notInstalled
        case .downloading: return .downloading
        // A load, and how it went, is about the recogniser in use, which may not be this one.
        case .loading where inUse: return .loading
        case .loadFailed where inUse: return .failed(.retry)
        case .loadFailedAgain where inUse: return .failed(.downloadSpeechModel)
        case .ready, .loading, .loadFailed, .loadFailedAgain, nil: break
        }
        guard let model = snapshot.speechModel else { return .unchecked }
        return model.isInstalled ? .ready : .notInstalled
    }

    /// The one word every surface uses for a model only a fresh download repairs.
    static let damaged = "Damaged"

    /// The storage row's form of it, with the fix.
    static let damagedDetail = "Damaged, download it again"

    /// The downloadable recogniser's name while its files are missing, so it never claims to be downloaded.
    static let notYetDownloaded = "Speech model to download"

    /// The clean-up engine that tidies now, or what is still being asked.
    static func cleanUpCard(_ snapshot: DiagnosticsSnapshot) -> DiagnosticsModelCard {
        let ordered = snapshot.engines.resolvedTransformerPreference
        let card = { (name: String, chips: [String], status: String, state: DiagnosticsState) in
            DiagnosticsModelCard(
                title: "Clean-up", symbolName: "wand.and.stars", tint: .suggestion, name: name,
                chips: chips, status: status, state: state)
        }
        if let lastCleanedBy = snapshot.lastCleanedBy {
            guard lastCleanedBy != .untidied else {
                return card(name(for: lastCleanedBy), [], "Last dictation", .attention)
            }
            let origin =
                lastCleanedBy == .cloud
                ? "Hosted" : (lastCleanedBy == .localModel ? "Downloaded" : "Built in")
            let chips = lastCleanedBy == .cloud ? [origin] : [origin, onDevice]
            let state: DiagnosticsState =
                snapshot.transformerAvailability[lastCleanedBy] == false ? .attention : .good
            return card(name(for: lastCleanedBy), chips, "Last dictation", state)
        }
        guard let inUse = ordered.first(where: { snapshot.transformerAvailability[$0] == true }) else {
            return card("Not checked yet", [], "Checking", .unknown)
        }
        let origin = inUse == .localModel ? "Downloaded" : "Built in"
        return card(name(for: inUse), [origin, onDevice], "Ready", .good)
    }

    /// The model AI suggestions need, and how far along it is.
    static func suggestionsCard(_ readiness: SuggestionModelReadiness) -> DiagnosticsModelCard {
        let (status, state): (String, DiagnosticsState) =
            switch readiness {
            case .notAsked: ("Off", .unknown)
            case .downloading(let fraction):
                (
                    fraction.map { "Downloading \(MenuBarPresenter.percentage(of: $0))%" } ?? "Downloading",
                    .unknown
                )
            case .loading: ("Loading", .unknown)
            case .ready: ("Loaded", .good)
            case .releasedForMemory: ("Set aside for memory", .unknown)
            case .insufficientSpace(let neededBytes):
                ("Needs \(neededBytes.formatted(.byteCount(style: .file))) free", .attention)
            case .fetchFailed, .failed: ("Could not be fetched", .attention)
            case .loadFailed: ("Could not be loaded", .attention)
            }
        return DiagnosticsModelCard(
            title: "AI suggestions", symbolName: "sparkles", tint: .amber,
            name: name(for: TransformerKind.localModel), chips: ["About 3 GB", onDevice],
            status: status, state: state)
    }

    // MARK: - This Mac

    /// The build and the machine, as facts with nothing to press.
    static func systemRows(for snapshot: DiagnosticsSnapshot) -> [DiagnosticsRow] {
        var rows: [DiagnosticsRow] = []
        if snapshot.version.isKnown {
            rows.append(DiagnosticsRow(title: "Uttrflow", detail: snapshot.version.tag, state: .good))
        }
        if let machine = snapshot.machine {
            rows.append(DiagnosticsRow(title: "macOS", detail: machine, state: .good))
        }
        return rows
    }

    // MARK: - The verdict

    /// What to say above the table: the first thing wrong, starting with anything that stops dictation.
    static func summary(
        engines: [DiagnosticsRow], permissions: [DiagnosticsRow], availability: [DiagnosticsRow],
        storage: [DiagnosticsRow]
    ) -> DiagnosticsSummary {
        // The shortcut and input device are checked before models and engines, since without them no dictation can start.
        let ordered = permissions + availability + storage + engines
        guard let problem = ordered.first(where: { $0.state == .attention }) else {
            // An unanswered check is not an all-clear, so the line names it without raising a warning.
            if let pending = ordered.first(where: { $0.state == .unknown }) {
                return DiagnosticsSummary(
                    text: "Still checking: \(pending.title).", needsAttention: false, action: nil)
            }
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

    /// Counts kept dictations by arrival, never their words; an arrival with none is left out.
    static func arrivalRows(for arrivals: [RecordedArrival?]) -> [DiagnosticsRow] {
        let titled: [(RecordedArrival?, String)] = [
            (.confirmed, "Confirmed in the field"), (.notReported, "Sent, field did not report"),
            (.unconfirmed, "Unconfirmed, left on clipboard"), (.notInserted, "Not inserted"),
            (nil, "Kept before arrivals were recorded"),
        ]
        return titled.compactMap { arrival, title in
            let count = arrivals.count { $0 == arrival }
            guard count > 0 else { return nil }
            return DiagnosticsRow(
                title: title, detail: MainFormatting.count(count, "dictation", "dictations"),
                state: .good)
        }
    }

    /// Counts only aggregate decode outcomes, never the pieces or their words.
    static func decodingRows(
        for decoding: [DecodeEffort], segments: [SegmentReliability] = [],
        locale: Locale = .autoupdatingCurrent
    ) -> [DiagnosticsRow] {
        guard !decoding.isEmpty else { return [] }
        let repeated = decoding.count { $0.fallbacks > 0 || $0.retriedWithoutPrompt }
        let retried = decoding.count { $0.retriedWithoutPrompt }
        let rows = [
            DiagnosticsRow(
                title: "Pieces needing more than one decode",
                detail: "\(repeated) of \(decoding.count) pieces", state: .good),
            DiagnosticsRow(
                title: "Empty-result retries",
                detail: MainFormatting.count(retried, "retry", "retries"), state: .good),
        ]
        return rows + [recognitionSplitRow(for: decoding, locale: locale)].compactMap(\.self)
            + segmentRows(for: segments, locale: locale)
    }

    /// How the decoder judges its segments, as counts and spreads only; nothing when no engine reports it.
    static func segmentRows(for segments: [SegmentReliability], locale: Locale) -> [DiagnosticsRow] {
        guard !segments.isEmpty else { return [] }
        let hotter = segments.count { $0.temperature > 0 }
        let scores = segments.map(\.averageLogProbability).sorted()
        func value(_ number: Double) -> String {
            number.formatted(.number.locale(locale).grouping(.never).precision(.fractionLength(2)))
        }
        return [
            DiagnosticsRow(
                title: "Segments kept from a hotter decode",
                detail: "\(hotter) of \(segments.count) segments", state: .good),
            DiagnosticsRow(
                title: "Segment log-probability, p50 / lowest",
                detail: value(scores[(scores.count - 1) / 2]) + " / " + value(scores[0]), state: .good),
        ]
    }

    /// The wait after key-up at p50 and p95 over the kept dictations, then one row per cause named.
    static func waitRows(
        for waits: [TimedWait], locale: Locale = .autoupdatingCurrent
    ) -> [DiagnosticsRow] {
        let log = DictationWaits(waits)
        guard let typical = log.typical, let tail = log.tail else { return [] }
        let over = log.timed.count { $0.cause != nil }
        let counts = log.causeCounts
        let causes = SlowDictationCause.allCases.compactMap { cause -> DiagnosticsRow? in
            guard let count = counts[cause] else { return nil }
            return DiagnosticsRow(
                title: title(for: cause), detail: MainFormatting.count(count, "dictation", "dictations"),
                state: .good)
        }
        return [
            DiagnosticsRow(
                title: "Wait after release, p50 / p95",
                detail: MainFormatting.secondsValue(typical, locale: locale) + " / "
                    + MainFormatting.secondsValue(tail, locale: locale), state: .good),
            DiagnosticsRow(
                title: "Over the \(MainFormatting.secondsValue(DictationWait.target, locale: locale)) target",
                detail: "\(over) of \(log.timed.count) dictations", state: .good),
        ] + causes
    }

    /// How a cause of a slow wait is named on the page.
    static func title(for cause: SlowDictationCause) -> String {
        switch cause {
        case .modelLoad: "Loading the speech model"
        case .fallbackDecode: "Decoding again at a higher temperature"
        case .cappedDecodeRetry: "Decoding a piece again after a cut-off"
        case .tidyTimeout: "Tidying ran out of time"
        case .tidyColdSession: "Starting the tidier"
        case .contextRead: "Reading the field"
        case .insertionConfirmation: "Placing the words"
        case .other: "Nothing named"
        }
    }

    /// One row per kept load, newest first: when, how long, on which macOS build and model revision, and why.
    static func speechModelLoadRows(
        for loads: [SpeechModelLoadRecord], locale: Locale = .autoupdatingCurrent
    ) -> [DiagnosticsRow] {
        loads.reversed().map { load in
            let when = load.date.formatted(
                .dateTime.year().month(.abbreviated).day().hour().minute().second().locale(locale))
            let facts = [
                MainFormatting.secondsValue(.seconds(load.seconds), locale: locale),
                "macOS \(load.systemBuild)", "model \(load.modelRevision.prefix(7))", reason(for: load),
            ]
            return DiagnosticsRow(title: when, detail: facts.joined(separator: ", "), state: .good)
        }
    }

    /// Why a load took as long as it did, in the words the Speech model load section uses.
    static func reason(for load: SpeechModelLoadRecord) -> String {
        let change =
            switch load.change {
            case .firstRecorded: "first load recorded, slow expected"
            case .unchanged: "nothing changed"
            case .systemUpdated: "macOS updated, slow expected"
            case .modelChanged: "model changed, slow expected"
            }
        return load.isLikelyRecompile ? change + ", likely recompile" : change
    }

    /// The mean time per piece in each recognition sub-stage, or nothing when no piece was timed.
    static func recognitionSplitRow(for decoding: [DecodeEffort], locale: Locale) -> DiagnosticsRow? {
        let timed = decoding.map(\.timings).filter { $0.recognitionSeconds > 0 }
        guard !timed.isEmpty else { return nil }
        let total = timed.reduce(RecognitionTimings.zero) { $0.adding($1) }
        func mean(_ seconds: Double) -> String {
            MainFormatting.secondsValue(.seconds(seconds / Double(timed.count)), locale: locale)
        }
        return DiagnosticsRow(
            title: "Recognition split per piece",
            detail: "mel \(mean(total.melSeconds)), encode \(mean(total.encodeSeconds)), "
                + "decode \(mean(total.decodeSeconds)), word timing \(mean(total.wordTimingSeconds)) "
                + "of \(mean(total.recognitionSeconds))",
            state: .good)
    }

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
        let dictations = summaries.first { $0.stage == .insertion }?.samples ?? 0
        let measured = MainFormatting.seconds(total)
        let overDictations = MainFormatting.count(dictations, "dictation", "dictations")

        // "at least" needs a number it can qualify, and "under 0.01s" is an upper bound, not a floor.
        let floor = total.inSeconds < 0.01 ? MainFormatting.secondsValue(.zero) : measured

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
        case .microphoneOpen: "Opening the microphone"
        case .keyDownToAudio: "Shortcut to first audio"
        case .capture: "Recording"
        case .drain: "Finishing the piece already under way"
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

        let recogniser = snapshot.speechInUse ?? snapshot.engines.speech
        // The downloaded recogniser cannot run without its files, so it is not green while they are missing.
        let condition = speechModelCondition(snapshot, inUse: recogniser == .whisperKit)
        let lacksModel =
            recogniser == .whisperKit && (condition == .notInstalled || condition == .incomplete)
        let speech = DiagnosticsRow(
            title: "Speech",
            detail: lacksModel ? notYetDownloaded : name(for: recogniser),
            state: lacksModel ? .attention : .good)

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
        }
    }

    /// Plain English for a clean-up engine, never a product name.
    static func name(for kind: TransformerKind) -> String {
        switch kind {
        case .foundationModels: "Built-in language model"
        case .localModel: "Downloaded language model"
        case .rules: "Built-in rules"
        case .cloud: "Hosted language model"
        case .untidied: "No clean-up ran"
        }
    }

    // MARK: - What the clean-up steps did

    /// At most this many words are quoted in a row; the rest are counted, so a row stays a line.
    static let quoted = 4

    /// The steps this page reports on: the ones the user is offered, whichever engine tidied the words.
    static func reported(_ record: CleaningRecord) -> [CleaningRecord.Change] {
        record.changes.filter { CleaningSteps.isOffered($0.step) }
    }

    /// One row per quality layer in declaration order: on or off, and whether a local override set it.
    static func qualityLayerRows(for layers: QualityLayers) -> [DiagnosticsRow] {
        QualityLayer.allCases.map { layer in
            let on = layers.isOn(layer)
            let state = on ? "On" : "Off"
            return DiagnosticsRow(
                title: layer.rawValue,
                detail: on == layer.defaultOn ? state : "\(state), overridden",
                state: on == layer.defaultOn ? .good : .attention)
        }
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
        // A refused answer is why this dictation reads plainer than the last, and nothing else says so.
        let refused = record.refusals.map {
            DiagnosticsRow(
                title: "Answer refused", detail: "\($0.engine): \($0.reason)", state: .unknown)
        }
        let unavailable = record.unavailableEngines.map {
            DiagnosticsRow(
                title: "Engine skipped",
                detail: "\($0.engine): \($0.reason.diagnosticDescription)", state: .attention)
        }
        let failures = record.engineFailures.map {
            DiagnosticsRow(
                title: "Engine failed", detail: "\($0.engine): \($0.failureClass.rawValue)", state: .attention
            )
        }
        // A stage that gave up is why a correction or snippet is missing, and nothing else says so.
        let skipped = record.skippedStages.map {
            DiagnosticsRow(
                title: "Stage skipped", detail: "\($0.stage.rawValue): \($0.reason.rawValue)",
                state: .attention)
        }
        guard changed.isEmpty, off.isEmpty, refused.isEmpty, unavailable.isEmpty, failures.isEmpty,
            skipped.isEmpty
        else {
            return skipped + unavailable + failures + refused + changed + off
        }
        return [
            DiagnosticsRow(
                title: "Clean-up steps", detail: "Nothing needed changing", state: .good)
        ]
    }

    /// Why the last dictation read no field text, so a blank screen is never taken for an empty field.
    static func screenTextRows(for unavailable: ContextUnavailableReason?) -> [DiagnosticsRow] {
        guard let unavailable else { return [] }
        return [
            DiagnosticsRow(title: "Screen text", detail: "none (\(name(of: unavailable)))", state: .unknown)
        ]
    }

    /// The reason as Diagnostics words it.
    static func name(of unavailable: ContextUnavailableReason) -> String {
        switch unavailable {
        case .notTrusted: "not trusted"
        case .noFocusedElement: "no focused field"
        case .refused: "refused"
        case .timedOut: "timed out"
        case .secure: "secure"
        case .notTextSurface: "no text surface"
        case .restricted: "restricted by your setting"
        }
    }

    /// One row per application counting which rung answered its screen reads; nothing before the first read.
    static func readRungRows(for tally: ContextReadTally) -> [DiagnosticsRow] {
        tally.entries.map {
            DiagnosticsRow(title: "Screen reads, \($0.bundleIdentifier)", detail: $0.counts, state: .unknown)
        }
    }

    /// One row per engine counting how its last pieces ended; nothing while no piece was tidied.
    static func tidyTallyRows(for tally: TidyTally) -> [DiagnosticsRow] {
        guard !tally.outcomes.isEmpty else { return [] }
        let pieces = tally.outcomes.count
        return tally.entries.map {
            DiagnosticsRow(
                title: "Tidy outcomes, \($0.name), last \(pieces) pieces", detail: $0.counts, state: .unknown)
        }
    }

    /// What one step did, in the first few words it did it to and a count of the rest.
    static func detail(of change: CleaningRecord.Change) -> String {
        change.summary(quoting: quoted)
    }

    /// The same steps counted rather than quoted, for the report that leaves this Mac by hand.
    static func countedCleanUp(_ record: CleaningRecord) -> [String] {
        reported(record).map { change in
            let counts = [
                change.removedCount == 0 ? nil : "removed \(change.removedCount)",
                change.replacedCount == 0 ? nil : "rewrote \(change.replacedCount)",
                change.insertedCount == 0 ? nil : "added \(change.insertedCount)",
            ].compactMap(\.self)
            return "  \(CleaningSteps.name(of: change.step)): \(counts.joined(separator: ", "))"
        }
            + record.switchedOff.map { "  \(CleaningSteps.name(of: $0)): switched off" }
            // The kind, never the reason: a reason quotes what was said, and this string is pasted elsewhere.
            + record.refusals.map { "  answer refused (\($0.engine)): \($0.kind.summary)" }
            + record.unavailableEngines.map {
                "  engine skipped (\($0.engine)): \($0.reason.diagnosticDescription)"
            }
            + record.engineFailures.map { "  engine failed (\($0.engine)): \($0.failureClass.summary)" }
            + record.skippedStages.map { "  stage skipped (\($0.stage.rawValue)): \($0.reason.rawValue)" }
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

    /// Whether the two pieces of hardware/setup most likely to stop dictation are ready.
    static func availabilityRows(for snapshot: DiagnosticsSnapshot) -> [DiagnosticsRow] {
        let shortcut: DiagnosticsRow =
            switch snapshot.dictationShortcutArmed {
            case true:
                DiagnosticsRow(title: "Dictation shortcut", detail: "Armed", state: .good)
            case false:
                DiagnosticsRow(title: "Dictation shortcut", detail: "Not armed", state: .attention)
            case nil:
                DiagnosticsRow(title: "Dictation shortcut", detail: "Not checked yet", state: .unknown)
            }
        let input: DiagnosticsRow =
            switch snapshot.hasDefaultInputDevice {
            case true:
                DiagnosticsRow(title: "Input device", detail: "Available", state: .good)
            case false:
                DiagnosticsRow(title: "Input device", detail: "No default input device", state: .attention)
            case nil:
                DiagnosticsRow(title: "Input device", detail: "Not checked yet", state: .unknown)
            }
        return [shortcut, input]
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

    /// The speech model row: not checked, not downloaded, incomplete, loading, failed to load, or its size and languages.
    static func storageRows(for snapshot: DiagnosticsSnapshot, locale: Locale) -> [DiagnosticsRow] {
        // Only the downloaded recogniser needs these files, so their absence is a problem only for it.
        let needed = (snapshot.speechInUse ?? snapshot.engines.speech) == .whisperKit
        let row = { (detail: String, state: DiagnosticsState, fix: RecoveryAction?) in
            [
                DiagnosticsRow(
                    title: "Speech model", detail: detail, state: state, action: fix.map { Self.action($0) })
            ]
        }
        let onDisk = snapshot.speechModel.map { model in
            let languages = model.isMultilingual ? "every language" : "English"
            let size = model.bytesOnDisk.map { "\(MainFormatting.bytes($0, locale: locale)), " } ?? ""
            return "\(size)on this Mac, \(languages)"
        }
        switch speechModelCondition(snapshot, inUse: needed) {
        case .unchecked:
            return row("Not checked yet", .unknown, nil)
        case .notInstalled:
            return row("Not downloaded", needed ? .attention : .good, .downloadSpeechModel)
        case .incomplete:
            return row(damagedDetail, needed ? .attention : .good, .downloadSpeechModel)
        case .downloading:
            return row("Downloading", .unknown, nil)
        case .loading:
            return row([onDisk, "loading"].compactMap(\.self).joined(separator: ", "), .unknown, nil)
        case .failed(let fix):
            let detail = fix == .downloadSpeechModel ? damagedDetail : "On this Mac, but it failed to load"
            return row(detail, .attention, fix)
        case .ready:
            return row(onDisk ?? "On this Mac", .good, nil)
        }
    }

    /// A row only when the learned-state file is set aside, since what was learned is then not in use.
    static func learnedStateRows(for refusal: EvidenceLedgerError?) -> [DiagnosticsRow] {
        switch refusal {
        case nil:
            return []
        case .newerVersion:
            return [
                DiagnosticsRow(
                    title: "Learned state",
                    detail: "Saved by a newer version of Uttrflow, so it is left untouched and not used",
                    state: .attention)
            ]
        case .unreadable:
            return [
                DiagnosticsRow(
                    title: "Learned state", detail: "Could not be read, so it is left untouched and not used",
                    state: .attention)
            ]
        case .setAside:
            return [
                DiagnosticsRow(
                    title: "Learned state",
                    detail: "Could not be read, so it was kept aside and rebuilt from History",
                    state: .attention)
            ]
        }
    }

    // MARK: - Copying it out

    /// The same facts as plain text for a bug report, built from the page so the two cannot differ.
    public static func report(
        for snapshot: DiagnosticsSnapshot, locale: Locale = .autoupdatingCurrent
    ) -> String {
        let stages = stageRows(for: StageLatency.summarise(snapshot.measurements))
        var lines = ["Uttrflow diagnostics", footnote, ""]
        let system = systemRows(for: snapshot)
        if !system.isEmpty {
            lines += system.map { "\($0.title): \($0.detail)" } + [""]
        }

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

        if snapshot.decoding.isEmpty {
            lines += ["", "Decode effort: none recorded yet"]
        } else {
            let decoding = decodingRows(
                for: snapshot.decoding, segments: snapshot.segmentReliability, locale: locale)
            lines += ["", "Decode effort (\(snapshot.decoding.count) pieces)"]
            lines += decoding.map { "  \($0.title): \($0.detail)" }
        }

        let waits = waitRows(for: snapshot.waits, locale: locale)
        if !waits.isEmpty {
            lines += ["", "Wait after release (\(snapshot.waits.count) dictations)"]
            lines += waits.map { "  \($0.title): \($0.detail)" }
        }

        let captureSkips = captureSkipRows(for: snapshot.captureSkips)
        if !captureSkips.isEmpty {
            lines += ["", "Suggestion lines not learned"]
            lines += captureSkips.map { "  \($0.title): \($0.detail)" }
        }

        let arrivals = arrivalRows(for: snapshot.arrivals)
        lines += ["", arrivals.isEmpty ? "Arrival: no dictations kept" : "Arrival (kept dictations)"]
        lines += arrivals.map { "  \($0.title): \($0.detail)" }

        let loads = speechModelLoadRows(for: snapshot.speechModelLoads, locale: locale)
        lines += ["", loads.isEmpty ? "Speech model load: none recorded yet" : "Speech model load"]
        lines += loads.map { "  \($0.title): \($0.detail)" }

        // Counted, never quoted: this string is pasted elsewhere, and dictated words are not a diagnostic.
        let counted = snapshot.cleaning.map(countedCleanUp) ?? []
        if !counted.isEmpty {
            lines += ["", "Clean-up steps, last dictation"] + counted
        }
        // The reason only, never the field: this string is pasted elsewhere.
        if let screenText = screenTextRows(for: snapshot.screenTextUnavailable).first {
            lines += ["", "\(screenText.title): \(screenText.detail)"]
        }
        // Summed across applications, never per app: this string is pasted elsewhere.
        if !snapshot.readRungs.counts.isEmpty {
            lines += ["", "Screen reads by rung, all apps: \(snapshot.readRungs.allApplications)"]
        }
        if !snapshot.tidyTally.outcomes.isEmpty {
            lines += ["", "Tidy outcomes, last \(snapshot.tidyTally.outcomes.count) pieces"]
            lines += snapshot.tidyTally.lines.map { "  \($0)" }
        }

        let models = models(for: snapshot, locale: locale).map {
            DiagnosticsRow(title: $0.title, detail: $0.status, state: $0.state)
        }
        let sections: [(String, [DiagnosticsRow])] = [
            ("Models", models),
            ("Engines", engineRows(for: snapshot)),
            ("Permissions", permissionRows(for: snapshot)),
            ("Availability", availabilityRows(for: snapshot)),
            (
                "On disk",
                storageRows(for: snapshot, locale: locale) + learnedStateRows(for: snapshot.learnedState)
            ),
        ]
        for (heading, rows) in sections {
            lines += ["", heading]
            lines += rows.map { "  \($0.title): \($0.detail)" }
        }

        return lines.joined(separator: "\n")
    }
}
