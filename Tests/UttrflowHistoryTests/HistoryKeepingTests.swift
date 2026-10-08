import Testing
import UttrflowHistory

@Suite("Which dictations history may keep")
struct HistoryKeepingTests {
    @Test("the default keeps every dictation, known app or not")
    func everythingKeepsAll() {
        #expect(HistoryKeeping.everything.keeps(applicationIdentifier: "com.example.records"))
        #expect(HistoryKeeping.everything.keeps(applicationIdentifier: nil))
    }

    @Test("a listed app is forgotten whatever the identifier's case, others are kept")
    func listedAppIsForgotten() {
        let keeping = HistoryKeeping(excludedApplications: ["com.example.Records"])
        #expect(!keeping.keeps(applicationIdentifier: "COM.EXAMPLE.RECORDS"))
        #expect(keeping.keeps(applicationIdentifier: "com.example.editor"))
        #expect(keeping.keeps(applicationIdentifier: nil))
    }

    @Test("keeping nothing forgets every dictation, an unknown app included")
    func keepsNothingForgetsAll() {
        let keeping = HistoryKeeping(keepsNothing: true)
        #expect(!keeping.keeps(applicationIdentifier: "com.example.editor"))
        #expect(!keeping.keeps(applicationIdentifier: nil))
    }
}
