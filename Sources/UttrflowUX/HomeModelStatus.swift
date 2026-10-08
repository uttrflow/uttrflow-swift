// What home's hero says in place of its waveform while the speech model cannot transcribe.
public import UttrflowCore
public import struct Foundation.Date

/// The colour of the dot beside the status: dictation's teal while setup runs, amber once it needs a hand.
public enum HomeModelTone: String, Sendable, Equatable, CaseIterable {
    case dictation
    case warning
}

/// The thin bar under the status: filled to a known share, or sliding while nothing measures the wait.
public enum HomeModelProgress: Sendable, Equatable {
    case fraction(Double)
    case sliding
}

/// The speech model's state, drawn in the hero where the waveform would be.
public struct HomeModelStatus: Sendable, Equatable {
    /// "Setting up… 42%", beside the dot.
    public let title: String
    /// The line under the title.
    public let subtitle: String
    /// The dot's colour.
    public let tone: HomeModelTone
    /// The bar under the status, absent once there is nothing to wait for.
    public let progress: HomeModelProgress?
    /// The button drawn in place of the start pill; absent while the pill waits, dimmed, for setup to end.
    public let action: MainAction?
    /// The button's fill: amber to load again, teal to download.
    public let actionTone: HomeModelTone
    /// What VoiceOver reads for the block as a whole.
    public let accessibilityLabel: String
    /// When the load under way began, so the hero moves its own estimate on; `nil` in every other state.
    public let loadingSince: Date?

    /// Whether setup runs with nothing for the user to do, so the hero blurs behind a ring.
    public var isWaiting: Bool { progress != nil && action == nil }

    /// Builds a status from its parts.
    public init(
        title: String, subtitle: String, tone: HomeModelTone, progress: HomeModelProgress?,
        action: MainAction?, actionTone: HomeModelTone = .dictation, accessibilityLabel: String,
        loadingSince: Date? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.tone = tone
        self.progress = progress
        self.action = action
        self.actionTone = actionTone
        self.accessibilityLabel = accessibilityLabel
        self.loadingSince = loadingSince
    }

    /// The line under a long load's estimate, since only the first load after a restart is slow.
    static let afterRestart = "Only after a restart. Everything else already works."

    /// The download under way, at a share from 0 to 1, with the bytes so far when the total is known.
    public static func downloading(_ fraction: Double, bytes: Int64? = nil) -> HomeModelStatus {
        let percent = MenuBarPresenter.percentage(of: fraction)
        let received = bytes.map { total in
            let arrived = Int64(Double(total) * min(max(fraction, 0), 1))
            return "\(MenuBarPresenter.size(of: arrived)) of \(MenuBarPresenter.size(of: total))"
        }
        return HomeModelStatus(
            title: "Setting up… \(percent)%",
            subtitle: ["Downloading the speech model", received].compactMap(\.self).joined(separator: " · "),
            tone: .dictation, progress: .fraction(min(max(fraction, 0), 1)), action: nil,
            accessibilityLabel: "Setting up. Downloading the speech model, \(percent) percent.")
    }

    /// A load that began at `since`, as it stands at `now`, carrying `since` so the hero redraws it alone.
    public static func loading(since: Date, at now: Date) -> HomeModelStatus {
        load(.loading(elapsed: .seconds(now.timeIntervalSince(since)))).began(at: since)
    }

    /// This status with the load's start attached.
    func began(at since: Date) -> HomeModelStatus {
        HomeModelStatus(
            title: title, subtitle: subtitle, tone: tone, progress: progress, action: action,
            actionTone: actionTone, accessibilityLabel: accessibilityLabel, loadingSince: since)
    }

    /// The model on disk and loading, failed to load, damaged, or not on disk at all.
    public static func load(_ load: SpeechModelLoad) -> HomeModelStatus {
        switch load {
        case .loading:
            guard let estimate = load.estimate else {
                return HomeModelStatus(
                    title: "Getting ready…", subtitle: "Loading the speech model", tone: .dictation,
                    progress: .sliding, action: nil, accessibilityLabel: load.accessibilityLabel)
            }
            return HomeModelStatus(
                title: estimate.heading, subtitle: afterRestart, tone: .dictation,
                progress: .fraction(estimate.fraction), action: nil,
                accessibilityLabel: "\(estimate.spokenHeading). \(afterRestart)")
        case .failed:
            return HomeModelStatus(
                title: load.status, subtitle: "Nothing was lost. Try loading it again.",
                tone: .warning, progress: nil,
                action: MainAction(title: "Try again", intent: .recover(.retry)), actionTone: .warning,
                accessibilityLabel: "\(load.status). Nothing was lost. Try loading it again.")
        case .broken:
            let repair = "Download it again to repair it."
            return HomeModelStatus(
                title: load.status, subtitle: repair, tone: .warning, progress: nil,
                action: MainAction(title: "Download again", intent: .recover(.downloadSpeechModel)),
                actionTone: .warning, accessibilityLabel: "\(load.status). \(repair)")
        case .missing:
            return missing(bytes: nil)
        }
    }

    /// No model on disk, with the download's size when it is known and without one when it is not.
    public static func missing(bytes: Int64?) -> HomeModelStatus {
        let size = bytes.map { MenuBarPresenter.size(of: $0) }
        return HomeModelStatus(
            title: "Speech model not installed",
            subtitle: "Dictation needs it · "
                + (size.map { "\($0), works offline after" } ?? "works offline after"),
            tone: .warning, progress: nil,
            action: MainAction(title: "Download speech model", intent: .recover(.downloadSpeechModel)),
            accessibilityLabel:
                "Speech model not installed. Dictation needs it\(size.map { ", a \($0) download," } ?? ""), "
                + "and works offline once it is downloaded.")
    }
}

extension SpeechModelReadiness {
    /// How far the download has got, zero while it is unmeasured; `nil` when nothing is downloading.
    public var download: Double? {
        guard case .downloading(let fraction) = self else { return nil }
        return fraction ?? 0
    }
}
