// Shared fixtures for the clipboard tests.

import Foundation
import Testing

@testable import UttrflowClipboard

/// A fixed instant, so no result depends on the clock the test ran under.
let noon = Date(timeIntervalSince1970: 1_700_000_000)

/// Seven days of history, reckoned back from `now`.
func week(from now: Date = noon) -> ClipRetention { ClipRetention(days: 7, now: now) }

/// A temporary file, gone when the test that made it is.
struct TemporaryFile: ~Copyable {
    let url: URL

    init(named name: String = UUID().uuidString) {
        url = URL.temporaryDirectory
            .appending(path: "UttrflowClipboardTests/\(UUID().uuidString)/\(name)")
    }

    deinit {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }
}

/// A store over its own temporary folder, removed with the test.
struct TemporaryFolder: ~Copyable {
    let url: URL
    let store: ClipboardStore
    let retention = week(from: .now)

    init() throws {
        url = URL.temporaryDirectory.appending(
            path: "uttrflow-clipboard-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        store = ClipboardStore(
            file: url.appending(path: "clipboard.json", directoryHint: .notDirectory))
    }

    deinit { try? FileManager.default.removeItem(at: url) }
}

extension ClipboardBudget {
    /// The same budget with one bound narrowed in every pool, so a test names only the rule it is about.
    func limiting(
        items: Int? = nil, bytes: Int? = nil, days: Int? = nil, largestClip: Int? = nil,
        disk: Int? = nil
    ) -> ClipboardBudget {
        func narrowed(_ tier: ClipboardTier) -> ClipboardTier {
            ClipboardTier(
                bytes: bytes ?? tier.bytes, items: items ?? tier.items, days: days ?? tier.days)
        }
        return ClipboardBudget(
            ceiling: ceiling, copied: narrowed(copied), dictation: narrowed(dictation),
            images: narrowed(images), largestClip: largestClip ?? self.largestClip,
            disk: disk ?? self.disk)
    }
}
