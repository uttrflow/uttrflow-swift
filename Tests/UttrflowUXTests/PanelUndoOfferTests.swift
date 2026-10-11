import Foundation
import Testing
import UttrflowClipboard

@testable import UttrflowUX

@MainActor
@Suite("PanelUndoOffer")
struct PanelUndoOfferTests {
    private func clip(_ text: String) -> Clip {
        Clip(text: text, kind: .text, copiedAt: Date(timeIntervalSince1970: 0), source: nil)
    }

    @Test("two overlapping deletes leave the offer describing the later one")
    func overlappingDeletes() {
        var offer = PanelUndoOffer()
        let first = clip("first")
        let second = clip("second")
        let firstTicket = offer.offer([first])
        let secondTicket = offer.offer([second])
        #expect(offer.clip == second)
        #expect(!offer.isLatest(firstTicket))
        #expect(offer.isLatest(secondTicket))
    }

    @Test("one offer can restore every clip removed together")
    func offerRestoresAGroup() {
        var offer = PanelUndoOffer()
        let clips = [clip("first"), clip("second")]
        _ = offer.offer(clips)

        let claim = offer.claimForRestore()

        #expect(claim?.clips == clips)
        #expect(offer.clips.isEmpty)
    }

    @Test("a withdrawn offer supersedes a delete still in flight")
    func withdrawSupersedes() {
        var offer = PanelUndoOffer()
        let ticket = offer.offer([clip("gone")])
        offer.withdraw()
        #expect(offer.clip == nil)
        #expect(!offer.isLatest(ticket))
    }

    @Test("a delete gate remembers completion before its waiter arrives")
    func deleteGateCompletesBeforeWait() async {
        let gate = DeleteGate()
        await gate.finishDelete()
        await gate.wait()
    }

    @Test("an undo during delete waits for that delete before restoring")
    func undoWaitsForDelete() async {
        var offer = PanelUndoOffer()
        let clip = clip("gone")
        let ticket = offer.offer([clip])
        let gate = DeleteGate()
        let deletion = Task {
            await gate.wait()
            return Result<Void, ClipboardStoreError>.success(())
        }
        offer.trackDelete(deletion, ticket: ticket)

        let claim = offer.claimForRestore()
        #expect(claim?.clip == clip)
        #expect(claim?.clips == [clip])
        #expect(offer.clip == nil)

        let restoreSignal = RestoreSignal()
        let restore = Task {
            await restoreSignal.willWaitForDelete()
            try? await claim?.waitForDelete()
            await restoreSignal.restore(clip)
        }
        await gate.waitingForDelete
        await restoreSignal.isWaitingForDelete
        #expect(await restoreSignal.restoredClip == nil)
        await gate.finishDelete()
        await restore.value

        #expect(await restoreSignal.restoredClip == clip)
    }

    @Test("expiry withdraws the offer before picture release can finish")
    func expiryWithdrawsBeforePictureRelease() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "panel-undo-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ClipboardStore(file: directory.appending(path: "clipboard.json"))
        let now = Date(timeIntervalSince1970: 0)
        let retention = ClipRetention(days: 30, now: now)
        let bytes = Data(repeating: 0x89, count: 2_048)
        let incoming = NoticedClip(
            clip: Clip(text: "", kind: .image, copiedAt: now), picture: (bytes, 1, 1))
        _ = try await store.record(incoming, keeping: retention)
        let clip = try #require(await store.clips(keeping: retention).first)
        let image = try #require(clip.image)
        _ = try await store.delete(clip.id, keeping: retention, holdingPicture: true)
        #expect(await store.imageData(for: image) == bytes)

        var offer = PanelUndoOffer()
        _ = offer.offer([clip])
        let release = ReleaseGate()
        let expiry = Task {
            await PanelUndoExpiry.expire(
                withdraw: { offer.withdraw() },
                releasingPictures: {
                    await release.didWithdraw()
                    await release.wait()
                    await store.forgetHeldPictures()
                })
        }

        await release.withdrawalCompleted
        #expect(offer.clip == nil)
        #expect(offer.pendingDelete == nil)
        let unavailableDuringRelease = offer.claimForRestore()
        #expect(unavailableDuringRelease?.clip == nil)
        #expect(await store.imageData(for: image) == bytes)
        await release.finish()
        await expiry.value
        #expect(await store.imageData(for: image) == nil)
        let unavailableAfterRelease = offer.claimForRestore()
        #expect(unavailableAfterRelease?.clip == nil)
    }
}

private actor DeleteGate {
    private var deleteContinuation: CheckedContinuation<Void, Never>?
    private var waitingContinuation: CheckedContinuation<Void, Never>?
    private var isComplete = false
    private(set) var isWaiting = false

    func wait() async {
        guard !isComplete else { return }
        await withCheckedContinuation { continuation in
            deleteContinuation = continuation
            isWaiting = true
            waitingContinuation?.resume()
            waitingContinuation = nil
        }
    }

    func finishDelete() {
        isComplete = true
        deleteContinuation?.resume()
        deleteContinuation = nil
    }

    var waitingForDelete: Void {
        get async {
            if isWaiting { return }
            await withCheckedContinuation { waitingContinuation = $0 }
        }
    }
}

private actor RestoreSignal {
    private(set) var restoredClip: Clip?
    private var waitingContinuation: CheckedContinuation<Void, Never>?
    private(set) var isWaiting = false

    func willWaitForDelete() {
        isWaiting = true
        waitingContinuation?.resume()
        waitingContinuation = nil
    }

    func restore(_ clip: Clip) { restoredClip = clip }

    var isWaitingForDelete: Void {
        get async {
            if isWaiting { return }
            await withCheckedContinuation { waitingContinuation = $0 }
        }
    }
}

private actor ReleaseGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var withdrawalContinuation: CheckedContinuation<Void, Never>?
    private(set) var withdrawal = false
    private var isComplete = false

    func didWithdraw() {
        withdrawal = true
        withdrawalContinuation?.resume()
        withdrawalContinuation = nil
    }

    var withdrawalCompleted: Void {
        get async {
            if withdrawal { return }
            await withCheckedContinuation { withdrawalContinuation = $0 }
        }
    }

    func wait() async {
        guard !isComplete else { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func finish() {
        isComplete = true
        continuation?.resume()
        continuation = nil
    }
}
