import UttrflowClipboard

/// Orders panel list reads and publishes only the most recent refresh.
@MainActor
final class PanelListRefreshCoordinator {
    private var reads = 0

    struct Readers {
        let clips: () async -> [Clip]
        let reportUnreadable: () async -> Void
        let facts: ([Clip]) async -> PanelListFacts
    }

    func refresh(
        using recordedClips: [Clip]? = nil, readers: Readers,
        publish: ([Clip], PanelListFacts) -> Void
    ) async {
        reads += 1
        let read = reads
        let clips: [Clip]
        if let recordedClips {
            clips = recordedClips
        } else {
            clips = await readers.clips()
            await readers.reportUnreadable()
        }
        let facts = await readers.facts(clips)
        // A read that started earlier never replaces a newer list.
        guard read == reads else { return }
        publish(clips, facts)
    }
}
