import Foundation
import Testing

@testable import UttrflowContext

@Suite struct SurfaceProbeOwnerTests {
    @Test func acceptsAFieldOwnedByTheRequestedApplication() {
        #expect(SurfaceProbe.owns(42, 42, current: 7))
    }

    @Test func refusesASystemWideFieldOwnedByAnotherProcess() {
        #expect(!SurfaceProbe.owns(7, 42, current: 7))
        #expect(!SurfaceProbe.owns(99, 42, current: 7))
    }

    @Test func refusesAFieldWhoseOwnerIsUnknown() {
        #expect(!SurfaceProbe.owns(nil, 42, current: 7))
    }

    @Test func refusesUttrflowsOwnProcessEvenWhenAskedForIt() {
        #expect(!SurfaceProbe.owns(7, 7, current: 7))
    }

    @Test func neverReadsAFieldWhenAskedAboutItsOwnProcess() {
        #expect(SurfaceProbe.focusedField(of: getpid()) == nil)
    }
}
