import Foundation
import Testing
import UttrflowCore

private enum SampleFailure: Error {
    case empty
    case carrying(String)
}

private struct SampleRecord: Error {
    let text: String
}

struct ErrorLogTests {
    @Test func aCaseWithoutPayloadIsNamedByTypeAndCase() {
        #expect(ErrorLog.failure(SampleFailure.empty) == "SampleFailure.empty")
    }

    @Test func aCaseWithPayloadKeepsOnlyItsLabel() {
        let line = ErrorLog.failure(SampleFailure.carrying("invented words"))
        #expect(line == "SampleFailure.carrying")
        #expect(!line.contains("invented"))
    }

    @Test func aStructIsNamedByTypeDomainAndCode() {
        let line = ErrorLog.failure(SampleRecord(text: "invented words"))
        #expect(line.hasPrefix("SampleRecord domain="))
        #expect(!line.contains("invented"))
    }
}
