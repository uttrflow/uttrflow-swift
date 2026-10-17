import Foundation
import Testing
import UttrflowTestSupport

@testable import UttrflowAI
@testable import UttrflowCore

@Suite("ZzProbeFile")
struct ZzProbeFileTests {
    @Test("run")
    func run() async throws {
        let dir = "/private/tmp/claude-501/scratch"
        guard let input = try? String(contentsOfFile: dir + "/in.txt", encoding: .utf8) else { return }
        var out = ""
        for line in input.split(separator: "\n") {
            let parts = line.split(separator: "|", maxSplits: 1).map(String.init)
            let (dests, spoken) = parts.count == 2 ? (parts[0].split(separator: ",").map(String.init), parts[1]) : (["plain"], String(line))
            for d in dests {
                let dest = Destination(rawValue: d) ?? .plain
                let app = AppContext()
                let situation = Situation(app: app, insertion: app.insertionPoint, destination: dest)
                let request = TransformationRequest(transcription: .fixture(text: spoken, language: .english), situation: situation)
                let result = try await RuleBasedTransformer().transform(request)
                let ledger = (result.changeLedger ?? []).map { "\($0.pass.rawValue):\($0.kind.rawValue)@\($0.writtenIndex)" }.joined(separator: " ")
                out += "[\(d)] \(spoken)\n   => \(result.text)\n   ## \(ledger)\n"
            }
        }
        try out.write(toFile: dir + "/out.txt", atomically: true, encoding: .utf8)
    }
}
