import Testing
import UttrflowCore

@testable import UttrflowAI

/// Issue #7923: an ssh-style remote, a user at a host then a colon and a path, is written as one word.
@Suite("An ssh-style remote is written as one word", .bug(id: 7923))
struct SshRemoteTests {
    private static let terminal = AppContext(
        applicationName: "Terminal", bundleIdentifier: "com.apple.Terminal")

    private static func cleaned(_ spoken: String) -> String {
        let situation = SituationResolver.resolve(from: terminal)
        let formatter = DestinationFormatter.standard(for: situation.destination)
        return CleaningPipeline.standard(for: formatter, situation: situation)
            .run(Draft(text: spoken)).text
    }

    @Test(
        "a remote joins its user, host, colon and path",
        arguments: [
            (
                "git clone git at git dot example dot com colon acme slash widgets dot git",
                "git clone git@git.example.com:acme/widgets.git"
            ),
            (
                "scp file dot txt me at host dot example dot com colon slash tmp",
                "scp file.txt me@host.example.com:/tmp"
            ),
        ])
    func remote(spoken: String, written: String) {
        #expect(Self.cleaned(spoken) == written)
    }
}
