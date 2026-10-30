// Tests for the shipped banking and health families and how an identifier is matched to one.

import Testing

@testable import UttrflowCore

@Suite("Banking and health application families")
struct SensitiveApplicationsTests {
    @Test("matches the family's own identifier and any build that continues it after a dot")
    func matchesByFamily() {
        let family = ApplicationFamily(prefix: "Com.Example.Bank", name: "Example Bank")
        #expect(family.prefix == "com.example.bank")
        #expect(family.contains("com.example.bank"))
        #expect(family.contains("COM.EXAMPLE.BANK.Beta"))
        #expect(!family.contains("com.example.bankers"))
        #expect(!family.contains("com.example"))
    }

    @Test("finds the shipped family an identifier belongs to, and none for an ordinary app")
    func findsShippedFamily() {
        #expect(SensitiveApplications.family(of: "com.chase.mobile")?.prefix == "com.chase")
        #expect(SensitiveApplications.family(of: "com.apple.health")?.name == "Health")
        #expect(SensitiveApplications.family(of: "com.example.notes") == nil)
    }
}
