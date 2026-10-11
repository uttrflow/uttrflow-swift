import struct Foundation.ByteCountFormatStyle
import struct Foundation.Date
import UttrflowCore
import UttrflowSettings

extension SettingsPresenter {
    /// One read-only row per store a person would recognise, saying what it occupies on this Mac.
    static func storageRows(_ storage: [LocalStoreUsage], settings: Settings = .default) -> [SettingsRow] {
        storage.sorted { storageRank($0.entry) < storageRank($1.entry) }.compactMap { usage in
            storageLabel(usage.entry).map { label in
                SettingsRow(
                    id: "storage.\(usage.entry.rawValue)",
                    label: label,
                    explanation: storageExplanation(usage, settings: settings),
                    control: .status(usage.bytes.formatted(.byteCount(style: .file))))
            }
        }
    }

    /// How many files a store holds, how old the oldest is, and the rule that removes them, when one exists.
    static func storageExplanation(_ usage: LocalStoreUsage, settings: Settings) -> String {
        var parts: [String] = []
        if usage.files == 0 {
            parts.append("Nothing stored")
        } else {
            parts.append(counted(usage.files, "file", "files"))
            if let oldest = usage.oldest {
                parts.append("oldest from \(oldest.formatted(date: .abbreviated, time: .omitted))")
            }
        }
        if let rule = storageRetention(usage.entry, settings: settings) { parts.append(rule) }
        return parts.joined(separator: ". ")
    }

    /// The retention each store is swept by, named only where a setting or a fixed period decides it.
    private static func storageRetention(_ entry: LocalStoreEntry, settings: Settings) -> String? {
        switch entry {
        case .dictationHistory: keepRule(days: settings.transcriptRetentionDays)
        case .clipboard: keepRule(days: settings.clipboardRetentionDays)
        case .recordings: "Deleted after 24 hours"
        default: nil
        }
    }

    private static func keepRule(days: Int) -> String {
        SettingsRetention.isAlways(days: days)
            ? "Kept until you delete it" : "Deleted after \(SettingsRetention.title(days: days))"
    }

    /// Where a store sits in the list: the order ``storageLabel(_:)`` names them in, speech first.
    private static func storageRank(_ entry: LocalStoreEntry) -> Int {
        storageOrder.firstIndex(of: entry) ?? storageOrder.count
    }

    private static let storageOrder: [LocalStoreEntry] = [
        .dictationHistory, .recordings, .personalDictionary, .snippets, .evidenceLedger, .predict,
        .predictConsent, .clipboard, .clipboardImages, .savedClips, .notSecretClips, .clipboardPreferences,
        .networkActivity,
        .speechModels, .speechModelLoads,
    ]
}
