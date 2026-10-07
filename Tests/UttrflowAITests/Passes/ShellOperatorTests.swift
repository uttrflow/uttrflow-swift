import Testing
import UttrflowCore

@testable import UttrflowAI

@Suite("Spoken pipes and redirects at a command line")
struct ShellOperatorTests {
    private func run(_ spoken: String, in destination: Destination) -> String {
        let app = AppContext(applicationName: "Terminal", bundleIdentifier: "com.apple.Terminal")
        let situation = Situation(app: app, insertion: app.insertionPoint, destination: destination)
        return CleaningPipeline.beforeModel(for: .standard(for: destination), situation: situation)
            .run(Draft(text: spoken)).text
    }

    @Test("writes a pipe, a redirect and an append in a terminal")
    func terminalOperators() {
        #expect(run("ls pipe grep notes", in: .terminal) == "ls | grep notes")
        #expect(run("echo done greater than out.txt", in: .terminal) == "echo done > out.txt")
        #expect(run("echo done double greater than log.txt", in: .terminal) == "echo done >> log.txt")
    }

    @Test("keeps the words in prose and leaves terminal brackets to the marks")
    func proseUnchanged() {
        let prose = "the pipe is greater than the hose"
        #expect(run(prose, in: .document) == prose)
        #expect(!run("echo open paren close paren", in: .terminal).contains("()"))
    }
}
