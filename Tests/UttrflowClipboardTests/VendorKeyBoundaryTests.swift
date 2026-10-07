import Testing

@testable import UttrflowClipboard
@testable import UttrflowCore

@Suite("Vendor key prefixes start at token boundaries")
struct VendorKeyBoundaryTests {
    @Test("matches vendor prefixes at token boundaries without matching embedded prefixes", .bug(id: 4956))
    func boundaries() {
        let prose = [
            "task-management-dashboard",
            "risk-assessment-framework",
            "desk-reservation-schedule",
            "myhf_Abcdefghijklmnop",
            "buildingnpm_abcdefghijklmnopqrstuvwxyzABCD",
            "designSG.Abcdefghijklmnop.QrstuvwxyzABCDEF",
        ]
        for text in prose {
            #expect(!SecretShapes.matches(text), "Must leave \(text) as ordinary text")
        }

        let keys = [
            "sk-proj-" + "Qv7RkT2mXeL9pAz4NbHc8FwJ",
            "hf_" + "A1b2C3d4E5f6G7h8I9j0K1l2M3n4O5p6",
            "npm_" + "A1b2C3d4E5f6G7h8I9j0K1l2M3n4O5p6",
            "SG." + "A1b2C3d4E5f6G7h8I9j0" + "." + "K1l2M3n4O5p6Q7r8",
        ]
        for key in keys {
            #expect(SecretShapes.matches(key))
            #expect(SecretShapes.matches("copy: \(key)"))
        }
    }
}
