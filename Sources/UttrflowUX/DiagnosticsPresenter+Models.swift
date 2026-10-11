import Foundation
import UttrflowCore

extension DiagnosticsPresenter {
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
        // A model that loads but keeps decoding unconditioned has lost its tokenizer, which a fresh download repairs.
        if inUse, snapshot.unconditionedRun >= DecodeConditioning.repairThreshold {
            return .failed(.downloadSpeechModel)
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

}
