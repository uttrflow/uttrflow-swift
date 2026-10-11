import struct Foundation.ByteCountFormatStyle
import UttrflowClipboard
import UttrflowCore
import UttrflowSettings

extension SettingsPresenter {
    // MARK: - Privacy

    /// Privacy: what stays on this Mac and for how long, how Uttrflow looks, and starting over.
    static func privacy(
        _ settings: Settings, _ capabilities: SettingsCapabilities,
        _ personalisation: SettingsPersonalisation
    ) -> SettingsPane {
        SettingsPane(
            tab: .privacy,
            title: title(of: .privacy),
            banner: nil,
            groups: [
                SettingsGroup(
                    id: "retention",
                    title: "Your data",
                    rows: [retentionRow(settings), clipboardRetentionRow(settings), clipboardLimitsRow]
                        + storageRows(personalisation.storage, settings: settings)
                        + [
                            toggleRow(
                                .sharesUsageStatistics,
                                label: "Share usage statistics",
                                explanation:
                                    "Counts and timings, linked to your account when you are signed in. "
                                    + "Never what you dictate.",
                                settings, capabilities
                            ).with(icon: .symbol("chart.bar", .info)),
                            toggleRow(
                                .sendsCrashReports,
                                label: "Send crash reports",
                                explanation: SettingsPresenter.crashReportsExplanation,
                                settings, .everything
                            ).with(icon: .symbol("exclamationmark.bubble", .neutral)),
                        ]),
                SettingsGroup(id: "context", title: "Context", rows: contextRows(settings)),
                SettingsGroup(
                    id: "network", title: "Network, last \(NetworkActivity.windowDays) days",
                    rows: networkRows(personalisation.network)),
                SettingsGroup(id: "appearance", title: "Appearance", rows: [appearanceRow(settings)]),
                personaGroup(personalisation),
                SettingsGroup(
                    id: "reset",
                    title: "Start over",
                    rows: [forgetLearnedRow(personalisation), clearClipboardRow, resetRow(personalisation)]),
            ],
            callout: SettingsCallout(
                symbolName: "lock",
                message: "\(privacyPromise) \(signingOutKeepsEverything)",
                tint: .dictation))
    }

    /// Dictation first, which no purpose belongs to, then every purpose with its count from the ledger.
    static func networkRows(_ network: [NetworkPurpose: NetworkTally]) -> [SettingsRow] {
        let dictation = SettingsRow(
            id: "network.dictation",
            label: "Dictation",
            explanation: "Nothing you say is uploaded",
            control: .status(counted(0, "request", "requests")),
            icon: .symbol("checkmark.shield", .dictation))
        return [dictation]
            + NetworkPurpose.allCases.map { purpose in
                SettingsRow(
                    id: "network.\(purpose.rawValue)",
                    label: networkLabel(purpose),
                    control: .status(counted(network[purpose]?.count ?? 0, "request", "requests")))
            }
    }

    /// The name each purpose goes by in the Privacy pane.
    static func networkLabel(_ purpose: NetworkPurpose) -> String {
        switch purpose {
        case .account: "Account and sign-in"
        case .modelDownload: "Downloads"
        case .updateCheck: "Update checks"
        case .crashReport: "Crash reports"
        case .usageStatistics: "Usage statistics"
        }
    }

    /// What a crash report carries, in the words the row shows. See `Docs/crash-reporting.md`.
    static let crashReportsExplanation =
        "When Uttrflow crashes or freezes, sends where in its code it happened, the app and macOS "
        + "versions, and nothing you dictated, copied or opened. Off until you turn it on."

    /// Says that signing out is not a reset. See `Docs/ux-settings-model.md`.
    static let signingOutKeepsEverything =
        "Signing out takes nothing away. Your history, your dictionary and these settings "
        + "are files on this Mac; resetting is the only thing that removes them."

    /// The privacy promise, written once for every screen. See `Docs/ux-settings-model.md`.
    static let privacyPromise =
        "\(recordingsPromise) The text is kept on this Mac until you delete it, or for the period you choose. We "
        + "never see it, and it is not tied to your account. Local history, clips, "
        + "suggestions and retry recordings kept on this Mac until deleted are excluded "
        + "from Mac backups that honour that setting."

    /// What happens to the audio, in the one wording every screen repeats. See `Docs/recordings.md`.
    public static let recordingsPromise =
        "Audio is deleted the moment it becomes text, and kept on this Mac for a day only "
        + "if some of it couldn’t be, so you can retry."

    /// How long the text of a dictation survives, offering only periods the store round-trips.
    private static func retentionRow(_ settings: Settings) -> SettingsRow {
        let days = settings.transcriptRetentionDays
        return SettingsRow(
            id: "transcripts",
            label: "Keep dictations for",
            explanation: "Choose a limit to delete older ones automatically",
            control: .menu(
                options: SettingsRetention.offeredDays.map { offered in
                    SettingsOption(
                        id: String(offered), title: SettingsRetention.title(days: offered),
                        change: .retention(days: offered))
                },
                selectedID: String(days)),
            icon: .symbol("clock", .info))
    }

    /// How long copied text and pictures stay in the clipboard history, and what keeps dictation clips apart.
    private static func clipboardRetentionRow(_ settings: Settings) -> SettingsRow {
        SettingsRow(
            id: "clipboardRetention",
            label: "Keep clipboard history for",
            explanation:
                "Dictation clips follow Keep transcripts for. Pinned, named and filed clips have no time limit.",
            control: .menu(
                options: SettingsRetention.offeredDays.map { offered in
                    SettingsOption(
                        id: String(offered), title: SettingsRetention.title(days: offered),
                        change: .clipboardRetention(days: offered))
                },
                selectedID: String(settings.clipboardRetentionDays)),
            icon: .symbol("list.clipboard", .info))
    }

    /// The fixed bounds the clipboard keeps within, read from the budget the store enforces.
    private static var clipboardLimitsRow: SettingsRow {
        let budget = ClipboardBudget.standard
        func size(_ bytes: Int) -> String { bytes.formatted(.byteCount(style: .file)) }
        let picture =
            budget.images.days.map { "Pictures are kept for \($0) days at most" } ?? "Pictures are limited"
        return SettingsRow(
            id: "clipboardLimits",
            label: "Clipboard limits",
            explanation:
                "Up to \(budget.copied.items) clips of each kind, \(size(budget.largestClip)) each. "
                + "\(picture), within \(size(budget.images.bytes)) of thumbnails and \(size(budget.disk)) of files. "
                + "The clip used least recently goes first.",
            control: .status("Fixed"),
            icon: .symbol("gauge.with.dots.needle.50percent", .info))
    }

    /// Clears the history and says what stays; the store call spares pinned, named and filed clips.
    private static var clearClipboardRow: SettingsRow {
        let kept = "Pinned, named and filed clips, your dictionary, snippets and settings stay."
        return SettingsRow(
            id: "clearClipboard",
            label: "Clear clipboard history",
            explanation: "Deletes copied text, pictures and dictation clips. \(kept)",
            control: .removal(
                SettingsRemoval(
                    reset: .clipboardHistory, title: "Clear…",
                    confirmation: SettingsConfirmation(
                        title: "Clear clipboard history?",
                        message: "This deletes every clip that is not pinned, named or filed. \(kept) "
                            + "This cannot be undone.",
                        confirmTitle: "Clear", cancelTitle: "Cancel"))),
            unavailability: SettingsEditor.unavailability(
                of: .clipboardHistory, given: .nothing),
            icon: .symbol("list.clipboard", .danger))
    }

    /// The name each store goes by in the Privacy pane; the key and the lock are the app's own, so they have none.
    static func storageLabel(_ entry: LocalStoreEntry) -> String? {
        switch entry {
        case .dictationHistory: "Dictations"
        case .recordings: "Recordings"
        case .personalDictionary: "Dictionary"
        case .snippets: "Snippets"
        case .evidenceLedger: "What Uttrflow has learned about you"
        case .predict: "AI suggestions"
        case .predictConsent: "AI suggestion choices"
        case .clipboard: "Clipboard history"
        case .clipboardImages: "Copied images"
        case .savedClips: "Saved clips"
        case .notSecretClips: "Clips marked not secret"
        case .clipboardPreferences: "Clipboard settings"
        case .networkActivity: "Network log"
        case .speechModels: "Speech recognition"
        case .speechModelLoads: "Speech start-up times"
        case .encryptionKey, .legacyMigrationMarker, .instanceLock: nil
        }
    }

}
