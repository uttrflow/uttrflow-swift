import Testing

@testable import UttrflowUX

/// The seven steps as the rail beside the page draws them.
///
/// The rail is SwiftUI and is not covered, so what it reads — the order, the names, and
/// the fact that the position it highlights indexes into that order — is tested here
/// instead. The rail's one arithmetic act is `steps[position - 1]`, and everything below
/// exists so that it cannot be reached with a position that has no step.
struct OnboardingStepTests {
    @Test("names every step as a noun the rail can be scanned for")
    func everyStepHasARailTitle() {
        for step in OnboardingStep.allCases {
            #expect(!step.railTitle.isEmpty)
            // A rail title is a name, not the page's own sentence: no full stops, and
            // short enough for the rail's width at 12.5 points.
            #expect(!step.railTitle.contains("."))
            #expect(step.railTitle.count <= 18)
        }
    }

    @Test("gives every step a different name")
    func theNamesAreDistinct() {
        let names = Set(OnboardingStep.allCases.map(\.railTitle))
        #expect(names.count == OnboardingStep.count)
    }

    @Test("orders the steps by the position the rest of the flow numbers them with")
    func theListIsInPositionOrder() {
        #expect(OnboardingStep.inOrder.map(\.position) == Array(1...OnboardingStep.count))
    }

    @Test("holds every step exactly once")
    func theListIsWholeAndHasNoRepeats() {
        #expect(OnboardingStep.inOrder.count == OnboardingStep.count)
        #expect(Set(OnboardingStep.inOrder) == Set(OnboardingStep.allCases))
    }

    /// The rail highlights `inOrder[position - 1]`, so a position that did not index its
    /// own step would light the wrong row — or, at one past the end, crash the window.
    @Test("puts each step at its own position in the list")
    func positionIndexesIntoTheList() {
        for step in OnboardingStep.allCases {
            #expect(OnboardingStep.inOrder[step.position - 1] == step)
        }
    }
}
