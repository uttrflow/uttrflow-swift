// Tests for the steps as the rail beside the page draws them.
import Testing

@testable import UttrflowUX

/// The rail is SwiftUI and uncovered, so its order, names and `steps[position - 1]` are tested here.
struct OnboardingStepTests {
    @Test("names every step as a noun the rail can be scanned for")
    func everyStepHasARailTitle() {
        for step in OnboardingStep.allCases {
            #expect(!step.railTitle.isEmpty)
            // A rail title is a name, not the page's sentence: no full stops, and short enough for the rail.
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

    /// The rail highlights `inOrder[position - 1]`, so a wrong position lights the wrong row or crashes.
    @Test("puts each step at its own position in the list")
    func positionIndexesIntoTheList() {
        for step in OnboardingStep.allCases {
            #expect(OnboardingStep.inOrder[step.position - 1] == step)
        }
    }
}
