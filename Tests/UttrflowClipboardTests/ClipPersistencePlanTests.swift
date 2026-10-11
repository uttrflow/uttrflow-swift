// Synthetic clip values exercise the saved-index transition calculations.

import Testing

@testable import UttrflowClipboard

@Suite("Planning saved-index contents")
struct ClipPersistencePlanTests {
    private func clip(_ text: String) -> Clip {
        Clip(text: text, kind: .text, copiedAt: noon, source: "FixtureEditor", lastUsedOrder: 4)
    }

    @Test("without a departing saved clip, every kept record stays in input order")
    func keptRecords() {
        let history = clip("Synthetic history")
        let named = clip("Synthetic named").with { $0.alias = "/synthetic" }
        let tagged = clip("Synthetic tagged").with { $0.tags = ["synthetic"] }
        let filed = clip("Synthetic filed").with { $0.category = "Synthetic collection" }
        let pinned = clip("Synthetic pinned").with { $0.isPinned = true }
        let result = ClipPersistencePlan.bridging(
            [history, named, tagged, filed, pinned], from: [], into: [history])
        #expect(result == [named, tagged, filed, pinned])
    }

    @Test("a clip returning to history keeps its complete saved copy in the bridge")
    func departingSavedCopy() {
        let previous = clip("Synthetic saved").with {
            $0.isPinned = true
            $0.richText = "<p>Synthetic saved</p>"
            $0.timesCopied = 7
        }
        let departing = previous.with {
            $0.isPinned = false
            $0.text = "Synthetic edited history"
            $0.richText = nil
            $0.timesCopied = 8
        }
        let history = clip("Synthetic other history")
        let arriving = clip("Synthetic arriving").with { $0.tags = ["synthetic"] }
        let result = ClipPersistencePlan.bridging(
            [history, departing, arriving], from: [previous], into: [history, departing])
        #expect(result == [previous, arriving])
    }

    @Test("duplicate saved identities bridge the first complete copy")
    func firstSavedCopy() {
        let previous = clip("Synthetic first copy").with { $0.isPinned = true }
        let duplicate = previous.with { $0.text = "Synthetic later copy" }
        let departing = previous.with { $0.isPinned = false }
        #expect(
            ClipPersistencePlan.bridging(
                [departing], from: [previous, duplicate], into: [departing]) == [previous])
    }

    @Test("a removed saved clip is absent while another returns to history")
    func removedSavedCopy() {
        let removed = clip("Synthetic removed").with { $0.isPinned = true }
        let previous = clip("Synthetic retained").with { $0.isPinned = true }
        let departing = previous.with { $0.isPinned = false }
        #expect(
            ClipPersistencePlan.bridging(
                [departing], from: [removed, previous], into: [departing]) == [previous])
    }

    @Test("complete equal records match independent of order, including empty lists")
    func orderIndependentEquality() {
        let first = clip("Synthetic first").with { $0.richText = "<p>Synthetic first</p>" }
        let second = clip("Synthetic second").with { $0.tags = ["synthetic"] }
        #expect(ClipPersistencePlan.holdsTheSameClips([first, second], as: [second, first]))
        #expect(ClipPersistencePlan.holdsTheSameClips([], as: []))
    }

    @Test("changed records, missing identities and different list sizes do not match")
    func differentRecords() {
        let original = clip("Synthetic original")
        let changed = original.with { $0.lastUsedOrder = 5 }
        let other = clip("Synthetic original")
        #expect(!ClipPersistencePlan.holdsTheSameClips([original], as: [changed]))
        #expect(!ClipPersistencePlan.holdsTheSameClips([original], as: [other]))
        #expect(!ClipPersistencePlan.holdsTheSameClips([original], as: []))
    }

    @Test("duplicate identities retain the comparison's existing list asymmetry")
    func duplicateListAsymmetry() {
        let first = clip("Synthetic first")
        let second = clip("Synthetic second")
        #expect(!ClipPersistencePlan.holdsTheSameClips([first, second], as: [first, first]))
        #expect(!ClipPersistencePlan.holdsTheSameClips([first, first], as: [first, first]))
        #expect(ClipPersistencePlan.holdsTheSameClips([first, first], as: [first, second]))
    }
}
