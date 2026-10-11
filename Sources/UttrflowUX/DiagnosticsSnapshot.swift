public import UttrflowCore
public import UttrflowHistory

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
    /// How many recent pieces in a row were decoded without the user's words, from the local recorder.
    let unconditionedRun: Int
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
        unconditionedRun: Int = 0,
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
        self.unconditionedRun = unconditionedRun
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
