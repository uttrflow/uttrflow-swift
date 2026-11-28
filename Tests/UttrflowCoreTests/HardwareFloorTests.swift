import Testing

@testable import UttrflowCore

@Suite("The supported-hardware floor")
struct HardwareFloorTests {
    private static let gigabyte: Int64 = 1_073_741_824

    @Test("an Apple silicon Mac at or above the minimum memory is supported")
    func supported() {
        #expect(HardwareFloor.classify(isAppleSilicon: true, physicalMemory: 8 * Self.gigabyte) == .supported)
        #expect(
            HardwareFloor.classify(isAppleSilicon: true, physicalMemory: 36 * Self.gigabyte) == .supported)
    }

    @Test("an Apple silicon Mac below the minimum memory dictates but is slow")
    func slow() {
        #expect(
            HardwareFloor.classify(isAppleSilicon: true, physicalMemory: 8 * Self.gigabyte - 1)
                == .slow(.memoryBelowMinimum))
    }

    @Test("a Mac without Apple silicon is unsupported whatever its memory")
    func unsupported() {
        #expect(
            HardwareFloor.classify(isAppleSilicon: false, physicalMemory: 64 * Self.gigabyte)
                == .unsupported(.notAppleSilicon))
        #expect(
            HardwareFloor.classify(isAppleSilicon: false, physicalMemory: 4 * Self.gigabyte)
                == .unsupported(.notAppleSilicon))
    }

    @Test("the Mac running the tests is read without failing")
    func current() {
        #expect(HardwareFloor.current() != .unsupported(.memoryBelowMinimum))
    }
}
