import Darwin
import Foundation
import Testing

@testable import UttrflowLocalModel

@Suite("Token healing vocabulary measurements")
struct TokenHealingPerformanceTests {
    @Test("Probe: record init and first prefix lookup for a 262k-token vocabulary")
    func largeVocabularyInitializationAndLookup() throws {
        guard ProcessInfo.processInfo.environment["UTTRFLOW_TOKEN_PREFIX_BENCHMARK"] == "1" else {
            return
        }

        let bytes = (0..<262_144).map(Self.tokenBytes)
        let before = try #require(Self.footprintBytes())
        let clock = ContinuousClock()
        var vocabulary: TokenHealing.Vocabulary?
        let initialization = clock.measure {
            vocabulary = TokenHealing.Vocabulary(bytes: bytes, ending: [])
        }
        let afterInitialization = try #require(Self.footprintBytes())
        let owed = bytes[0]
        let firstLookup = clock.measure {
            _ = vocabulary?.allowedIDs(owing: owed, wordComplete: false)
        }
        let afterLookup = try #require(Self.footprintBytes())
        let totalFootprintDelta = afterLookup - before

        print(
            "token-prefix-probe tokens=262144 bytesPerToken=5 init=\(initialization) initFootprintDelta=\(afterInitialization - before)B firstLookup=\(firstLookup) lookupFootprintDelta=\(afterLookup - afterInitialization)B totalFootprintDelta=\(totalFootprintDelta)B"
        )
        #expect(vocabulary?.allowedIDs(owing: owed, wordComplete: false).isEmpty == false)
        #expect(
            initialization + firstLookup <= .milliseconds(500),
            "vocabulary initialization plus first index build must stay within 500 ms"
        )
        #expect(
            totalFootprintDelta <= 32 * 1_024 * 1_024,
            "vocabulary initialization plus prefix index must stay within 32 MiB"
        )
    }

    private static func tokenBytes(_ id: Int) -> [UInt8] {
        let alphabet = Array("0123456789abcdefghijklmnopqrstuvwxyz".utf8)
        var value = id
        var bytes = [UInt8](repeating: alphabet[0], count: 5)
        for index in bytes.indices.reversed() {
            bytes[index] = alphabet[value % alphabet.count]
            value /= alphabet.count
        }
        return bytes
    }

    private static func footprintBytes() -> Int? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return status == KERN_SUCCESS ? Int(info.phys_footprint) : nil
    }
}
