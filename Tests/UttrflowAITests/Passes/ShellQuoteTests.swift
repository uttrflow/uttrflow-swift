import Testing
import UttrflowCore

@testable import UttrflowAI

@Suite("A spoken quote around an argument at a command line")
struct ShellQuoteTests {
    private func run(_ spoken: String, in destination: Destination) -> String {
        let app = AppContext(applicationName: "Terminal", bundleIdentifier: "com.apple.Terminal")
        let situation = Situation(app: app, insertion: app.insertionPoint, destination: destination)
        return CleaningPipeline.beforeModel(for: .standard(for: destination), situation: situation)
            .run(Draft(text: spoken)).text
    }

    @Test("closes a quotation a bare quote opened with a second bare quote")
    func barePair() {
        let spoken = "git commit dash m quote fix the build quote"
        #expect(run(spoken, in: .terminal) == "git commit -m \"fix the build\"")
        #expect(run("echo open quote a quote b close quote", in: .terminal) == "echo \"a quote b\"")
    }

    @Test("keeps a quote after a determiner, and the words where nothing pairs or outside a terminal")
    func wordsStay() {
        #expect(
            run("git commit dash m quote fix the quote parser quote", in: .terminal)
                == "git commit -m \"fix the quote parser\"")
        #expect(run("can you quote me a price", in: .terminal) == "can you quote me a price")
        #expect(run("i need the quote for the quote", in: .terminal) == "i need the quote for the quote")
        #expect(run("echo quote hello quote", in: .document) == "echo quote hello quote")
    }

    @Test("quotes a pattern only where a quote is said, so an unquoted glob or variable still expands")
    func expansionKept() {
        #expect(run("ls *.txt", in: .terminal) == "ls *.txt")
        #expect(run("rm -f *.log pipe wc -l", in: .terminal) == "rm -f *.log | wc -l")
        #expect(run("echo $HOME", in: .terminal) == "echo $HOME")
        #expect(run("find dot dash name quote *.swift quote", in: .terminal).hasSuffix("\"*.swift\""))
        #expect(run("echo quote $HOME quote", in: .terminal) == "echo \"$HOME\"")
    }
}
